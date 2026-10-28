import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "release_configuration", Path(__file__).resolve().parents[1] / "validate-release-configuration.py"
)
configuration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configuration)


class ReleaseConfigurationTests(unittest.TestCase):
    def test_debug_can_use_local_primo_key_without_proxy(self):
        configuration.validate("Debug", "")

    def test_release_rejects_missing_or_unexpanded_setting(self):
        for value in ["", "  ", "$(PRIMO_PROXY_URL)"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                configuration.validate("Release", value)

    def test_release_accepts_https_base_and_prefix(self):
        for value in ["https://proxy.example.org", "https://proxy.example.org/library", "https://proxy.example.org:8443/"]:
            with self.subTest(value=value):
                configuration.validate("Release", value)

    def test_release_rejects_urls_the_live_client_cannot_use(self):
        for value in ["http://proxy.example.org", "HTTPS://proxy.example.org", "proxy.example.org", "https://",
                      " https://proxy.example.org", "https://proxy.example.org ", "https://user:secret@proxy.example.org",
                      "https://proxy.example.org?q=1", "https://proxy.example.org?", "https://proxy.example.org/#x",
                      "https://proxy.example.org/#", "https://proxy.example.org:bad",
                      "https://proxy.example.org:70000", "https://proxy.example.org/a b"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                configuration.validate("Release", value)


if __name__ == "__main__":
    unittest.main()
