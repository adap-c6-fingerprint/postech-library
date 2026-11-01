import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest


spec = importlib.util.spec_from_file_location(
    "release_configuration", Path(__file__).resolve().parents[1] / "validate-release-configuration.py"
)
configuration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configuration)


class ReleaseConfigurationTests(unittest.TestCase):
    def test_debug_tests_need_no_live_tokens(self):
        configuration.validate("Debug", "automatic")

    def test_release_rejects_missing_or_unexpanded_setting(self):
        for name in ["development", "testflight", "production"]:
            for value in ["", "  ", f"$(POBOOK_RELAY_TOKEN_{name.upper()})", "short", "x" * 32 + "\n"]:
                tokens = dict(development="d" * 32, testflight="t" * 32, production="p" * 32)
                tokens[name] = value
                with self.subTest(name=name, value=value), self.assertRaisesRegex(ValueError, name.upper()):
                    configuration.validate("Release", "automatic", **tokens)

    def test_automatic_release_needs_all_environment_tokens(self):
        tokens = dict(development="d" * 32, testflight="t" * 32, production="p" * 32)
        configuration.validate("Release", "automatic", **tokens)
        for name in tokens:
            incomplete = {key: value for key, value in tokens.items() if key != name}
            with self.subTest(missing=name), self.assertRaisesRegex(ValueError, name.upper()):
                configuration.validate("Release", "automatic", **incomplete)

    def test_internal_release_uses_only_dev(self):
        configuration.validate("Release", "internal", development="d" * 32)
        with self.assertRaises(ValueError):
            configuration.validate("Release", "internal", production="p" * 32)

    def test_automatic_release_rejects_duplicate_tokens(self):
        for values in [("d", "d", "p"), ("d", "t", "d"), ("d", "t", "t"), ("d", "d", "d")]:
            tokens = dict(zip(["development", "testflight", "production"], [value * 32 for value in values]))
            with self.subTest(values=values), self.assertRaisesRegex(ValueError, "distinct") as result:
                configuration.validate("Release", "automatic", **tokens)
            for token in tokens.values():
                self.assertNotIn(token, str(result.exception))

    def test_archive_requires_automatic_release(self):
        tokens = dict(development="d" * 32, testflight="t" * 32, production="p" * 32)
        for action in ["install", "archive"]:
            configuration.validate("Release", "automatic", action=action, **tokens)
            for build, channel in [("Release", "internal"), ("Debug", "internal"), ("Debug", "automatic")]:
                with self.subTest(action=action, build=build, channel=channel), self.assertRaisesRegex(ValueError, "Archive/install"):
                    configuration.validate(build, channel, action=action, **tokens)
        configuration.validate("Release", "internal", development="d" * 32, action="build")

    def test_build_phase_reads_archive_action_from_environment(self):
        settings = dict(CONFIGURATION="Release", POBOOK_BUILD_CHANNEL="internal",
                        POBOOK_RELAY_TOKEN_DEVELOPMENT="d" * 32, ACTION="install")
        command = [sys.executable, str(spec.origin)]
        archive = subprocess.run(command, env=settings, capture_output=True, text=True)
        self.assertEqual(archive.returncode, 1)
        self.assertIn("Archive/install", archive.stderr)
        self.assertNotIn(settings["POBOOK_RELAY_TOKEN_DEVELOPMENT"], archive.stderr)
        settings["ACTION"] = "build"
        local = subprocess.run(command, env=settings, capture_output=True, text=True)
        self.assertEqual(local.returncode, 0, local.stderr)

    def test_invalid_channel_and_errors_do_not_print_tokens(self):
        with self.assertRaises(ValueError):
            configuration.validate("Debug", "production")
        token = "s" * 32 + "\r\n"
        with self.assertRaises(ValueError) as result:
            configuration.validate("Release", "internal", development=token)
        self.assertNotIn(token, str(result.exception))


if __name__ == "__main__":
    unittest.main()
