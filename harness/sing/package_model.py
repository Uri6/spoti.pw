#!/usr/bin/env python3
"""Package a local, two-second AOT export for injection with cyan; never downloads a model."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path, help="export_model.py graph compiled by coreai-build for iOS")
parser.add_argument("output", type=Path, help="new Sing.bundle directory, outside tracked source")
parser.add_argument("--architecture", required=True, help="Core AI architecture used by coreai-build, e.g. h18p")
args = parser.parse_args()
source, output = args.model.resolve(), args.output.resolve()
if source.suffix != ".aimodelc" or not source.is_dir() or output.exists() or output.name != "Sing.bundle":
    parser.error("need an existing .aimodelc and a new Sing.bundle output")
if not args.architecture.isalnum() or not (source / f"main-{args.architecture}.mlirb").is_file():
    parser.error("architecture does not match the compiled graph")
metadata = json.loads((source / "metadata.json").read_text())
if metadata.get("license") != "MIT":
    parser.error("the pinned model must retain its MIT metadata")
here = Path(__file__).resolve().parent
profile = json.loads((here / "model.json").read_text())["liveProfile"]
if metadata.get("sourceHash", "").upper() != profile["sourceHash"].upper():
    parser.error("AOT graph is not the pinned two-second export; benchmark and pin it before packaging")
output.mkdir(parents=True)
try:
    destination = output / "separator.aimodelc"
    # clonefile avoids a second 470 MB allocation on APFS, with independent destination ownership.
    if sys.platform == "darwin":
        subprocess.run(["cp", "-cR", str(source), str(destination)], check=True)
    else:
        shutil.copytree(source, destination)
    hashes = {}
    for path in sorted(destination.rglob("*")):
        if path.is_symlink():
            raise ValueError("model payloads must be regular files")
        if path.is_file():
            with path.open("rb") as stream:
                hashes[path.relative_to(destination).as_posix()] = hashlib.file_digest(stream, "sha256").hexdigest()
    (output / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    (output / "Sing.plist").write_bytes(plistlib.dumps({"Architecture": args.architecture, "WindowFrames": 88200,
        "SampleRate": 44100, "Channels": 2, "SourceHash": metadata.get("sourceHash", "")}))
    (output / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "pw.spoti.sing-model",
        "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"}))
    for name in ("NOTICE", "model.json"):
        shutil.copyfile(here / name, output / name)
except BaseException:
    shutil.rmtree(output)
    raise
print(output)
