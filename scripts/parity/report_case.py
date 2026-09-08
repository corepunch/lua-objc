#!/usr/bin/env python3
"""Compare one SwiftUI readiness record with one native candidate capture.

The report deliberately keeps geometry and pixels separate: semantic frame
deltas are authoritative for matching nodes, while image metadata and the
HTML artifact make visual review reproducible. Pixel diffing is optional when
Pillow is available; the report says so explicitly instead of silently
substituting a weak image heuristic.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


TOLERANCE = 0.75


def png_metadata(path: Path | None) -> dict | None:
	if path is None:
		return None
	if not path.is_file() or path.stat().st_size == 0:
		return {"path": str(path), "available": False}
	data = path.read_bytes()
	meta = {
		"path": str(path),
		"available": True,
		"bytes": len(data),
		"sha256": hashlib.sha256(data).hexdigest(),
	}
	if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
		width, height = struct.unpack(">II", data[16:24])
		meta["width"] = width
		meta["height"] = height
	return meta


def frame(node: ET.Element) -> dict:
	return {key: float(node.attrib[key]) for key in ("x", "y", "width", "height")}


def candidate_nodes(path: Path) -> dict[str, dict]:
	root = ET.parse(path).getroot()
	nodes = {}
	for node in root.iter("View"):
		identifier = node.attrib.get("identifier")
		if identifier:
			nodes[identifier] = {
				"id": identifier,
				"class": node.attrib.get("class", ""),
				"frame": frame(node),
				"text": node.attrib.get("text"),
				"clipped": node.attrib.get("contentClipped") == "true",
				"outsideParent": node.attrib.get("outsideParent") == "true",
			}
	return nodes


def compare(candidate: Path, reference: Path, candidate_png: Path | None,
			reference_png: Path | None, out: Path, reproduction: str) -> dict:
	ref = json.loads(reference.read_text())
	probes = {probe["id"]: probe for probe in ref.get("probes", [])}
	candidates = candidate_nodes(candidate)
	comparisons = []
	failures = []
	for identifier, expected in probes.items():
		actual = candidates.get(identifier)
		if actual is None:
			failures.append({"id": identifier, "reason": "missing-candidate-node"})
			comparisons.append({"id": identifier, "status": "missing"})
			continue
		expected_frame = {key: float(expected[key]) for key in
			("x", "y", "width", "height")}
		delta = {key: actual["frame"][key] - expected_frame[key]
			for key in expected_frame}
		within = all(abs(value) <= TOLERANCE for value in delta.values())
		if not within:
			failures.append({"id": identifier, "reason": "frame-delta",
				"delta": delta})
		if actual["clipped"] or actual["outsideParent"]:
			failures.append({"id": identifier, "reason": "candidate-clipped-or-outside",
				"clipped": actual["clipped"],
				"outsideParent": actual["outsideParent"]})
		comparisons.append({"id": identifier,
			"status": "pass" if within and not actual["clipped"] and not actual["outsideParent"] else "fail",
			"expected": expected_frame, "actual": actual, "delta": delta})

	image = {
		"candidate": png_metadata(candidate_png),
		"reference": png_metadata(reference_png),
		"pixelDiff": {"status": "unavailable", "reason": "Pillow is not required"},
	}
	try:
		from PIL import Image, ImageChops  # type: ignore
		if candidate_png and reference_png and candidate_png.is_file() and reference_png.is_file():
			candidate_image = Image.open(candidate_png).convert("RGBA")
			reference_image = Image.open(reference_png).convert("RGBA")
			if candidate_image.size == reference_image.size:
				diff = ImageChops.difference(candidate_image, reference_image)
				bbox = diff.getbbox()
				image["pixelDiff"] = {"status": "different" if bbox else "identical",
					"bbox": list(bbox) if bbox else None}
			else:
				image["pixelDiff"] = {"status": "different-size",
					"candidate": candidate_image.size, "reference": reference_image.size}
	except ImportError:
		pass

	status = "pass" if not failures and probes else "fail"
	report = {
		"schema": 1,
		"case": ref.get("fixture"),
		"status": status,
		"tolerance": TOLERANCE,
		"reference": str(reference),
		"candidate": str(candidate),
		"referenceGeneration": ref.get("generation"),
		"referenceActionCount": ref.get("actionCount", 0),
		"comparisons": comparisons,
		"failures": failures,
		"image": image,
		"reproduction": reproduction,
	}
	out.parent.mkdir(parents=True, exist_ok=True)
	out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
	write_html(out.with_suffix(".html"), report)
	return report


def write_html(path: Path, report: dict) -> None:
	image = report["image"]
	candidate = image.get("candidate") or {}
	reference = image.get("reference") or {}
	def image_tag(meta: dict, title: str) -> str:
		if not meta.get("available"):
			return f"<figure><figcaption>{html.escape(title)} unavailable</figcaption></figure>"
		src = html.escape(Path(meta["path"]).as_uri())
		return f'<figure><figcaption>{html.escape(title)}</figcaption><img src="{src}" alt="{html.escape(title)}"></figure>'
	rows = []
	for item in report["comparisons"]:
		rows.append("<tr>" + "".join(f"<td>{html.escape(str(item.get(key, '')))}</td>"
			for key in ("id", "status", "delta")) + "</tr>")
	path.write_text("""<!doctype html>
<meta charset="utf-8"><title>Parity report</title>
<style>body{font:14px system-ui;margin:2rem} .images{display:flex;gap:2rem} figure{margin:0} img{max-width:480px;border:1px solid #aaa} table{border-collapse:collapse}td,th{border:1px solid #aaa;padding:.35rem}</style>
<h1>Parity report: %s</h1><p>Status: <strong>%s</strong></p>
<p>Reproduction: <code>%s</code></p><div class="images">%s%s</div>
<table><thead><tr><th>ID</th><th>Status</th><th>Frame delta</th></tr></thead><tbody>%s</tbody></table>
""" % (html.escape(str(report.get("case"))), html.escape(report["status"]),
		html.escape(report["reproduction"]), image_tag(reference, "Reference"),
		image_tag(candidate, "Candidate"), "".join(rows)))


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--candidate-xml", required=True, type=Path)
	parser.add_argument("--reference-json", required=True, type=Path)
	parser.add_argument("--candidate-png", type=Path)
	parser.add_argument("--reference-png", type=Path)
	parser.add_argument("--out", required=True, type=Path)
	parser.add_argument("--reproduction", default="CASE=<id> make parity-case")
	parser.add_argument("--strict", action="store_true")
	args = parser.parse_args()
	for path in (args.candidate_xml, args.reference_json):
		if not path.is_file() or path.stat().st_size == 0:
			parser.error(f"missing or empty input: {path}")
	report = compare(args.candidate_xml, args.reference_json, args.candidate_png,
		args.reference_png, args.out, args.reproduction)
	print(json.dumps({"status": report["status"], "out": str(args.out),
		"html": str(args.out.with_suffix('.html')), "failures": len(report["failures"])},
		indent=2))
	return 1 if args.strict and report["status"] != "pass" else 0


if __name__ == "__main__":
	sys.exit(main())
