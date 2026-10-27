"""데이터셋 생성 계약 검사. 사용자 원본·번들 자료에는 쓰지 않는다."""

from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from indoor_navigation_dataset import build_manifest, map_hashes


SCRIPT = Path(__file__).resolve().parents[1] / "indoor_navigation_dataset.py"
REQUIRED = {"manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
            "unit.geojson", "fixture.geojson", "opening.geojson"}


def write_json(path, value):
    path.write_text(json.dumps(value) + "\n")


class NavigationDatasetTests(unittest.TestCase):
    @contextmanager
    def fixture(self, amenity=True, section=False):
        with tempfile.TemporaryDirectory(prefix="NavigationDataset-") as temporary:
            root = Path(temporary)
            imdf = root / "IMDFData"
            imdf.mkdir()
            names = REQUIRED | ({"amenity.geojson"} if amenity else set()) | ({"section.geojson"} if section else set())
            for name in names:
                write_json(imdf / name, {"test_file": name})
            write_json(root / "routing-graph.geojson", {"schema_version": 1, "layout_version": "fixture-v1"})
            write_json(root / "shelves.json", {"schema_version": 1, "dataset_id": "fixture", "layout_version": "fixture-v1"})
            yield root

    def run_cli(self, root, *arguments):
        return subprocess.run([sys.executable, str(SCRIPT), "--directory", str(root), *arguments],
                              capture_output=True, text=True, timeout=15)

    def test_all_optional_file_combinations_are_pinned(self):
        for amenity in (False, True):
            for section in (False, True):
                with self.subTest(amenity=amenity, section=section), self.fixture(amenity, section) as root:
                    result = self.run_cli(root)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    manifest = json.loads((root / "dataset.json").read_text())
                    expected = REQUIRED | ({"amenity.geojson"} if amenity else set()) | ({"section.geojson"} if section else set())
                    self.assertEqual(set(manifest["map_files_sha256"]), expected)
                    for name, value in manifest["map_files_sha256"].items():
                        self.assertEqual(value, hashlib.sha256((root / "IMDFData" / name).read_bytes()).hexdigest())
                    self.assertEqual(manifest["schema_version"], 1)

    def test_actual_library_map_hashes_exclude_amenity_and_include_section(self):
        imdf = SCRIPT.parents[1] / "fingerprint-library/Resources/IndoorMaps/POSTECHLibrary/IMDFData"
        self.assertEqual(set(map_hashes(imdf)), REQUIRED | {"section.geojson"})

    def test_missing_required_file_preserves_existing_manifest(self):
        for name in REQUIRED:
            with self.subTest(file=name), self.fixture() as root:
                write_json(root / "dataset.json", {"note": "preserve me"})
                before = (root / "dataset.json").read_bytes()
                (root / "IMDFData" / name).unlink()
                self.assertNotEqual(self.run_cli(root, "--replace").returncode, 0)
                self.assertEqual((root / "dataset.json").read_bytes(), before)

    def test_repeated_generation_is_idempotent(self):
        with self.fixture(False, True) as root:
            self.assertEqual(self.run_cli(root).returncode, 0)
            before = (root / "dataset.json").read_bytes()
            self.assertEqual(self.run_cli(root).returncode, 0)
            self.assertEqual((root / "dataset.json").read_bytes(), before)

    def test_optional_file_addition_and_removal_require_explicit_replace(self):
        for initially_present in (False, True):
            with self.subTest(section=initially_present), self.fixture(True, initially_present) as root:
                manifest = build_manifest(root)
                manifest["source_commit"] = "keep-provenance"
                write_json(root / "dataset.json", manifest)
                section = root / "IMDFData/section.geojson"
                if initially_present:
                    section.unlink()
                else:
                    write_json(section, {"type": "FeatureCollection", "features": []})
                before = (root / "dataset.json").read_bytes()
                self.assertNotEqual(self.run_cli(root).returncode, 0)
                self.assertEqual((root / "dataset.json").read_bytes(), before)
                self.assertEqual(self.run_cli(root, "--replace").returncode, 0)
                updated = json.loads((root / "dataset.json").read_text())
                self.assertEqual("section.geojson" in updated["map_files_sha256"], not initially_present)
                self.assertEqual(updated["source_commit"], "keep-provenance")

    def test_mismatched_identifiers_are_rejected(self):
        for file, change in (("routing-graph.geojson", {"layout_version": "other"}),
                             ("shelves.json", {"dataset_id": " "}),
                             ("shelves.json", {"schema_version": 2})):
            with self.subTest(file=file, change=change), self.fixture() as root:
                value = json.loads((root / file).read_text())
                write_json(root / file, {**value, **change})
                with self.assertRaises(ValueError):
                    build_manifest(root)

    def test_optional_distance_hash_tracks_presence(self):
        with self.fixture() as root:
            file = root / "cross-floor-distances.json"
            write_json(file, {"schema_version": 1, "dataset_id": "fixture", "layout_version": "fixture-v1"})
            self.assertEqual(self.run_cli(root).returncode, 0)
            self.assertEqual(json.loads((root / "dataset.json").read_text())["cross_floor_distances_sha256"],
                             hashlib.sha256(file.read_bytes()).hexdigest())
            file.unlink()
            self.assertEqual(self.run_cli(root, "--replace").returncode, 0)
            self.assertNotIn("cross_floor_distances_sha256", json.loads((root / "dataset.json").read_text()))


if __name__ == "__main__":
    unittest.main()
