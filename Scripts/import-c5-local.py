#!/usr/bin/env python3
"""Refresh C5 development data while preserving its original license and provenance."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile

from indoor_navigation_dataset import build_manifest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRECTORY = Path("Fingerprint/App/Domain/IMDF/C5/IMDFData")
ROUTING_FILE = Path("Fingerprint/Debug/RoutingGraphTest/Resources/routing-graph.geojson")
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


def horizontal_distance_meters(start, end):
    """RoutingGeometry와 같은 WGS84 수평 직선거리 하한이다."""
    lon1, lat1 = start[:2]
    lon2, lat2 = end[:2]
    latitude_delta = math.radians(lat2 - lat1)
    lat1, lat2 = math.radians(lat1), math.radians(lat2)
    value = (math.sin(latitude_delta / 2) ** 2
             + math.cos(lat1) * math.cos(lat2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2)
    return 6_371_008.8 * 2 * math.atan2(math.sqrt(value), math.sqrt(max(0, 1 - value)))


def estimated_cross_floor_distances(graph):
    """사용자가 허용한 C5 시연용 가정이다. 실측 거리나 이동 시간으로 취급하지 않는다."""
    nodes = {f["id"]: f for f in graph["features"] if f["properties"]["role"] == "node"}
    entries = []
    for edge in sorted(graph["features"], key=lambda f: f["id"]):
        p = edge["properties"]
        if p["role"] != "edge":
            continue
        floors = abs(nodes[p["from"]]["properties"]["level"] - nodes[p["to"]]["properties"]["level"])
        if not floors:
            continue
        if p["category"] in {"elevator", "platform_lift"}:
            per_floor = 3.5
        elif p["category"] in {"stairs", "escalator", "ramp"}:
            per_floor = 10.0
        else:
            raise ValueError("층간 이동 수단을 확인하세요.")
        meters = floors * per_floor
        horizontal = horizontal_distance_meters(nodes[p["from"]]["geometry"]["coordinates"],
                                                nodes[p["to"]]["geometry"]["coordinates"])
        if not math.isfinite(meters) or not math.isfinite(horizontal) or meters < horizontal:
            raise ValueError(f"층간 연결 {edge['id']}의 추정 거리({meters:g}m)가 수평 직선거리({horizontal:g}m)보다 짧습니다. 거리 가정을 검토해주세요.")
        entries.append({"edge_id": edge["id"], "meters": meters, "source": "estimated",
                        "basis": f"C5 시연용 임시 가정: {p['category']} {per_floor:g}m/층 × {floors}층. 실측 후 교체."})
    return {"schema_version": 1, "dataset_id": "c5-demo", "layout_version": graph["layout_version"], "edges": entries}


def contains(point, geometry):
    def ring_contains(ring):
        x, y = point[:2]
        inside = False
        for a, b in zip(ring, ring[1:]):
            cross = (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0])
            if abs(cross) < 1e-14 and min(a[0], b[0]) <= x <= max(a[0], b[0]) and min(a[1], b[1]) <= y <= max(a[1], b[1]):
                return True
            if (a[1] > y) != (b[1] > y) and x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
                inside = not inside
        return inside

    polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    return any(ring_contains(polygon[0]) and not any(ring_contains(r) for r in polygon[1:]) for polygon in polygons)


def mock_shelves(original, graph):
    """실제 서가를 추측하지 않는다. 도착점이 포함된 기존 unit을 시연용 구역으로만 참조한다."""
    units = json.loads((original / "unit.geojson").read_text())["features"]
    floors = {f["id"]: f for f in json.loads((original / "level.geojson").read_text())["features"]}
    candidates = []
    for node in graph["features"]:
        p = node["properties"]
        if p["role"] != "node" or p.get("category") != "destination":
            continue
        floor = floors.get(p.get("level_id"))
        if not floor or floor["properties"]["ordinal"] != p["level"] or not contains(node["geometry"]["coordinates"], floor["geometry"]):
            continue
        matches = [u for u in units if u["properties"].get("level_id") == p["level_id"]
                   and contains(node["geometry"]["coordinates"], u["geometry"])]
        if len(matches) == 1:
            candidates.append((node, matches[0]))
    candidates.sort(key=lambda pair: (pair[0]["properties"]["level"], pair[0]["id"]))
    selected = []
    # 먼저 서로 다른 층을 선택하고, 세 번째 구역은 이미 선택한 unit과 겹치지 않게 선택한다.
    for pair in candidates:
        if pair[0]["properties"]["level"] not in {n["properties"]["level"] for n, _ in selected}:
            selected.append(pair)
            if len(selected) == 3:
                break
    for pair in candidates:
        if len(selected) == 3:
            break
        if pair[1]["id"] not in {u["id"] for _, u in selected}:
            selected.append(pair)
    if len(selected) != 3 or len({n["properties"]["level"] for n, _ in selected}) < 2:
        raise ValueError("서로 다른 층을 포함한 C5 목업 구역 3개를 정할 수 없습니다. 매핑을 검토하세요.")
    return {"schema_version": 1, "dataset_id": "c5-demo", "layout_version": graph["layout_version"], "mode": "mock",
            "shelves": [{"key": f"mock-{i:02}", "name": f"가상 서가 {i:02}",
                         "level_id": node["properties"]["level_id"], "element_kind": "unit",
                         "element_id": unit["id"], "arrival_node_id": node["id"]}
                        for i, (node, unit) in enumerate(selected, 1)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=PROJECT_ROOT.parent / "2026-C6-M06-Fingerprint")
    parser.add_argument("--replace", action="store_true", help="명시적으로 기존 로컬 복사본을 교체합니다.")
    args = parser.parse_args()
    source = args.source.expanduser().resolve()
    original = source / SOURCE_DIRECTORY
    routing = source / ROUTING_FILE
    destination = PROJECT_ROOT / "fingerprint-library/Resources/IndoorMaps/C5"

    if not original.is_dir():
        parser.error(f"C5 IMDF 폴더가 없습니다: {original}")
    if not routing.is_file() or routing.is_symlink():
        parser.error(f"일반 파일인 C5 routing GeoJSON이 필요합니다: {routing}")
    if any(path.is_symlink() for path in original.rglob("*")):
        parser.error("C5 원본에 심볼릭 링크가 있습니다. 일반 파일로 준비해주세요.")
    actual_files = {str(path.relative_to(original)) for path in original.rglob("*") if path.is_file()}
    if actual_files != EXPECTED_FILES:
        parser.error(f"예상 파일 묶음과 다릅니다. 누락={EXPECTED_FILES - actual_files}, 추가={actual_files - EXPECTED_FILES}")

    # 원본은 읽기만 한다. 커밋되지 않은 C5 변경도 해시와 함께 기록한다.
    hashes = {name: digest(original / name) for name in sorted(EXPECTED_FILES)}
    routing_hash = digest(routing)
    graph = json.loads(routing.read_bytes())
    if graph.get("schema_version") != 1 or not str(graph.get("layout_version", "")).strip():
        parser.error("routing GeoJSON에 schema_version 1과 layout_version이 필요합니다.")
    try:
        shelves = mock_shelves(original, graph)
        distances = estimated_cross_floor_distances(graph)
    except ValueError as error:
        parser.error(str(error))
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
    if not args.replace:
        if existing.exists():
            existing_files = {str(path.relative_to(existing)) for path in existing.rglob("*") if path.is_file()}
            if existing_files != EXPECTED_FILES or any(digest(existing / name) != value for name, value in hashes.items()):
                parser.error("로컬 복사본이 원본과 다릅니다. 내용을 확인한 뒤 --replace로 교체해주세요.")
        old_routing = destination / "routing-graph.geojson"
        if old_routing.exists() and digest(old_routing) != routing_hash:
            parser.error("로컬 routing 복사본이 원본과 다릅니다. 검토 후 --replace로 교체해주세요.")
        old_shelves = destination / "shelves.json"
        if old_shelves.exists() and json.loads(old_shelves.read_text()) != shelves:
            parser.error("로컬 목업 매핑이 생성 규칙과 다릅니다. 검토 후 --replace로 교체해주세요.")
        old_distances = destination / "cross-floor-distances.json"
        if old_distances.exists() and json.loads(old_distances.read_text()) != distances:
            parser.error("로컬 층간 거리 자료가 생성 규칙과 다릅니다. 검토 후 --replace로 교체해주세요.")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="c5-import-", dir=destination.parent) as temporary:
        staged = Path(temporary) / "C5"
        shutil.copytree(original, staged / "IMDFData")
        shutil.copy2(routing, staged / "routing-graph.geojson")
        (staged / "shelves.json").write_text(json.dumps(shelves, ensure_ascii=False, indent=2) + "\n")
        (staged / "cross-floor-distances.json").write_text(json.dumps(distances, ensure_ascii=False, indent=2) + "\n")
        if any(digest(staged / "IMDFData" / name) != value or digest(original / name) != value
               for name, value in hashes.items()) or digest(staged / "routing-graph.geojson") != routing_hash or digest(routing) != routing_hash:
            raise RuntimeError("복사 중 원본이 바뀌었습니다. 가져오기를 다시 실행해주세요.")
        (staged / "source.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        dataset = build_manifest(staged)
        dataset.update({
            "source_commit": record["source_commit"], "source_routing_path": str(ROUTING_FILE),
            "source_worktree_changes": git_output(source, "diff", "HEAD", "--name-only", "--", str(SOURCE_DIRECTORY), str(ROUTING_FILE)).splitlines(),
        })
        (staged / "dataset.json").write_text(json.dumps(dataset, ensure_ascii=False, indent=2) + "\n")
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
    print("routing 원본, 목업 목적지 3개와 데이터셋 해시를 함께 기록했습니다.")
    print("개발용 C5 데이터는 Git 추적 대상입니다. 갱신 diff와 원본 라이선스를 함께 검토하세요.")
    print("정식 배포 전 별도 도서관 데이터로 교체해야 합니다.")


if __name__ == "__main__":
    main()
