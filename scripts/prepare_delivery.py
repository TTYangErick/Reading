#!/usr/bin/env python3
"""Build or verify a local Android delivery bundle. Never installs an app."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SAMPLES = (
    "shelf-cover.epub", "shelf-missing.epub", "shelf-broken.epub",
    "footnotes-epub2.epub", "footnotes-epub3.epub",
)
DICTIONARIES = ("manifest.json", "wiktionary-manifest.json")
PRODUCTION = (
    "app/lib", "app/android", "app/ios", "app/assets",
    "app/pubspec.yaml", "app/pubspec.lock", "app/test/fixtures/epub",
    "scripts/flutterw", ":(exclude)app/android/gradle/gradle-daemon-jvm.properties",
)


def run(args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs).strip()


def git_file(revision, path):
    return run(["git", "show", f"{revision}:{path}"])


def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(chunk)
    return result.hexdigest()


def file_record(path):
    with path.open("rb") as stream:
        return {"file": path.name, "bytes": path.stat().st_size, "sha256": digest(stream)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def tools():
    properties = dict(
        line.split("=", 1) for line in (ROOT / "app/android/local.properties").read_text().splitlines()
        if "=" in line and not line.startswith("#")
    )
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or properties["sdk.dir"])
    candidates = sorted(
        (p for p in (sdk / "build-tools").iterdir() if re.fullmatch(r"\d+\.\d+\.\d+", p.name)),
        key=lambda p: tuple(map(int, p.name.split("."))), reverse=True,
    )
    build_tools = next(p for p in candidates if (p / "aapt").is_file() and (p / "apksigner").is_file())
    env = os.environ.copy()
    # Android Studio already supplies the JDK used for Flutter builds on this Mac.
    studio_java = Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home")
    if not env.get("JAVA_HOME") and (studio_java / "bin/java").is_file():
        env["JAVA_HOME"] = str(studio_java)
    return build_tools, env


def inspect_apk(path, revision):
    build_tools, env = tools()
    badging = run([str(build_tools / "aapt"), "dump", "badging", str(path)])
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    require(package is not None, f"Cannot read APK identity: {path}")
    identity = dict(zip(("package", "versionCode", "versionName"), package.groups()))
    abi = re.search(r"^native-code: (.+)$", badging, re.M)
    require(abi is not None and abi[1] == "'arm64-v8a'", "Expected only ARM64 native code")
    certs = run([str(build_tools / "apksigner"), "verify", "--print-certs", str(path)], env=env)
    certificates = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-f]+)", certs)
    require(len(certificates) == 1, "Expected one verified APK signer")
    dictionaries = []
    prefix = "assets/flutter_assets/assets/dictionaries/"
    with zipfile.ZipFile(path) as archive:
        for name in DICTIONARIES:
            expected = json.loads(git_file(revision, f"app/assets/dictionaries/{name}"))
            require(json.loads(archive.read(prefix + name)) == expected, f"Packed manifest differs: {name}")
            compressed = "compressedFile" in expected
            resource = expected["compressedFile" if compressed else "file"]
            size = expected["compressedBytes" if compressed else "bytes"]
            sha = expected["compressedSha256" if compressed else "sha256"]
            require(archive.getinfo(prefix + resource).file_size == size, f"Dictionary size differs: {resource}")
            with archive.open(prefix + resource) as stream:
                require(digest(stream) == sha, f"Dictionary checksum differs: {resource}")
            dictionaries.append({"id": expected["id"], "file": resource, "bytes": size, "sha256": sha})
    return {
        **file_record(path), **identity, "abi": "arm64-v8a", "signatureVerified": True,
        "certificateSha256": certificates[0],
        "permissions": sorted(re.findall(r"^uses-permission: name='([^']+)'", badging, re.M)),
        "dictionaries": dictionaries,
    }


def check_identity(packages, revision):
    version = re.search(r"^version:\s*(\S+)\+(\d+)\s*$", git_file(revision, "app/pubspec.yaml"), re.M)
    require(version is not None, "Expected explicit app version and build number")
    release, profile = packages["release"], packages["profile"]
    for key in ("package", "versionCode", "versionName", "abi", "certificateSha256", "permissions", "dictionaries"):
        require(release[key] == profile[key], f"Release/Profile differ: {key}")
    require(release["package"] == "dev.reading.reading_app", "Unexpected application ID")
    require((release["versionName"], release["versionCode"]) == version.groups(), "Version differs from pinned source")


def verify(directory):
    manifest = json.loads((directory / "manifest.json").read_text())
    require(manifest["schemaVersion"] == 1, "Unsupported delivery manifest schema")
    revision = manifest["appSourceRevision"]
    require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None, "Invalid source revision")
    require(set(manifest["packages"]) == {"release", "profile"}, "Expected Release and Profile")
    require(len(manifest["samples"]) == len(SAMPLES) and
            {item["file"] for item in manifest["samples"]} == set(SAMPLES), "Unexpected sample set")
    for record in [*manifest["packages"].values(), *manifest["samples"]]:
        require(Path(record["file"]).name == record["file"], "Expected bundle-local filename")
        actual = file_record(directory / record["file"])
        require(all(record[key] == actual[key] for key in actual), f"File checksum/size differs: {record['file']}")
    for record in manifest["samples"]:
        original = subprocess.check_output([
            "git", "show", f"{revision}:app/test/fixtures/epub/{record['file']}",
        ], cwd=ROOT)
        require(hashlib.sha256(original).hexdigest() == record["sha256"], f"Sample differs from pinned source: {record['file']}")
    packages = {mode: inspect_apk(directory / item["file"], revision) for mode, item in manifest["packages"].items()}
    require(packages == manifest["packages"], "APK metadata differs from recorded manifest")
    check_identity(packages, revision)
    print(f"Verified: {directory}", flush=True)


def source_revision():
    require(not run(["git", "status", "--porcelain", "--", *PRODUCTION]), "Commit application source/fixtures before packaging")
    return run(["git", "rev-parse", "HEAD"])


def prepare():
    revision = source_revision()
    version = re.search(r"^version:\s*(\S+)\+\d+\s*$", git_file(revision, "app/pubspec.yaml"), re.M)[1]
    parent = ROOT / "artifacts/delivery"
    destination = parent / f"reading-{version}-{revision[:7]}"
    require(not destination.exists(), f"Bundle already exists; verify it instead: {destination}")
    parent.mkdir(parents=True, exist_ok=True)
    # Only this private staging directory is removed on failure; old deliveries survive.
    with tempfile.TemporaryDirectory(prefix=".preparing-", dir=parent) as temporary:
        staging = Path(temporary)
        packages = {}
        for mode in ("release", "profile"):
            print(f"Building {mode} from {revision[:7]} (no install)", flush=True)
            subprocess.run([
                str(ROOT / "scripts/flutterw"), "build", "apk", f"--{mode}",
                "--target-platform", "android-arm64", "--split-per-abi",
                "-P", "force-version-code-ignoring-abi=true",
            ], cwd=ROOT / "app", check=True)
            source = ROOT / f"app/build/app/outputs/flutter-apk/app-arm64-v8a-{mode}.apk"
            target = staging / f"Reading-{version}-arm64-{mode}.apk"
            shutil.copyfile(source, target)
            packages[mode] = inspect_apk(target, revision)
        require(source_revision() == revision, "Source changed during packaging; discard this attempt")
        check_identity(packages, revision)
        samples = []
        for name in SAMPLES:
            target = staging / name
            shutil.copyfile(ROOT / "app/test/fixtures/epub" / name, target)
            samples.append(file_record(target))
        require(source_revision() == revision, "Source changed while copying fixtures")
        manifest = {
            "schemaVersion": 1, "preparedAt": datetime.now(timezone.utc).isoformat(),
            "appSourceRevision": revision, "packages": packages, "samples": samples,
            "scope": "Local test/development signing; no installation. Read fresh device/data baseline before updating.",
        }
        (staging / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        verify(staging)
        require(not destination.exists(), "Destination appeared during packaging; refusing overwrite")
        staging.rename(destination)
    print(f"Prepared: {destination}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", type=Path, metavar="BUNDLE", help="Verify an existing bundle without rebuilding/installing")
    arguments = parser.parse_args()
    try:
        if arguments.verify:
            verify(arguments.verify.resolve())
        else:
            prepare()
    except (ValueError, OSError, KeyError, StopIteration, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Delivery failed: {error}\n")
