#!/usr/bin/env python3
"""Persistent-process geometry batches. Only the reference host supplies expectations."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
KINDS = {"text", "hstack", "vstack", "zstack", "spacer"}
SAFE_ID = re.compile(r"^[a-z0-9][a-zA-Z0-9._-]*$")
ENVIRONMENT_FIELDS = ("platform", "os", "scale", "appearance", "locale", "textSize", "direction", "coordinateSpace")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                    ensure_ascii=False).encode()).hexdigest()


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n")
    temporary.replace(path)


def read(path):
    return json.loads(Path(path).read_text())


def finite(value):
    return type(value) in (float, int) and math.isfinite(value)


def validate(spec):
    if spec.get("schema") != 1 or not isinstance(spec.get("cases"), list) or not spec["cases"]:
        raise ValueError("expected nonempty schema-1 cases")
    if set(spec) - {"schema", "cases", "runId"}:
        raise ValueError("unsupported batch fields")
    case_ids = set()
    for case in spec["cases"]:
        if set(case) != {"id", "width", "height", "tree"}:
            raise ValueError("unsupported or missing case fields")
        if not SAFE_ID.fullmatch(case.get("id", "")) or case["id"] in case_ids:
            raise ValueError("unsafe or duplicate case ID")
        case_ids.add(case["id"])
        for key in ("width", "height"):
            if not finite(case.get(key)) or case[key] <= 0:
                raise ValueError(f"{case['id']}: viewport {key} must be positive")
        ids = set()

        def node(n):
            allowed = {"id", "kind", "padding", "width", "height"}
            if n.get("kind") == "text":
                allowed |= {"text", "size"}
            elif n.get("kind") in {"hstack", "vstack", "zstack"}:
                allowed.add("children")
                if n["kind"] != "zstack":
                    allowed.add("spacing")
            if set(n) - allowed:
                raise ValueError(f"unsupported node fields: {set(n) - allowed}")
            if n.get("kind") not in KINDS or not SAFE_ID.fullmatch(n.get("id", "")) or n["id"] in ids:
                raise ValueError("unsupported kind or unsafe/duplicate node ID")
            ids.add(n["id"])
            for key in ("spacing", "padding", "size", "width", "height"):
                if key in n and (not finite(n[key]) or n[key] < 0):
                    raise ValueError(f"invalid {key}")
            if n["kind"] == "text" and not isinstance(n.get("text"), str):
                raise ValueError("text nodes require text")
            children = n.get("children", [])
            if not isinstance(children, list) or (children and n["kind"] in {"text", "spacer"}):
                raise ValueError("invalid children")
            for child in children:
                node(child)
        node(case["tree"])
        if not expected_nodes(case):
            raise ValueError("case has no measurable nodes")
    return spec


def expected_nodes(case):
    result = {}
    def walk(n):
        if n["kind"] != "spacer":
            result[n["id"]] = n
        for child in n.get("children", []):
            walk(child)
    walk(case["tree"])
    return result


def generate():
    cases = []
    for kind in ("hstack", "vstack", "zstack"):
        for width in (120, 240, 360, 480):
            for spacing in ((None,) if kind == "zstack" else (0, 8, 20)):
                for padding in (0, 12):
                    for variant in ("empty", "single", "mixed", "nested"):
                        children = [] if variant == "empty" else [
                            {"kind": "text", "id": "first", "text": "Parity", "size": 13}]
                        if variant in {"mixed", "nested"}:
                            children.append({"kind": "text", "id": "second",
                                             "text": "Longer label", "size": 20})
                        if variant == "nested":
                            children.append({"kind": "vstack" if kind == "hstack" else "hstack",
                                             "id": "inner", "spacing": 8, "children": [
                                                 {"kind": "text", "id": "innerText", "text": "Nested", "size": 13},
                                                 {"kind": "spacer", "id": "space"}]})
                        tree = {"id": "root", "kind": kind,
                                "padding": padding, "children": children}
                        if spacing is not None:
                            tree["spacing"] = spacing
                        cases.append({"id": f"{kind}.w{width}.s{spacing if spacing is not None else 'default'}.p{padding}.{variant}",
                                      "width": width, "height": 160,
                                      "tree": tree})
    return validate({"schema": 1, "cases": cases})


def validate_capture(case, capture, run_id):
    if not isinstance(run_id, str) or not run_id:
        raise ValueError("missing capture run identity")
    if capture.get("schema") != 1 or capture.get("id") != case["id"] or capture.get("runId") != run_id:
        raise ValueError(f"{case['id']}: stale/wrong capture identity")
    for field in ("width", "height"):
        if capture.get(field) != case[field]:
            raise ValueError(f"{case['id']}: viewport mismatch")
    if capture.get("platform") not in {"macos", "ios"} or not capture.get("os"):
        raise ValueError("missing native environment")
    if not finite(capture.get("scale")) or capture["scale"] <= 0:
        raise ValueError("invalid display scale")
    for key, expected in (("appearance", "light"), ("textSize", "large"),
                          ("direction", "ltr"), ("coordinateSpace", "root-top-left-points")):
        if capture.get(key) != expected:
            raise ValueError(f"unsupported or missing {key}")
    if not isinstance(capture.get("locale"), str) or not capture["locale"]:
        raise ValueError("missing locale")
    probes = capture.get("probes")
    if not isinstance(probes, list):
        raise ValueError("missing probes")
    indexed = {}
    for probe in probes:
        if probe.get("id") in indexed:
            raise ValueError("duplicate probe")
        for key in ("x", "y", "width", "height"):
            if not finite(probe.get(key)) or (key in {"width", "height"} and probe[key] < 0):
                raise ValueError("invalid geometry")
        indexed[probe.get("id")] = probe
    if set(indexed) != set(expected_nodes(case)):
        raise ValueError(f"{case['id']}: missing or unexpected probes")
    for key, node in expected_nodes(case).items():
        if node["kind"] == "text" and indexed[key].get("text") != node["text"]:
            raise ValueError(f"{case['id']}: incorrect text at {key}")
    return indexed


def compare(case, ref, actual, tolerance=0.5):
    if not finite(tolerance) or tolerance < 0 or tolerance >= 1:
        raise ValueError("tolerance must be finite and below one point")
    rp = validate_capture(case, ref, ref.get("runId"))
    cp = validate_capture(case, actual, actual.get("runId"))
    for key in ENVIRONMENT_FIELDS:
        if ref[key] != actual[key]:
            raise ValueError(f"different {key}: {ref[key]} vs {actual[key]}")
    tolerance = min(tolerance, 0.5 / ref["scale"])
    failures = []
    for identifier in rp:
        delta = {key: cp[identifier][key] - rp[identifier][key]
                 for key in ("x", "y", "width", "height")}
        delta["right"] = delta["x"] + delta["width"]
        delta["bottom"] = delta["y"] + delta["height"]
        if any(abs(v) > tolerance for v in delta.values()):
            failures.append({"node": identifier, "kind": expected_nodes(case)[identifier]["kind"],
                             "delta": delta, "reference": rp[identifier], "candidate": cp[identifier]})
    return {"id": case["id"], "status": "geometry-fail" if failures else "geometry-pass",
            "failures": failures, "tolerancePoints": tolerance,
            "visual": "unverified", "interaction": "unverified"}


def source_hash(engine):
    """Ignore build products; include uncommitted source changes in provenance."""
    paths = ([ROOT / "tests/parity/batch/BatchReferenceHost.swift"] if engine == "reference" else
             sorted(p for base in ("src", "lua", "ios/LuaRuntime", "examples/parity_batch", "scripts/parity")
                    for p in (ROOT / base).rglob("*")
                    if p.is_file() and p.suffix in {".m", ".h", ".c", ".lua"}))
    return digest({str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})


def simctl(args, *command, env=None):
    native_env = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
    if env:
        native_env.update(env)
    return subprocess.run(["xcrun", "simctl", *command], env=native_env, check=True,
                          capture_output=True, text=True, timeout=60).stdout.strip()


def capture_ios(args, root, results):
    bundle_id = args.bundle_id or ("org.luaobjc.parity.batch-reference" if args.engine == "reference" else "org.luaobjc.host")
    # Installation is an explicit setup step, never hidden in the batch loop.
    container = Path(simctl(args, "get_app_container", args.device, bundle_id, "data"))
    installed = Path(simctl(args, "get_app_container", args.device, bundle_id, "app"))
    plist = subprocess.check_output(["plutil", "-extract", "CFBundleExecutable", "raw", "-o", "-",
                                     str(installed / "Info.plist")], text=True).strip()
    build_hash = hashlib.sha256((installed / plist).read_bytes()).hexdigest()
    device_root = container / "Documents" / ("parity-" + read(root / "input.json")["runId"])
    device_root.mkdir(parents=True)
    shutil.copy2(root / "input.json", device_root / "input.json")
    output = device_root / "results"
    output.mkdir()
    packager = None
    launch_env = {}
    try:
        if args.engine == "candidate":
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            log = (root / "packager.log").open("w")
            packager = subprocess.Popen([str(ROOT / "build/lua-objc-packager"), "--root", str(ROOT),
                                         "--entry", "examples/parity_batch", "--port", str(port)],
                                        stdout=log, stderr=log)
            log.close()
            import urllib.request
            deadline = time.monotonic() + 10
            while True:
                if packager.poll() is not None:
                    raise ValueError("owned packager exited; inspect packager.log")
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1):
                        break
                except OSError:
                    if time.monotonic() > deadline:
                        raise ValueError("owned packager did not become ready")
                    time.sleep(0.1)
            launch_env = {"SIMCTL_CHILD_PARITY_BATCH_INPUT": str(device_root / "input.json"),
                          "SIMCTL_CHILD_PARITY_BATCH_OUTPUT": str(output),
                          "SIMCTL_CHILD_LUA_OBJC_PACKAGER": f"http://127.0.0.1:{port}"}
        command = ["launch", "--terminate-running-process", args.device, bundle_id]
        if args.engine == "reference":
            command += ["--input", str(device_root / "input.json"), "--output", str(output)]
            if args.screenshots:
                command.append("--png")
        launch = simctl(args, *command, env=launch_env)
        (root / "launch.log").write_text(launch)
        deadline = time.monotonic() + args.timeout
        while not (output / "done.json").exists():
            if (output / "error.json").exists():
                raise ValueError((output / "error.json").read_text())
            if time.monotonic() > deadline:
                raise ValueError("simulator batch deadline exceeded; inspect device output " + str(output))
            time.sleep(0.1)
        done = read(output / "done.json")
        input_data = read(root / "input.json")
        if done.get("runId") != input_data["runId"] or done.get("count") != len(input_data["cases"]):
            raise ValueError("wrong simulator completion identity/count")
        shutil.copytree(output, results, dirs_exist_ok=True)
    finally:
        try:
            simctl(args, "terminate", args.device, bundle_id)
        except subprocess.SubprocessError:
            pass  # A failed launch or self-terminating host has no process to close.
        if packager:
            packager.terminate()
            try:
                packager.wait(timeout=5)
            except subprocess.TimeoutExpired:
                packager.kill()
                packager.wait()
    return build_hash, installed / plist


def capture(args):
    if args.screenshots and args.engine != "reference":
        raise ValueError("candidate batch PNG capture is not implemented; use the native integration screenshot path")
    spec = validate(read(args.spec))
    source_before = source_hash(args.engine)
    root = Path(args.out).resolve()
    if root.exists():
        raise ValueError("output must be a new directory (prevents stale evidence)")
    root.mkdir(parents=True)
    run_id = str(uuid.uuid4())
    save(root / "input.json", dict(spec, runId=run_id))
    results = root / "results"
    results.mkdir()
    env = dict(os.environ)
    started = time.monotonic()
    if args.platform == "ios":
        build_hash, binary = capture_ios(args, root, results)
    elif args.engine == "reference":
        binary = Path(args.binary).resolve()
        command = [str(binary), "--input", str(root / "input.json"), "--output", str(results)]
        if args.screenshots:
            command.append("--png")
        build_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
    else:
        binary = ROOT / "lua-objc"
        command = [str(binary), "--test", "scripts/parity/batch_candidate.lua"]
        env.update(PARITY_BATCH_INPUT=str(root / "input.json"), PARITY_BATCH_OUTPUT=str(results))
        binary = ROOT / "build/AppKit.dylib"
        build_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
    if args.platform != "ios":
        with (root / "stdout.log").open("w") as stdout, (root / "stderr.log").open("w") as stderr:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, timeout=args.timeout)
        if result.returncode:
            raise ValueError(f"host exited {result.returncode}; inspect {root}/stderr.log")
    environments = set()
    hashes = {}
    for case in spec["cases"]:
        path = results / (case["id"] + ".json")
        value = read(path)
        validate_capture(case, value, run_id)
        environments.add(tuple(value[k] for k in ENVIRONMENT_FIELDS))
        hashes[case["id"]] = digest(value)
    if len(environments) != 1:
        raise ValueError("environment changed within batch")
    if source_hash(args.engine) != source_before:
        raise ValueError("source changed during capture; rerun the batch")
    if hashlib.sha256(Path(binary).read_bytes()).hexdigest() != build_hash:
        raise ValueError("binary changed during capture; rerun the batch")
    manifest = {"schema": 1, "engine": args.engine, "runId": run_id, "specHash": digest(spec),
                "buildHash": build_hash, "binary": str(binary), "sourceHash": source_before, "environment": list(environments.pop()),
                "seconds": time.monotonic() - started, "count": len(spec["cases"]), "results": hashes}
    save(root / "complete.json", manifest)
    print(json.dumps({k: v for k, v in manifest.items() if k != "results"}, indent=2))


def load_run(path, spec, engine):
    root = Path(path)
    meta = read(root / "complete.json")
    if meta.get("schema") != 1 or meta.get("engine") != engine or meta.get("specHash") != digest(spec) or not meta.get("runId"):
        raise ValueError("wrong engine or changed specification; recapture")
    if meta.get("sourceHash") != source_hash(engine):
        raise ValueError(f"{engine} source changed after capture; rerun that engine")
    if hashlib.sha256(Path(meta["binary"]).read_bytes()).hexdigest() != meta["buildHash"]:
        raise ValueError(f"{engine} binary changed after capture; rerun that engine")
    data = {}
    if set(meta.get("results", {})) != {c["id"] for c in spec["cases"]}:
        raise ValueError("incomplete batch")
    for case in spec["cases"]:
        value = read(root / "results" / (case["id"] + ".json"))
        validate_capture(case, value, meta["runId"])
        if digest(value) != meta["results"][case["id"]]:
            raise ValueError("capture changed after completion")
        if [value[k] for k in ENVIRONMENT_FIELDS] != meta["environment"]:
            raise ValueError("capture environment differs from batch")
        data[case["id"]] = value
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    gen = commands.add_parser("generate")
    gen.add_argument("--out", required=True)
    cap = commands.add_parser("capture")
    cap.add_argument("--engine", required=True, choices=("reference", "candidate"))
    cap.add_argument("--spec", required=True)
    cap.add_argument("--out", required=True)
    cap.add_argument("--binary", default="build/parity/batch/SwiftUIBatchReference")
    cap.add_argument("--timeout", type=float, default=180)
    cap.add_argument("--screenshots", action="store_true")
    cap.add_argument("--platform", choices=("macos", "ios"), default="macos")
    cap.add_argument("--device", default="booted")
    cap.add_argument("--bundle-id")
    cmp = commands.add_parser("compare")
    for flag in ("spec", "reference", "candidate", "out"):
        cmp.add_argument("--" + flag, required=True)
    cmp.add_argument("--tolerance", type=float, default=0.5)
    args = parser.parse_args()
    try:
        if args.command == "generate":
            spec = generate()
            save(args.out, spec)
            print(f"{len(spec['cases'])} cases written to {args.out}")
        elif args.command == "capture":
            capture(args)
        else:
            spec = validate(read(args.spec))
            reference = load_run(args.reference, spec, "reference")
            candidate = load_run(args.candidate, spec, "candidate")
            reports = [compare(c, reference[c["id"]], candidate[c["id"]], args.tolerance) for c in spec["cases"]]
            failed = sum(r["status"] == "geometry-fail" for r in reports)
            groups = {}
            for report in reports:
                for failure in report["failures"]:
                    fields = ",".join(k for k, v in failure["delta"].items() if abs(v) > report["tolerancePoints"])
                    key = failure["kind"] + ":" + fields
                    group = groups.setdefault(key, {"nodes": 0, "cases": []})
                    group["nodes"] += 1
                    if report["id"] not in group["cases"]:
                        group["cases"].append(report["id"])
            save(args.out, {"schema": 1, "cases": reports, "failed": failed,
                            "passed": len(reports) - failed, "scope": "geometry-only",
                            "failureGroups": groups})
            print(f"{len(reports) - failed} geometry pass, {failed} geometry fail; visuals/interactions unverified")
            return int(failed > 0)
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"batch invalid: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
