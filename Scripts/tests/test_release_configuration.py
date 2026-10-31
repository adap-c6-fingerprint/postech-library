import importlib.util
from pathlib import Path
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
        for value in ["", "  ", "$(POBOOK_RELAY_TOKEN_PRODUCTION)", "short", "x" * 32 + "\n"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                configuration.validate("Release", "automatic", testflight="t" * 32, production=value)

    def test_store_archive_needs_both_environment_tokens(self):
        configuration.validate("Release", "automatic", testflight="t" * 32, production="p" * 32)
        with self.assertRaises(ValueError):
            configuration.validate("Release", "automatic", testflight="t" * 32)
        with self.assertRaises(ValueError):
            configuration.validate("Release", "automatic", production="p" * 32)

    def test_internal_release_uses_only_dev(self):
        configuration.validate("Release", "internal", development="d" * 32)
        with self.assertRaises(ValueError):
            configuration.validate("Release", "internal", production="p" * 32)

    def test_invalid_channel_and_errors_do_not_print_tokens(self):
        with self.assertRaises(ValueError):
            configuration.validate("Debug", "production")
        token = "s" * 32 + "\r\n"
        with self.assertRaises(ValueError) as result:
            configuration.validate("Release", "internal", development=token)
        self.assertNotIn(token, str(result.exception))


if __name__ == "__main__":
    unittest.main()
