"""Run make_app.sh's SDK selection with fixtures, stopping before app replacement.

Only the two absolute host paths (CLT SDKs and PlistBuddy) are redirected in
a temporary script copy. PATH supplies recording xcrun/swift stubs; swift
always fails deliberately, so no compilation, signing, or app copying occurs.
"""

from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "make_app.sh"


class SDKSelectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="murmur-sdk-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.active = self.root / "Xcode SDKs"
        self.clt = self.root / "CommandLineTools SDKs"
        self.active.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.script = self.root / "scripts" / "make_app.sh"
        self.script.parent.mkdir()
        source = SCRIPT.read_text()
        source = source.replace("/Library/Developer/CommandLineTools/SDKs", str(self.clt))
        source = source.replace("/usr/libexec/PlistBuddy", str(self.bin / "PlistBuddy"))
        self.script.write_text(source)
        self.stub("xcrun", '''printf '%s\\n' "$*" >> "$SDK_TEST_ROOT/xcrun.calls"
case "$*" in
    '--sdk macosx --show-sdk-path') printf '%s\\n' "$SDK_TEST_DEFAULT_PATH" ;;
    '--sdk macosx --show-sdk-version') printf '%s\\n' "$SDK_TEST_VERSION" ;;
    *) exit 99 ;;
esac
''')
        self.stub("PlistBuddy", 'cat "$3"\n')
        self.stub("swift", '''printf '%s\\n' "$@" > "$SDK_TEST_ROOT/swift.args"
exit 73
''')
        self.sentinel = self.root / "build" / "Murmur.app" / "preserve.txt"
        self.sentinel.parent.mkdir(parents=True)
        self.sentinel.write_text("existing app")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    def sdk(self, directory, name, version):
        path = directory / name
        path.mkdir(parents=True)
        if version is not None:
            (path / "SDKSettings.plist").write_text(version + "\n")
        return str(path)

    def run_selection(self, expected=None, *, version="27.0", args=(), warning=False):
        env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "LC_ALL": "C",
            "SDK_TEST_ROOT": str(self.root),
            "SDK_TEST_DEFAULT_PATH": str(self.active / "MacOSX.sdk"),
            "SDK_TEST_VERSION": version,
        }
        result = subprocess.run(
            ["/bin/bash", str(self.script), *args], env=env,
            text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(result.returncode, 73, result.stderr)
        auto_args = ["--sdk", expected] if expected else []
        self.assertEqual(
            (self.root / "swift.args").read_text().splitlines(),
            ["build", "-c", "release", *auto_args, *args],
        )
        self.assertEqual("WARNING:" in result.stderr, warning, result.stderr)
        if warning:
            self.assertIn("but no macOS 26 SDK is", result.stderr)
        if expected:
            self.assertIn(f"building against {expected}", result.stderr)
        self.assertEqual(self.sentinel.read_text(), "existing app")
        self.assertEqual(list(self.sentinel.parent.iterdir()), [self.sentinel])
        return result

    def test_xcode_newer_uses_newest_clt_sdk(self):
        self.sdk(self.active, "MacOSX27.0.sdk", "27.0")
        self.sdk(self.clt, "MacOSX26.sdk", "26.0")
        self.sdk(self.clt, "MacOSX26.5.sdk", "26.5")
        newest = self.sdk(self.clt, "MacOSX26.10.sdk", "26.10")
        self.sdk(self.clt, "MacOSX27.sdk", "27.0")
        self.run_selection(newest, args=("--disable-automatic-resolution",))

    def test_active_matching_sdks_keep_priority(self):
        self.sdk(self.active, "MacOSX26.sdk", "26.0")
        newest = self.sdk(self.active, "MacOSX26.5.sdk", "26.5")
        self.sdk(self.clt, "MacOSX26.10.sdk", "26.10")
        self.run_selection(newest)

    def test_clt_active_selects_from_active_directory(self):
        # xcrun can also point directly at the CLT directory.
        self.active = self.clt
        newest = self.sdk(self.active, "MacOSX26.5.sdk", "26.5")
        self.run_selection(newest)

    def test_matching_default_is_untouched(self):
        self.sdk(self.active, "MacOSX26.5.sdk", "26.5")
        self.sdk(self.clt, "MacOSX26.10.sdk", "26.10")
        self.run_selection(version="26.0")

    def test_older_default_is_untouched(self):
        self.sdk(self.clt, "MacOSX26.5.sdk", "26.5")
        self.run_selection(version="25.0")

    def test_explicit_sdk_bypasses_discovery(self):
        self.sdk(self.clt, "MacOSX26.5.sdk", "26.5")
        self.run_selection(args=("--sdk", "/chosen SDK/MacOSX27.sdk"))
        self.assertFalse((self.root / "xcrun.calls").exists())

    def test_no_target_in_either_directory_warns(self):
        self.sdk(self.active, "MacOSX27.sdk", "27.0")
        self.sdk(self.clt, "MacOSX25.sdk", "25.0")
        self.run_selection(warning=True)

    def test_missing_clt_directory_warns(self):
        self.run_selection(warning=True)

    def test_unreadable_active_candidate_allows_fallback(self):
        self.sdk(self.active, "MacOSX26.sdk", None)
        newest = self.sdk(self.clt, "MacOSX26.5.sdk", "26.5")
        self.run_selection(newest)

    def test_unreadable_clt_candidate_warns(self):
        self.sdk(self.clt, "MacOSX26.sdk", None)
        self.run_selection(warning=True)

    def test_failed_xcrun_is_untouched(self):
        self.stub("xcrun", "exit 1\n")
        self.sdk(self.clt, "MacOSX26.5.sdk", "26.5")
        self.run_selection()


if __name__ == "__main__":
    unittest.main()
