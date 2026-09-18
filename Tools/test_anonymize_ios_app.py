import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("anonymize-ios-app.sh")
BUILD_HOME = "/Users/preview-builder"


class AnonymizeIOSAppTests(unittest.TestCase):
    def run_anonymizer(self, app):
        return subprocess.run(
            ["bash", str(SCRIPT), str(app)],
            env={**os.environ, "HOME": BUILD_HOME},
            capture_output=True,
            text=True,
            check=False,
        )

    def test_scrubs_app_and_nested_widget_without_changing_byte_lengths(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Preview.app"
            widget = app / "PlugIns" / "PreviewWidgets.appex"
            widget.mkdir(parents=True)
            binaries = [app / "Preview", widget / "PreviewWidgets"]
            original = b"\0prefix:" + BUILD_HOME.encode() + b"/source.swift\0suffix"
            for binary in binaries:
                binary.write_bytes(original)

            result = self.run_anonymizer(app)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("residual home-path hits: 0", result.stdout)
            for binary in binaries:
                scrubbed = binary.read_bytes()
                self.assertEqual(len(scrubbed), len(original))
                self.assertNotIn(BUILD_HOME.encode(), scrubbed)
                self.assertIn(b"/Users/builder", scrubbed)
                self.assertTrue(scrubbed.endswith(b"/source.swift\0suffix"))

    def test_already_clean_bundle_succeeds(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Preview.app"
            app.mkdir()
            binary = app / "Preview"
            original = b"\0already anonymous\0"
            binary.write_bytes(original)

            result = self.run_anonymizer(app)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("residual home-path hits: 0", result.stdout)
            self.assertEqual(binary.read_bytes(), original)

    @unittest.skipIf(os.geteuid() == 0, "root can read permission-denied fixtures")
    def test_scan_errors_are_not_treated_as_no_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Preview.app"
            app.mkdir()
            binary = app / "Unreadable"
            binary.write_bytes(b"anonymous")
            binary.chmod(0)
            try:
                result = self.run_anonymizer(app)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)
                self.assertNotIn("clean", result.stdout)
            finally:
                binary.chmod(0o600)


if __name__ == "__main__":
    unittest.main()
