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

    def test_invalid_channel_and_errors_do_not_print_tokens(self):
        with self.assertRaises(ValueError):
            configuration.validate("Debug", "production")
        token = "s" * 32 + "\r\n"
        with self.assertRaises(ValueError) as result:
            configuration.validate("Release", "internal", development=token)
        self.assertNotIn(token, str(result.exception))


if __name__ == "__main__":
    unittest.main()
