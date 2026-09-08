#!/usr/bin/env python3
"""Validate the parity fixture manifest without third-party dependencies."""

from __future__ import annotations

import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tests/parity/manifest.json"
SCHEMA = ROOT / "tests/parity/schema.json"
STATUSES = {
    "unassessed",
    "missing",
    "implemented-unverified",
    "failing",
    "passing",
    "blocked",
    "not-applicable",
}
CASE_ID = re.compile(r"^[a-z0-9][a-z0-9.-]*$")
FAMILY = re.compile(r"^[A-E][0-9]$")


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    try:
        manifest = json.loads(MANIFEST.read_text())
        schema = json.loads(SCHEMA.read_text())
        if schema.get("type") != "object":
            fail("schema root must be an object")
        if manifest.get("version") != 1:
            fail("manifest version must be 1")
        if set(manifest.get("statusValues", [])) != STATUSES:
            fail("manifest statusValues do not match the contract")

        cases = manifest.get("cases")
        if not isinstance(cases, list) or not cases:
            fail("manifest cases must be a non-empty array")

        ids: set[str] = set()
        for index, case in enumerate(cases):
            if not isinstance(case, dict):
                fail(f"case {index} must be an object")
            for field in (
                "id",
                "family",
                "gate",
                "platforms",
                "swiftuiScene",
                "etluaScene",
                "mapping",
                "status",
                "evidence",
            ):
                if field not in case:
                    fail(f"case {index} is missing {field}")
            case_id = case["id"]
            if not isinstance(case_id, str) or not CASE_ID.fullmatch(case_id):
                fail(f"case {index} has an invalid id")
            if case_id in ids:
                fail(f"duplicate case id: {case_id}")
            ids.add(case_id)
            if not isinstance(case["family"], str) or not FAMILY.fullmatch(case["family"]):
                fail(f"case {case_id} has an invalid family")
            if case["gate"] not in {"core", "common"}:
                fail(f"case {case_id} has an invalid gate")
            if not isinstance(case["platforms"], list) or not case["platforms"]:
                fail(f"case {case_id} must name at least one platform")
            if case["status"] not in STATUSES:
                fail(f"case {case_id} has an invalid status")
            if not isinstance(case["evidence"], list):
                fail(f"case {case_id} evidence must be an array")

        print(f"parity manifest valid: {len(cases)} cases")
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"parity manifest invalid: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
