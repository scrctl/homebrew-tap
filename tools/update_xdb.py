#!/usr/bin/env python3
"""Prepare an xdb formula PR from a verified stable upstream release."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TAP = "scrctl/homebrew-tap"
UPSTREAM = "scrctl/XDeviceBridge"
FORMULA = "Formula/xdb.rb"
MAX_SOURCE_BYTES = 32 * 1024 * 1024
URL_PATTERN = r'^  url "https://github\.com/scrctl/XDeviceBridge/archive/refs/tags/v([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz"$'
HASH_PATTERN = r'^  sha256 "([0-9a-f]{64})"$'


def command(*args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or f"{args[0]} failed")
    return result.stdout


def gh_json(*args):
    return json.loads(command("gh", *args))


def version_number(value):
    value = value.removeprefix("v")
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise ValueError("Use a stable version such as 1.2.0 or v1.2.0")
    return value


def formula_version(contents):
    matches = re.findall(URL_PATTERN, contents, re.M)
    if len(matches) != 1 or len(re.findall(HASH_PATTERN, contents, re.M)) != 1:
        raise ValueError("Unexpected xdb formula layout; review it manually")
    return matches[0]


def update_formula(contents, version, checksum):
    current = formula_version(contents)
    if not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise ValueError("Invalid source SHA256")
    if tuple(map(int, version.split("."))) < tuple(map(int, current.split("."))):
        raise ValueError(f"Refusing to downgrade xdb {current} to {version}")
    if version == current:
        if re.search(HASH_PATTERN, contents, re.M).group(1) != checksum:
            raise ValueError("The published version's source hash changed; review it manually")
        return contents  # Retain published bottles when already up to date.
    contents = re.sub(URL_PATTERN, f'  url "https://github.com/{UPSTREAM}/archive/refs/tags/v{version}.tar.gz"',
                      contents, count=1, flags=re.M)
    contents = re.sub(HASH_PATTERN, f'  sha256 "{checksum}"', contents, count=1, flags=re.M)
    return re.sub(r"^  bottle do\n.*?^  end\n\n?", "", contents, count=1, flags=re.M | re.S)


def verify_archive(path, version, commit):
    if path.stat().st_size > MAX_SOURCE_BYTES:
        raise ValueError("Source archive is larger than the updater's 32 MiB limit")
    with tarfile.open(path, "r|gz") as archive:
        if archive.pax_headers.get("comment") != commit:
            raise ValueError("Source archive commit marker does not match the release tag")
        for entry in archive:
            if entry.name != f"XDeviceBridge-{version}/CMakeLists.txt":
                continue
            if not entry.isfile() or entry.size > 65536:
                raise ValueError("Unexpected CMakeLists.txt in source archive")
            source = archive.extractfile(entry).read().decode("utf-8")
            match = re.search(r"\bproject\s*\(\s*XDeviceBridge\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)\b",
                              source, re.I)
            if not match or match.group(1) != version:
                raise ValueError("CMake project version does not match the release tag")
            return hashlib.sha256(path.read_bytes()).hexdigest()
    raise ValueError("Source archive does not contain the expected CMakeLists.txt")


def release_source(version):
    tag = f"v{version}"
    release = gh_json("api", f"repos/{UPSTREAM}/releases/tags/{tag}")
    if (release.get("tag_name") != tag or release.get("draft") or release.get("prerelease")
            or not release.get("published_at") or not release.get("assets")):
        raise ValueError("The upstream release must be published, stable and have attachments")
    commit = gh_json("api", f"repos/{UPSTREAM}/commits/{tag}").get("sha", "")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Cannot resolve the release tag to a commit")
    with tempfile.TemporaryDirectory(prefix="xdb-formula-") as temporary:
        archive = Path(temporary) / "source.tar.gz"
        command("curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2",
                "--proto", "=https", "--proto-redir", "=https", "--max-time", "120",
                "--max-filesize", str(MAX_SOURCE_BYTES), "--output", str(archive),
                f"https://github.com/{UPSTREAM}/archive/refs/tags/{tag}.tar.gz")
        checksum = verify_archive(archive, version, commit)
    return commit, checksum


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="published stable xdb version, e.g. 1.2.0")
    parser.add_argument("--dry-run", action="store_true", help="verify sources and preview; do not edit files or create a PR")
    args = parser.parse_args(argv)
    version = version_number(args.version)
    for tool in ("git", "gh", "curl"):
        if not shutil.which(tool):
            raise RuntimeError(f"Required tool is missing: {tool}")
    origin = command("git", "remote", "get-url", "origin").strip()
    if not re.fullmatch(r"(?:https://github\.com/|git@github\.com:)scrctl/homebrew-tap(?:\.git)?/?", origin):
        raise ValueError(f"Run this tool in a clone whose origin is {TAP}")
    if not args.dry_run and command("git", "status", "--porcelain").strip():
        raise ValueError("The worktree must be clean; commit your work or use --dry-run")
    command("git", "fetch", "origin", "main")
    base = command("git", "rev-parse", "FETCH_HEAD").strip()
    original = command("git", "show", f"{base}:{FORMULA}")
    current = formula_version(original)
    if tuple(map(int, version.split("."))) < tuple(map(int, current.split("."))):
        raise ValueError(f"Refusing to downgrade xdb {current} to {version}")
    commit, checksum = release_source(version)
    updated = update_formula(original, version, checksum)
    print(f"Verified xdb {version}: commit {commit}, SHA256 {checksum}")
    if updated == original:
        print("The formula is already up to date; published bottles are unchanged.")
        return 0
    if args.dry_run:
        print("".join(difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                                         fromfile=FORMULA, tofile=FORMULA)), end="")
        return 0
    branch = f"codex/xdb-{version}"
    existing = gh_json("pr", "list", "--repo", TAP, "--head", branch, "--state", "open", "--json", "url")
    if existing:
        print(f"Existing PR: {existing[0]['url']}")
        return 0
    local = command("git", "for-each-ref", "--format=%(refname)", f"refs/heads/{branch}")
    remote = command("git", "ls-remote", "--heads", "origin", f"refs/heads/{branch}")
    if local.strip() or remote.strip():
        raise ValueError(f"Branch {branch} already exists without an open PR; inspect it manually")
    command("git", "switch", "-c", branch, base)
    (ROOT / FORMULA).write_text(updated, encoding="utf-8")
    command("git", "diff", "--check")
    command("git", "add", "--", FORMULA)
    command("git", "commit", "-m", f"xdb {version}")
    command("git", "push", "--set-upstream", "origin", branch)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".md") as body:
        body.write(f"Update xdb to [{version}](https://github.com/{UPSTREAM}/releases/tag/v{version}).\n\n"
                   f"Verified tag commit: `{commit}`. The source archive commit marker and CMake version match.\n\n"
                   f"Source SHA256: `{checksum}`. Remove old bottle metadata; the existing PR CI builds new bottles.\n\n"
                   "After checks pass, use the existing brew pr-pull workflow with this PR number and exact head SHA.\n")
        body.flush()
        print(command("gh", "pr", "create", "--repo", TAP, "--base", "main", "--head", branch,
                      "--title", f"xdb {version}", "--body-file", body.name).strip())
    print("PR head SHA for review/pr-pull: " + command("git", "rev-parse", "HEAD").strip())
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError, tarfile.TarError, subprocess.TimeoutExpired) as error:
        sys.exit(f"xdb formula update failed: {error}")
