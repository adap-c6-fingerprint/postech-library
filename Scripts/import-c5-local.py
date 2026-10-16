#!/usr/bin/env python3
"""Copy the locally held C5 evaluation data without redistributing it in Git."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRECTORY = Path("Fingerprint/App/Domain/IMDF/C5/IMDFData")
EXPECTED_FILES = {
    "manifest.json", "address.geojson", "venue.geojson", "building.geojson",
    "footprint.geojson", "level.geojson", "unit.geojson", "fixture.geojson",
    "opening.geojson", "amenity.geojson", "anchor.geojson", "occupant.geojson",
    "LICENSE/LICENSE.txt",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_output(source, *arguments):
    return subprocess.check_output(["git", "-C", str(source), *arguments], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=PROJECT_ROOT.parent / "2026-C6-M06-Fingerprint")
    parser.add_argument("--replace", action="store_true", help="명시적으로 기존 로컬 복사본을 교체합니다.")
    args = parser.parse_args()
    source = args.source.expanduser().resolve()
    original = source / SOURCE_DIRECTORY
    destination = PROJECT_ROOT / "fingerprint-library/Resources/IndoorMaps/C5"

    if not original.is_dir():
        parser.error(f"C5 IMDF 폴더가 없습니다: {original}")
    if any(path.is_symlink() for path in original.rglob("*")):
        parser.error("C5 원본에 심볼릭 링크가 있습니다. 일반 파일로 준비해주세요.")
    actual_files = {str(path.relative_to(original)) for path in original.rglob("*") if path.is_file()}
    if actual_files != EXPECTED_FILES:
        parser.error(f"예상 파일 묶음과 다릅니다. 누락={EXPECTED_FILES - actual_files}, 추가={actual_files - EXPECTED_FILES}")

    # 원본은 읽기만 한다. 커밋되지 않은 C5 변경도 해시와 함께 기록한다.
    hashes = {name: digest(original / name) for name in sorted(EXPECTED_FILES)}
    record = {
        "dataset_id": "c5",
        "source_project": source.name,
        "source_commit": git_output(source, "rev-parse", "HEAD"),
        "source_directory": str(SOURCE_DIRECTORY),
        "source_worktree_changes": git_output(source, "diff", "HEAD", "--name-only", "--", str(SOURCE_DIRECTORY)).splitlines(),
        "files_sha256": hashes,
    }
    existing = destination / "IMDFData"
    if destination.is_symlink() or existing.is_symlink():
        parser.error("대상 C5 폴더에 심볼릭 링크를 사용할 수 없습니다.")
    if existing.exists() and not args.replace:
        existing_files = {str(path.relative_to(existing)) for path in existing.rglob("*") if path.is_file()}
        if existing_files != EXPECTED_FILES or any(digest(existing / name) != value for name, value in hashes.items()):
            parser.error("로컬 복사본이 원본과 다릅니다. 내용을 확인한 뒤 --replace로 교체해주세요.")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="c5-import-", dir=destination.parent) as temporary:
        staged = Path(temporary) / "C5"
        shutil.copytree(original, staged / "IMDFData")
        if any(digest(staged / "IMDFData" / name) != value for name, value in hashes.items()):
            raise RuntimeError("복사 중 원본이 바뀌었습니다. 가져오기를 다시 실행해주세요.")
        (staged / "source.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        if destination.exists():
            backup = Path(temporary) / "previous"
            destination.rename(backup)
            try:
                staged.rename(destination)
            except BaseException:
                backup.rename(destination)
                raise
        else:
            staged.rename(destination)
    print(f"C5 {len(hashes)}개 파일을 로컬 평가용으로 가져왔습니다: {destination}")
    print("원본 데이터와 source.json은 Git 제외 대상입니다. 외부 배포물에 포함하지 마세요.")


if __name__ == "__main__":
    main()
