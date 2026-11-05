"""Static wiring checks; these do not replace an Xcode build or console verification."""

import json
from pathlib import Path
import plistlib
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]


class FirebaseSetupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with (ROOT / "fingerprint-library/Info.plist").open("rb") as stream:
            cls.info = plistlib.load(stream)
        converted = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(ROOT / "fingerprint-library.xcodeproj/project.pbxproj")],
            check=True, capture_output=True, text=True,
        )
        cls.objects = json.loads(converted.stdout)["objects"]
        cls.app = cls.objects["000000000000000100000000"]

    def test_collection_and_automatic_screen_reporting_default_off(self):
        for key in (
            "FIREBASE_ANALYTICS_COLLECTION_ENABLED", "FirebaseCrashlyticsCollectionEnabled",
            "FirebaseAutomaticScreenReportingEnabled", "FirebaseAppDelegateProxyEnabled",
            "GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED",
            "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS",
        ):
            with self.subTest(key=key):
                self.assertIs(self.info.get(key), False)

    def test_main_app_links_only_the_requested_firebase_products(self):
        products = [self.objects[ref] for ref in self.app["packageProductDependencies"]]
        firebase = [product for product in products if product["productName"].startswith("Firebase")]
        self.assertEqual({p["productName"] for p in firebase}, {
            "FirebaseCore", "FirebaseAnalyticsCore", "FirebaseCrashlytics",
        })
        for product in firebase:
            package = self.objects[product["package"]]
            self.assertEqual(package["repositoryURL"], "https://github.com/firebase/firebase-ios-sdk.git")
            self.assertEqual(package["requirement"], {"kind": "exactVersion", "version": "13.1.1"})
        frameworks = next(self.objects[p] for p in self.app["buildPhases"]
                          if self.objects[p]["isa"] == "PBXFrameworksBuildPhase")
        linked = {self.objects[ref]["productRef"] for ref in frameworks["files"]}
        self.assertTrue(set(self.app["packageProductDependencies"]).issubset(linked))

    def test_both_build_configurations_preserve_objc_linker_flag(self):
        configurations = self.objects[self.app["buildConfigurationList"]]["buildConfigurations"]
        for ref in configurations:
            settings = self.objects[ref]["buildSettings"]
            self.assertEqual(settings["OTHER_LDFLAGS"], "$(inherited) -ObjC")
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "com.youngmin.fingerprint-library")

    def test_bootstrap_preserves_existing_root_store(self):
        app = (ROOT / "fingerprint-library/App/MyApp.swift").read_text()
        self.assertIn("@UIApplicationDelegateAdaptor(FirebaseAppDelegate.self)", app)
        self.assertIn("AppView(store: store)", app)
        self.assertIn("Store(initialState: AppFeature.State()) { AppFeature() }", app)
        self.assertIn("options.bundleID == Bundle.main.bundleIdentifier", app)
        self.assertEqual(app.count("FirebaseApp.configure(options: options)"), 1)
        self.assertNotIn("NavigationView", app)
        self.assertNotIn("setAnalyticsCollectionEnabled(true)", app)

    def test_client_config_is_local_and_has_the_expected_bundle_id_when_present(self):
        relative = "fingerprint-library/GoogleService-Info.plist"
        ignored = subprocess.run(["git", "check-ignore", relative], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(ignored.returncode, 0)
        tracked = subprocess.run(["git", "ls-files", "--error-unmatch", relative], cwd=ROOT, capture_output=True)
        self.assertNotEqual(tracked.returncode, 0)
        config = ROOT / relative
        if config.exists():
            with config.open("rb") as stream:
                self.assertEqual(plistlib.load(stream)["BUNDLE_ID"], "com.youngmin.fingerprint-library")


if __name__ == "__main__":
    unittest.main()
