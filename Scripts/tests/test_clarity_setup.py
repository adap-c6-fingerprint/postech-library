"""Clarity wiring and production runtime tests with a no-network SDK double."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "fingerprint-library"


class ClaritySetupTests(unittest.TestCase):
    def test_main_app_links_exact_supported_sdk(self):
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(ROOT / "fingerprint-library.xcodeproj/project.pbxproj")],
            check=True, capture_output=True, text=True)
        objects = json.loads(result.stdout)["objects"]
        target = objects["000000000000000100000000"]
        product = objects["C26800000000000000000011"]
        package = objects[product["package"]]
        self.assertIn("C26800000000000000000011", target["packageProductDependencies"])
        self.assertEqual(product["productName"], "Clarity")
        self.assertEqual(package["repositoryURL"], "https://github.com/microsoft/clarity-apps")
        self.assertEqual(package["requirement"], {"kind": "exactVersion", "version": "4.1.2"})
        frameworks = next(objects[ref] for ref in target["buildPhases"]
                          if objects[ref]["isa"] == "PBXFrameworksBuildPhase")
        self.assertIn("C26800000000000000000011", {objects[ref]["productRef"] for ref in frameworks["files"]})

    def test_resolved_direct_dependencies_are_pinned(self):
        relative = "fingerprint-library.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        current = {p["identity"]: p for p in json.loads((ROOT / relative).read_text())["pins"]}
        self.assertEqual(current["clarity-apps"]["state"]["version"], "4.1.2")
        self.assertEqual(current["clarity-apps"]["state"]["revision"], "9cafe2f85279abd65d24c9346d96ecdc30bc8bb3")
        self.assertEqual(current["firebase-ios-sdk"]["state"]["version"], "13.1.1")
        self.assertEqual(current["swift-composable-architecture"]["state"]["version"], "1.26.2")

    def test_normal_ui_is_unmasked_and_only_private_settings_pause_replay(self):
        protected_paths = set()
        for path in APP.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path):
                self.assertNotIn(".clarityMask(", source)
                self.assertNotIn("ClaritySDK.maskView(", source)
            if ".sessionReplayProtected()" in source:
                protected_paths.add(path.relative_to(APP).as_posix())
        self.assertEqual(protected_paths, {
            "App/AppView.swift",  # 개발용 Mac 연결 설정만 중지
            "Features/Analytics/AnalyticsSettingsView.swift",
        })
        map_view = (APP / "Features/IndoorMap/Components/Common/Map/IndoorMapKitView.swift").read_text()
        self.assertIn("ClaritySDK.unmaskView(view)", map_view)
        root = (APP / "App/AppView.swift").read_text()
        self.assertIn("|| !SessionReplayRuntime.shared.consent.hasChosen", root)
        self.assertIn("SessionReplayRuntime.shared.setActive(phase == .active)", root)
        self.assertIn(".clarityUnmask()", root)
        screen = (APP / "Shared/Analytics/AnalyticsScreenModifier.swift").read_text()
        self.assertIn(".clarityUnmask()", screen)
        settings = (APP / "Features/Analytics/AnalyticsSettingsView.swift").read_text()
        self.assertIn("save(AnalyticsConsent(), sessionReplay: false)", settings)
        self.assertIn("SessionReplayRuntime.shared.saveConsent(enabled: sessionReplay)", settings)
        self.assertIn("지도에 표시되는 위치·층·경로도 녹화에 포함될 수 있습니다", settings)
        self.assertNotIn("텍스트·이미지·지도 영역은 가립니다", settings)
        runtime = (APP / "Clients/Analytics/SessionReplayRuntime.swift").read_text()
        self.assertNotIn("setCustomUserId", runtime)
        self.assertNotIn("getCurrentSessionUrl", runtime)

    def test_runtime_with_async_sdk_double(self):
        with tempfile.TemporaryDirectory(prefix="pobook-clarity-", dir="/private/tmp") as temporary:
            temp = Path(temporary)
            module = temp / "libClarity.dylib"
            common = ["xcrun", "swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
                      "-module-cache-path", str(temp / "modules")]
            for debug in (False, True):
                with self.subTest(debug=debug):
                    flags = ["-D", "DEBUG"] if debug else []
                    commands = [
                        common + ["-emit-library", "-emit-module", "-module-name", "Clarity",
                                  "-emit-module-path", str(temp / "Clarity.swiftmodule"),
                                  str(ROOT / "Scripts/tests/fixtures/ClarityStub.swift"), "-o", str(module)],
                        common + flags + ["-parse-as-library", "-I", str(temp), "-L", str(temp), "-lClarity",
                                          "-Xlinker", "-rpath", "-Xlinker", str(temp),
                                          str(APP / "Domain/Book/Book.swift"),
                                          str(APP / "Domain/Analytics/AnalyticsEvent.swift"),
                                          str(APP / "Domain/Analytics/SessionReplayConsent.swift"),
                                          str(APP / "Clients/Analytics/SessionReplayRuntime.swift"),
                                          str(ROOT / "Scripts/verify-session-replay.swift"), "-o", str(temp / "proof")],
                        [str(temp / "proof")],
                    ]
                    for command in commands:
                        result = subprocess.run(command, cwd=ROOT, env=os.environ.copy(),
                                                capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual("[ClarityDebug]" in result.stdout, debug)
                    if debug:
                        for event in ("consent_loaded", "initialization_blocked_by_policy",
                                      "initialize_requested", "session_started", "waiting_for_session",
                                      "protected_view_added", "protected_view_removed",
                                      "recording_allowed", "recording_blocked"):
                            self.assertIn("event=" + event, result.stdout)
                        for event in ("initialize_returned", "session_callback_registered",
                                      "sdk_consent_returned", "build_channel_tag_returned"):
                            self.assertIn("event=" + event + " result=false", result.stdout)
                        self.assertIn("protected_views=1", result.stdout)
                        self.assertIn("sdk_paused=false", result.stdout)
                        self.assertTrue(any(
                            "event=waiting_for_session" in line and "ready=false" in line
                            and "sdk_consent=true" in line and "sdk_paused=false" in line
                            for line in result.stdout.splitlines()))
                        self.assertNotIn("test-session", result.stdout)
                        self.assertNotIn("https://", result.stdout)


if __name__ == "__main__":
    unittest.main()
