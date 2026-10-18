"""Synthetic CLI regression tests; never reads or modifies the user's C5 data."""

from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest


IMPORT_SCRIPT = Path(__file__).resolve().parents[1] / "import-c5-local.py"
IMDF_PATH = Path("Fingerprint/App/Domain/IMDF/C5/IMDFData")
ROUTING_PATH = Path("Fingerprint/Debug/RoutingGraphTest/Resources/routing-graph.geojson")
IMDF_FILES = (
    "manifest.json", "address.geojson", "venue.geojson", "building.geojson",
    "footprint.geojson", "level.geojson", "unit.geojson", "fixture.geojson",
    "opening.geojson", "amenity.geojson", "anchor.geojson", "occupant.geojson",
    "LICENSE/LICENSE.txt",
)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True) + "\n")


def snapshot(directory):
    return {str(p.relative_to(directory)): p.read_bytes() for p in directory.rglob("*") if p.is_file()}


def polygon(left, right):
    return {"type": "Polygon", "coordinates": [[[left, 0], [right, 0], [right, 0.01], [left, 0.01], [left, 0]]]}


class C5ImportTests(unittest.TestCase):
    @contextmanager
    def fixture(self):
        with tempfile.TemporaryDirectory(prefix="C5ImportRegression-") as temporary:
            root = Path(temporary)
            source = root / "source"
            imdf = source / IMDF_PATH
            for name in IMDF_FILES:
                path = imdf / name
                path.parent.mkdir(parents=True, exist_ok=True)
                if name.endswith(".txt"):
                    path.write_text("Synthetic test fixture license.\n")
                else:
                    write_json(path, {"type": "FeatureCollection", "features": []})
            floor_ids = ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"]
            levels = [{"id": floor_id, "properties": {"ordinal": i}, "geometry": polygon(0, 0.01)}
                      for i, floor_id in enumerate(floor_ids)]
            units = []
            nodes = []
            for i, (floor, x) in enumerate(((0, 0.002), (0, 0.007), (1, 0.002))):
                units.append({"id": f"00000000-0000-4000-8000-{i + 10:012}",
                              "properties": {"level_id": floor_ids[floor]},
                              "geometry": polygon(0 if x < 0.005 else 0.005, 0.005 if x < 0.005 else 0.01)})
                nodes.append({"type": "Feature", "id": f"node-{i}",
                              "properties": {"role": "node", "category": "destination", "level": floor,
                                             "level_id": floor_ids[floor]},
                              "geometry": {"type": "Point", "coordinates": [x, 0.002]}})
            write_json(imdf / "level.geojson", {"type": "FeatureCollection", "features": levels})
            write_json(imdf / "unit.geojson", {"type": "FeatureCollection", "features": units})
            write_json(source / ROUTING_PATH, {"type": "FeatureCollection", "schema_version": 1,
                                              "layout_version": "synthetic-v1", "features": nodes})
            git = ["git", "-c", f"core.hooksPath={root / 'no-hooks'}", "-c", "commit.gpgSign=false"]
            subprocess.run([*git, "init", "-q", str(source)], check=True, capture_output=True)
            subprocess.run([*git, "-C", str(source), "add", "."], check=True, capture_output=True)
            subprocess.run([*git, "-C", str(source), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                            "commit", "-qm", "Synthetic fixture"], check=True, capture_output=True)
            project = root / "project"
            script = project / "Scripts/import-c5-local.py"
            script.parent.mkdir(parents=True)
            shutil.copy2(IMPORT_SCRIPT, script)
            destination = project / "fingerprint-library/Resources/IndoorMaps/C5"

            def run(*args):
                return subprocess.run([sys.executable, str(script), "--source", str(source), *args],
                                      text=True, capture_output=True, timeout=15)

            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            yield SimpleNamespace(source=source, destination=destination, run=run)

    def edit_sidecar(self, fixture, filename):
        path = fixture.destination / filename
        value = json.loads(path.read_text())
        if filename == "routing-graph.geojson":
            value["features"][0]["properties"]["name"] = "local edit"
        elif filename == "shelves.json":
            value["shelves"][0]["name"] = "local edit"
        else:
            value["layout_version"] = "local edit"
        write_json(path, value)

    def assert_source_preserved(self, fixture):
        source = snapshot(fixture.source / IMDF_PATH)
        self.assertEqual(snapshot(fixture.destination / "IMDFData"), source)
        self.assertEqual((fixture.destination / "routing-graph.geojson").read_bytes(),
                         (fixture.source / ROUTING_PATH).read_bytes())
        record = json.loads((fixture.destination / "source.json").read_text())
        self.assertEqual(record["files_sha256"], {name: hashlib.sha256(data).hexdigest() for name, data in source.items()})

    def test_initial_import_preserves_source(self):
        with self.fixture() as fixture:
            self.assertEqual(len(snapshot(fixture.destination)), 18)
            self.assert_source_preserved(fixture)

    def test_modified_sidecars_require_replace_with_or_without_imdf(self):
        for has_imdf in (False, True):
            for filename in ("routing-graph.geojson", "shelves.json", "cross-floor-distances.json"):
                with self.subTest(imdf=has_imdf, file=filename), self.fixture() as fixture:
                    if not has_imdf:
                        shutil.rmtree(fixture.destination / "IMDFData")
                    self.edit_sidecar(fixture, filename)
                    before = snapshot(fixture.destination)
                    result = fixture.run()
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertIn("--replace", result.stderr)
                    self.assertEqual(snapshot(fixture.destination), before)

    def test_explicit_replace_updates_modified_sidecars(self):
        for has_imdf in (False, True):
            for filename in ("routing-graph.geojson", "shelves.json", "cross-floor-distances.json"):
                with self.subTest(imdf=has_imdf, file=filename), self.fixture() as fixture:
                    if not has_imdf:
                        shutil.rmtree(fixture.destination / "IMDFData")
                    self.edit_sidecar(fixture, filename)
                    edited = (fixture.destination / filename).read_bytes()
                    result = fixture.run("--replace")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotEqual((fixture.destination / filename).read_bytes(), edited)
                    self.assert_source_preserved(fixture)

    def test_matching_partial_destination_can_be_completed(self):
        with self.fixture() as fixture:
            shutil.rmtree(fixture.destination / "IMDFData")
            before = snapshot(fixture.destination)
            result = fixture.run()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_source_preserved(fixture)
            for path, value in before.items():
                self.assertEqual((fixture.destination / path).read_bytes(), value)

    def test_repeated_import_is_idempotent(self):
        with self.fixture() as fixture:
            before = snapshot(fixture.destination)
            result = fixture.run()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(snapshot(fixture.destination), before)

    def test_modified_imdf_requires_replace(self):
        with self.fixture() as fixture:
            path = fixture.destination / "IMDFData/unit.geojson"
            path.write_bytes(path.read_bytes() + b" ")
            before = snapshot(fixture.destination)
            result = fixture.run()
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(snapshot(fixture.destination), before)

    def test_estimated_cross_floor_distances_are_pinned(self):
        with self.fixture() as fixture:
            path = fixture.source / ROUTING_PATH
            graph = json.loads(path.read_text())
            for category in ("stairs", "elevator"):
                graph["features"].append({"id": category, "properties": {
                    "role": "edge", "from": "node-0", "to": "node-2", "category": category}})
            write_json(path, graph)
            result = fixture.run("--replace")
            self.assertEqual(result.returncode, 0, result.stderr)
            file = fixture.destination / "cross-floor-distances.json"
            distances = json.loads(file.read_text())
            self.assertEqual({e["edge_id"]: e["meters"] for e in distances["edges"]}, {"stairs": 10, "elevator": 3.5})
            self.assertTrue(all(e["source"] == "estimated" and e["basis"] for e in distances["edges"]))
            manifest = json.loads((fixture.destination / "dataset.json").read_text())
            self.assertEqual(manifest["cross_floor_distances_sha256"], hashlib.sha256(file.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
