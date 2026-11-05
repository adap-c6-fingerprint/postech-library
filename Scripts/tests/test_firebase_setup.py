"""Static wiring checks; these do not replace an Xcode build or console verification."""

import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
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

    def test_collection_has_one_consent_boundary_and_no_automatic_crash_upload(self):
        runtime = (ROOT / "fingerprint-library/Clients/Analytics/AnalyticsRuntime.swift").read_text()
        self.assertIn("storedConsent.permitsEvents(configured: configured, active: active)", runtime)
        self.assertIn("storedConsent.permitsDiagnosticReport(previousRunEligible:", runtime)
        self.assertIn("operations.reset()", runtime)
        self.assertIn("profileRevision == revision", runtime)
        self.assertNotIn("setCrashlyticsCollectionEnabled(true)", runtime)
        self.assertEqual(runtime.count("sendUnsentReports()"), 1)
        self.assertEqual(runtime.count("Analytics.logEvent("), 1)
        self.assertIn("Analytics.resetAnalyticsData()", runtime)
        self.assertIn(".adStorage: .denied", runtime)
        self.assertIn(".adUserData: .denied", runtime)
        self.assertIn(".adPersonalization: .denied", runtime)

    def test_consent_is_available_at_first_launch_and_in_settings(self):
        app = (ROOT / "fingerprint-library/App/AppView.swift").read_text()
        settings = (ROOT / "fingerprint-library/Features/Analytics/AnalyticsSettingsView.swift").read_text()
        my_page = (ROOT / "fingerprint-library/Features/MyPage/View/MyPageView.swift").read_text()
        self.assertIn("!AnalyticsRuntime.shared.consent.hasChosen", app)
        self.assertIn("AnalyticsSettingsView(isFirstChoice: true)", app)
        self.assertIn("AnalyticsSettingsView(isFirstChoice: false)", my_page)
        self.assertIn('Button("모두 거부")', settings)
        self.assertIn(".interactiveDismissDisabled(isFirstChoice)", settings)

    def test_profile_catalog_has_unique_stable_short_codes(self):
        catalog = json.loads((ROOT / "fingerprint-library/Resources/RecommendationDataset.json").read_text())
        affiliations = catalog["affiliations"]
        self.assertEqual(len(affiliations), 301)
        self.assertEqual(len({tuple(item["selectionKey"]) for item in affiliations}), len(affiliations))
        self.assertEqual(len({item["id"] for item in affiliations}), len(affiliations))
        self.assertTrue(all(len(item["id"]) <= 36 for item in affiliations))

    def test_crash_symbols_are_last_and_archive_only(self):
        phase = self.objects[self.app["buildPhases"][-1]]
        self.assertEqual(phase["name"], "Crashlytics Symbols (Archive only)")
        self.assertEqual(str(phase["runOnlyForDeploymentPostprocessing"]), "1")
        self.assertEqual(len(phase["inputPaths"]), 6)
        self.assertIn("GoogleService-Info.plist", " ".join(phase["inputPaths"]))
        self.assertIn("SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols", phase["shellScript"])
        self.assertIn("--build-phase", phase["shellScript"])
        self.assertNotIn("&", phase["shellScript"])
        self.assertTrue(any(path.endswith("/Crashlytics/upload-symbols") for path in phase["inputPaths"]))

    def test_pure_consent_and_request_logic(self):
        result = subprocess.run(["bash", "Scripts/verify-analytics.sh"], cwd=ROOT,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unchanged_analytics_consent_does_not_reset_a_visit_or_operations(self):
        runtime = (ROOT / "fingerprint-library/Clients/Analytics/AnalyticsRuntime.swift").read_text()
        save = runtime.split("func saveConsent(", 1)[1].split("func setActive(", 1)[0]
        block = re.search(r"if analyticsChanged \{([^}]+)\}", save).group(1)
        for reset in ("operations.reset()", "lastNavigationState.removeAll()", "visitID = nil",
                      "profileVersion = nil", "intervalStart = nil", "profileRevision += 1"):
            self.assertIn(reset, block)
        self.assertIn("previous.analytics != choice.analytics", save)
        self.assertIn("if active, analyticsChanged { beginVisitIfNeeded() }", save)

    def test_symbol_upload_failures_reach_the_build(self):
        phase = self.objects[self.app["buildPhases"][-1]]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tool = root / "SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
            tool.parent.mkdir(parents=True)
            tool.write_text("#!/bin/sh\necho upload-failed >&2\nexit 37\n")
            tool.chmod(0o700)
            result = subprocess.run(["/bin/sh", "-c", phase["shellScript"]],
                                    env={**os.environ, "BUILD_DIR": str(root / "Build/Products")},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 37)
            self.assertIn("upload-failed", result.stderr)

    def test_verification_respects_selected_xcode_and_cleans_temporary_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tool = root / "xcrun"
            tool.write_text(
                '#!/bin/bash\n'
                'printf "%s" "${DEVELOPER_DIR-selected-xcode}" > "$PROOF_ENV_FILE"\n'
                'for argument in "$@"; do binary="$argument"; done\n'
                'printf "%s\\n" "$binary"\n'
                'if [ "${PROOF_FAIL-0}" = 1 ]; then exit 37; fi\n'
                'printf "#!/bin/sh\\nexit 0\\n" > "$binary"\n'
                'chmod 700 "$binary"\n'
            )
            tool.chmod(0o700)
            for developer_dir, fails in ((None, False), ("/custom/Xcode-beta.app", False), (None, True)):
                with self.subTest(developer_dir=developer_dir, fails=fails):
                    trace = root / "developer-dir"
                    env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                           "PROOF_ENV_FILE": str(trace), "PROOF_FAIL": "1" if fails else "0"}
                    env.pop("DEVELOPER_DIR", None)
                    if developer_dir is not None:
                        env["DEVELOPER_DIR"] = developer_dir
                    result = subprocess.run(["bash", "Scripts/verify-analytics.sh"], cwd=ROOT,
                                            env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 37 if fails else 0, result.stderr)
                    self.assertEqual(trace.read_text(), developer_dir or "selected-xcode")
                    proof_dir = Path(result.stdout.strip()).parent
                    self.assertTrue(proof_dir.name.startswith("pobook-analytics."))
                    self.assertFalse(proof_dir.exists())


if __name__ == "__main__":
    unittest.main()
