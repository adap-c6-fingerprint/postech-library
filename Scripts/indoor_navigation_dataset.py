#!/usr/bin/env python3
"""이미 준비된 IMDF·그래프·서가 자료의 dataset.json을 생성한다. 원본 자료는 수정하지 않는다."""

import argparse
import hashlib
import json
from pathlib import Path


REQUIRED_MAP_FILES = (
    "manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
    "unit.geojson", "fixture.geojson", "opening.geojson",
)
OPTIONAL_MAP_FILES = ("amenity.geojson", "section.geojson")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def map_hashes(directory):
    """필수 파일과 실제로 존재하는 선택 파일을 빠짐없이 고정한다."""
    names = REQUIRED_MAP_FILES + tuple(name for name in OPTIONAL_MAP_FILES if (directory / name).exists())
    return {name: digest(directory / name) for name in sorted(names)}


def build_manifest(directory):
    """schema 1 자료의 식별자를 확인하고 지도·경로·서가·선택적 층간 거리 해시를 묶는다."""
    graph = json.loads((directory / "routing-graph.geojson").read_text())
    shelves = json.loads((directory / "shelves.json").read_text())
    layout = graph.get("layout_version")
    dataset = shelves.get("dataset_id")
    if (graph.get("schema_version") != 1 or shelves.get("schema_version") != 1
            or not isinstance(layout, str) or not layout.strip()
            or not isinstance(dataset, str) or not dataset.strip()
            or shelves.get("layout_version") != layout):
        raise ValueError("그래프·서가의 schema 1, dataset_id와 layout_version을 확인하세요.")
    manifest = {
        "schema_version": 1, "dataset_id": dataset, "layout_version": layout,
        "map_files_sha256": map_hashes(directory / "IMDFData"),
        "routing_sha256": digest(directory / "routing-graph.geojson"),
        "shelves_sha256": digest(directory / "shelves.json"),
    }
    distances = directory / "cross-floor-distances.json"
    if distances.exists():
        metadata = json.loads(distances.read_text())
        if (metadata.get("schema_version") != 1 or metadata.get("dataset_id") != dataset
                or metadata.get("layout_version") != layout):
            raise ValueError("층간 거리 자료의 schema·데이터셋·개정이 일치하지 않습니다.")
        manifest["cross_floor_distances_sha256"] = digest(distances)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True, help="IMDFData·routing-graph.geojson·shelves.json이 있는 폴더")
    parser.add_argument("--replace", action="store_true", help="검토 후 기존 dataset.json을 다시 생성합니다.")
    args = parser.parse_args()
    directory = args.directory.expanduser().resolve()
    output = directory / "dataset.json"
    try:
        manifest = build_manifest(directory)
        if output.exists():
            previous = json.loads(output.read_text())
            # 갱신 대상이 아닌 출처 등 추가 메타데이터는 보존한다.
            generated_keys = set(manifest) | {"cross_floor_distances_sha256"}
            manifest.update({key: value for key, value in previous.items() if key not in generated_keys})
            if manifest == previous:
                print(f"데이터셋 해시가 이미 일치합니다: {output}")
                return
            if not args.replace:
                parser.error("기존 데이터셋과 자료가 다릅니다. 묶음을 검토한 뒤 --replace로 다시 생성하세요.")
        output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"지도 {len(manifest['map_files_sha256'])}개 파일과 길찾기 자료의 해시를 기록했습니다: {output}")


if __name__ == "__main__":
    main()
