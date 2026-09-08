"""Negative controls for evidence acceptance, not implementation string checks."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
loader = importlib.util.spec_from_file_location("batch", ROOT / "scripts/parity/batch.py")
batch = importlib.util.module_from_spec(loader)
loader.loader.exec_module(batch)


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.case = {"id": "sample", "width": 320, "height": 160,
                     "tree": {"id": "label", "kind": "text", "text": "Hello"}}
        self.value = {"schema": 1, "id": "sample", "runId": "run-one", "platform": "macos",
                      "os": "test-os", "scale": 2, "width": 320, "height": 160,
                      "appearance": "light", "locale": "en_US", "textSize": "large", "direction": "ltr",
                      "coordinateSpace": "root-top-left-points",
                      "probes": [{"id": "label", "text": "Hello", "x": 10, "y": 20,
                                  "width": 40, "height": 16}]}

    def test_generated_matrix_is_valid(self):
        self.assertEqual(len(batch.generate()["cases"]), 224)

    def test_candidate_provenance_includes_streamed_fixture_sources(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(batch, "ROOT", Path(tmp)):
            previous = batch.source_hash("candidate")
            for relative in ("examples/parity_batch/Model.lua", "scripts/parity/batch_candidate.lua"):
                source = Path(tmp) / relative
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text("return {}")
                current = batch.source_hash("candidate")
                self.assertNotEqual(current, previous)
                previous = current

    def test_identical_and_one_point_displacement(self):
        self.assertEqual(batch.compare(self.case, self.value, self.value)["status"], "geometry-pass")
        changed = copy.deepcopy(self.value)
        changed["probes"][0]["x"] += 1
        self.assertEqual(batch.compare(self.case, self.value, changed)["status"], "geometry-fail")

    def test_reject_missing_duplicate_wrong_text_nan(self):
        for probes in ([], self.value["probes"] * 2,
                       [dict(self.value["probes"][0], text="Wrong")],
                       [dict(self.value["probes"][0], x=float("nan"))]):
            with self.subTest(probes=probes), self.assertRaises(ValueError):
                batch.validate_capture(self.case, dict(self.value, probes=probes), "run-one")

    def test_reject_stale_generation_and_other_os(self):
        with self.assertRaises(ValueError):
            batch.validate_capture(self.case, self.value, "run-two")
        with self.assertRaises(ValueError):
            batch.compare(self.case, self.value, dict(self.value, os="other-os"))

    def test_edge_displacement_is_not_hidden_by_origin_size_tolerance(self):
        changed = copy.deepcopy(self.value)
        changed["probes"][0].update(x=10.5, width=40.5)
        self.assertEqual(batch.compare(self.case, self.value, changed)["status"], "geometry-fail")

    def test_reject_unknown_properties_and_unsafe_ids(self):
        for tree in (dict(self.case["tree"], magicAlignment="leading"),
                     dict(self.case["tree"], id="../escape")):
            with self.assertRaises(ValueError):
                batch.validate({"schema": 1, "cases": [dict(self.case, tree=tree)]})

    def test_cached_results_are_bound_to_spec_and_content(self):
        spec = {"schema": 1, "cases": [self.case]}
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = root / "test-binary"
            binary.write_bytes(b"test")
            batch.save(root / "results/sample.json", self.value)
            batch.save(root / "complete.json", {
                "schema": 1, "engine": "reference", "runId": "run-one", "specHash": batch.digest(spec),
                "sourceHash": batch.source_hash("reference"),
                "binary": str(binary), "buildHash": batch.hashlib.sha256(b"test").hexdigest(),
                "environment": [self.value[k] for k in batch.ENVIRONMENT_FIELDS], "results": {"sample": batch.digest(self.value)}})
            self.assertEqual(batch.load_run(root, spec, "reference")["sample"], self.value)
            batch.save(root / "results/sample.json", dict(self.value, runId="old-run"))
            with self.assertRaises(ValueError):
                batch.load_run(root, spec, "reference")


if __name__ == "__main__":
    unittest.main()
