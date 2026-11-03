import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


PACKAGER = Path(__file__).resolve().parents[1] / "scripts" / "package-source.py"


class PackageSourceTests(unittest.TestCase):
    def test_source_package_excludes_internal_plan_notes(self):
        with tempfile.TemporaryDirectory(prefix="appaudit-source-package-") as temporary:
            root = Path(temporary) / "AppAudit"
            (root / "scripts").mkdir(parents=True)
            (root / "docs").mkdir()
            (root / "dist").mkdir()
            packager = root / "scripts" / "package-source.py"
            shutil.copyfile(PACKAGER, packager)
            (root / "dist" / "App-Audit-1.5.1-macOS-arm64.zip").write_bytes(b"fixture")
            (root / "docs" / "INSTALL.md").write_text("Public setup instructions")
            (root / "docs" / "1.3-plan.md").write_text("Internal planning notes")

            result = subprocess.run(
                [sys.executable, str(packager)], capture_output=True, text=True
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            with zipfile.ZipFile(root / "dist" / "App-Audit-1.5.1-source.zip") as archive:
                self.assertIn("AppAudit/docs/INSTALL.md", archive.namelist())
                self.assertNotIn("AppAudit/docs/1.3-plan.md", archive.namelist())

    def test_gitignore_keeps_internal_plan_notes_local(self):
        project = PACKAGER.parents[1]
        with tempfile.TemporaryDirectory(prefix="appaudit-ignore-") as temporary:
            root = Path(temporary)
            shutil.copyfile(project / ".gitignore", root / ".gitignore")
            (root / "docs").mkdir()
            (root / "docs" / "1.3-plan.md").write_text("Internal planning notes")
            (root / "docs" / "INSTALL.md").write_text("Public setup instructions")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)

            plan = subprocess.run(
                ["git", "check-ignore", "--no-index", "docs/1.3-plan.md"],
                cwd=root,
                capture_output=True,
                text=True,
            )
            public_doc = subprocess.run(
                ["git", "check-ignore", "--no-index", "docs/INSTALL.md"],
                cwd=root,
                capture_output=True,
                text=True,
            )

            self.assertEqual(plan.returncode, 0, "internal plan note is not ignored")
            self.assertEqual(public_doc.returncode, 1, "public setup docs are ignored")

    def test_source_package_refuses_file_symlinks_outside_project(self):
        with tempfile.TemporaryDirectory(prefix="appaudit-source-package-") as temporary:
            root = Path(temporary) / "AppAudit"
            (root / "scripts").mkdir(parents=True)
            (root / "Sources").mkdir()
            (root / "dist").mkdir()
            packager = root / "scripts" / "package-source.py"
            shutil.copyfile(PACKAGER, packager)
            (root / "dist" / "App-Audit-1.5.1-macOS-arm64.zip").write_bytes(b"fixture")

            outside = Path(temporary) / "outside.txt"
            outside.write_text("PUBLICATION_BOUNDARY_SENTINEL")
            (root / "Sources" / "external.txt").symlink_to(outside)

            result = subprocess.run(
                [sys.executable, str(packager)], capture_output=True, text=True
            )

            archive = root / "dist" / "App-Audit-1.5.1-source.zip"
            self.assertNotEqual(result.returncode, 0, "packager accepted an external file symlink")
            self.assertIn("symlink", result.stderr.lower())
            self.assertFalse(archive.exists(), "packager left a partial public archive")


if __name__ == "__main__":
    unittest.main()
