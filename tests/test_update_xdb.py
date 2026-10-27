"""Offline checks for release provenance, formula edits and non-destructive updates."""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("update_xdb", Path(__file__).resolve().parents[1] / "tools/update_xdb.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
COMMIT = "1" * 40
FORMULA = '''class Xdb < Formula
  url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "''' + "a" * 64 + '''"
  bottle do
    root_url "https://example.invalid/bottles"
    sha256 arm64_sequoia: "old-bottle"
  end

  resource "mdns" do
    url "https://example.invalid/mdns.tar.gz"
    sha256 "''' + "c" * 64 + '''"
  end
end
'''


class FormulaTest(unittest.TestCase):
    def test_update_changes_only_release_fields_and_removes_stale_bottles(self):
        updated = module.update_formula(FORMULA, "1.2.0", "b" * 64)
        self.assertIn('/v1.2.0.tar.gz"', updated)
        self.assertIn('  sha256 "' + "b" * 64 + '"', updated)
        self.assertNotIn("bottle do", updated)
        self.assertEqual(updated.split('  resource "mdns"')[1], FORMULA.split('  resource "mdns"')[1])

    def test_same_version_preserves_bottles_but_hash_change_and_downgrade_fail(self):
        self.assertEqual(module.update_formula(FORMULA, "1.1.0", "a" * 64), FORMULA)
        with self.assertRaisesRegex(ValueError, "source hash changed"):
            module.update_formula(FORMULA, "1.1.0", "b" * 64)
        with self.assertRaisesRegex(ValueError, "downgrade"):
            module.update_formula(FORMULA, "1.0.0", "b" * 64)

    def test_invalid_versions_and_unexpected_formula_layout_are_rejected(self):
        self.assertEqual(module.version_number("v1.2.0"), "1.2.0")
        for value in ("1.2", "1.2.0-rc1", "01.2.0", "1.2.0;echo nope"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.version_number(value)
        with self.assertRaisesRegex(ValueError, "layout"):
            module.update_formula(FORMULA.replace('  url "', '    url "', 1), "1.2.0", "b" * 64)


class SourceTest(unittest.TestCase):
    def archive(self, directory, version="1.2.0", commit=COMMIT, cmake_version="1.2.0"):
        path = Path(directory) / "source.tar.gz"
        with tarfile.open(path, "w:gz", format=tarfile.PAX_FORMAT, pax_headers={"comment": commit}) as output:
            source = f"project(XDeviceBridge VERSION {cmake_version} LANGUAGES CXX)".encode()
            item = tarfile.TarInfo(f"XDeviceBridge-{version}/CMakeLists.txt")
            item.size = len(source); output.addfile(item, io.BytesIO(source))
        return path

    def test_source_digest_requires_matching_commit_and_cmake_version(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.archive(directory)
            self.assertEqual(module.verify_archive(path, "1.2.0", COMMIT), hashlib.sha256(path.read_bytes()).hexdigest())
            with self.assertRaisesRegex(ValueError, "commit marker"):
                module.verify_archive(path, "1.2.0", "2" * 40)
            path = self.archive(directory, cmake_version="1.1.0")
            with self.assertRaisesRegex(ValueError, "CMake project version"):
                module.verify_archive(path, "1.2.0", COMMIT)

    def test_unpublished_prerelease_and_empty_release_fail_before_download(self):
        stable = {"tag_name": "v1.2.0", "draft": False, "prerelease": False,
                  "published_at": "2026-10-27T00:00:00Z", "assets": [{"name": "runtime"}]}
        for change in ({"draft": True}, {"prerelease": True}, {"published_at": None}, {"assets": []}):
            with self.subTest(change=change), patch.object(module, "gh_json", return_value=stable | change), \
                 patch.object(module, "command") as command:
                with self.assertRaisesRegex(ValueError, "published, stable"):
                    module.release_source("1.2.0")
                command.assert_not_called()


class WorkflowTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Formula").mkdir(); (self.root / module.FORMULA).write_text(FORMULA)
        self.calls = []
        self.dirty = ""; self.local_branch = ""
        for patcher in (patch.object(module, "ROOT", self.root),
                        patch.object(module.shutil, "which", return_value="/tool"),
                        patch.object(module, "command", side_effect=self.command),
                        patch.object(module, "release_source", return_value=(COMMIT, "b" * 64))):
            patcher.start(); self.addCleanup(patcher.stop)

    def command(self, *args):
        self.calls.append(args)
        if args[:3] == ("git", "remote", "get-url"): return "https://github.com/scrctl/homebrew-tap.git\n"
        if args[:2] == ("git", "status"): return self.dirty
        if args[:2] == ("git", "rev-parse"): return COMMIT + "\n"
        if args[:2] == ("git", "show"): return FORMULA
        if args[:2] == ("git", "for-each-ref"): return self.local_branch
        if args[:3] == ("gh", "pr", "create"):
            body = Path(args[args.index("--body-file") + 1]).read_text()
            self.assertIn(COMMIT, body); self.assertIn("b" * 64, body)
            return "https://github.com/scrctl/homebrew-tap/pull/99\n"
        return ""

    def test_dirty_worktree_stops_before_fetch_or_file_edits(self):
        self.dirty = " M README.md\n"
        with self.assertRaisesRegex(ValueError, "worktree must be clean"):
            module.main(["1.2.0"])
        self.assertFalse(any(c[:2] == ("git", "fetch") for c in self.calls))
        self.assertEqual((self.root / module.FORMULA).read_text(), FORMULA)

    def test_dry_run_verifies_and_shows_diff_without_mutations(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(module.main(["1.2.0", "--dry-run"]), 0)
        self.assertIn("v1.2.0", output.getvalue())
        self.assertEqual((self.root / module.FORMULA).read_text(), FORMULA)
        self.assertFalse(any(c[0] == "gh" or c[1] in {"switch", "add", "commit", "push"} for c in self.calls))

    def test_existing_pr_is_reused_without_rewriting_files(self):
        with patch.object(module, "gh_json", return_value=[{"url": "https://github.com/scrctl/homebrew-tap/pull/99"}]), \
             contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(module.main(["1.2.0"]), 0)
        self.assertIn("Existing PR", output.getvalue())
        self.assertEqual((self.root / module.FORMULA).read_text(), FORMULA)
        self.assertFalse(any(c[:2] == ("git", "switch") for c in self.calls))

    def test_colliding_branch_is_not_force_updated(self):
        self.local_branch = "refs/heads/codex/xdb-1.2.0\n"
        with patch.object(module, "gh_json", return_value=[]), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, "already exists"):
                module.main(["1.2.0"])
        self.assertEqual((self.root / module.FORMULA).read_text(), FORMULA)

    def test_new_release_is_committed_and_pushed_before_creating_pr(self):
        with patch.object(module, "gh_json", return_value=[]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(module.main(["1.2.0"]), 0)
        self.assertIn("v1.2.0", (self.root / module.FORMULA).read_text())
        self.assertNotIn("bottle do", (self.root / module.FORMULA).read_text())
        pushed = next(i for i, c in enumerate(self.calls) if c[:2] == ("git", "push"))
        created = next(i for i, c in enumerate(self.calls) if c[:3] == ("gh", "pr", "create"))
        self.assertLess(pushed, created)
        self.assertTrue(any(c[:3] == ("git", "switch", "-c") and c[-1] == COMMIT for c in self.calls))


if __name__ == "__main__":
    unittest.main()
