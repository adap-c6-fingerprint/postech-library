#!/usr/bin/env python3
"""실제 API/설정 없이 표지·추천·검색 캐시의 순수 로직을 macOS SwiftPM에서 검증한다."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-dir", type=Path, help="검증용 소스와 빌드 결과를 보관할 별도 경로")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    work = (args.scratch_dir or Path(tempfile.mkdtemp(prefix="recommendation-cache-tests-"))).resolve()
    assert work != repo and not work.is_relative_to(repo / "fingerprint-library")
    sources = work / "Sources/fingerprint_library"
    tests = work / "Tests/RecommendationTests"
    sources.mkdir(parents=True, exist_ok=True)
    tests.mkdir(parents=True, exist_ok=True)
    (work / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "RecommendationCacheValidation", platforms: [.macOS(.v15)], targets: [
    .target(name: "fingerprint_library", swiftSettings: [.defaultIsolation(MainActor.self)]),
    .testTarget(name: "RecommendationTests", dependencies: ["fingerprint_library"])
])
''')
    for relative in [
        "fingerprint-library/Domain/Book/Book.swift",
        "fingerprint-library/Clients/Book/Cache/RecommendationCacheStore.swift",
        "fingerprint-library/Clients/Book/Cache/RecommendationCachePreparer.swift",
        "fingerprint-library/Shared/BookCover/SharedImageLoader.swift",
        "fingerprint-library/Shared/BookCover/BookCoverFailure.swift",
        "fingerprint-library/Shared/BookCover/BookCoverModel.swift",
        "fingerprint-library/Clients/Book/Cache/BookSearchResultCache.swift",
    ]:
        path = repo / relative
        shutil.copy2(path, sources / path.name)
    for name in [
        "RecommendationCacheStoreTests.swift", "RecommendationCachePreparerTests.swift",
        "SharedImageLoaderTests.swift", "BookSearchResultCacheTests.swift",
        "BookCoverFailureTests.swift", "BookCoverModelTests.swift",
    ]:
        shutil.copy2(repo / "BookDetailTests" / name, tests / name)
    # SwiftPM 자체의 중첩 sandbox만 끈다. 공개 소스 사본과 가짜 응답만 빌드한다.
    command = [
        "xcrun", "swift", "test", "--disable-sandbox", "--package-path", str(work),
        "--cache-path", str(work / "cache"), "--config-path", str(work / "config"),
        "--security-path", str(work / "security"), "--scratch-path", str(work / "build"),
        "-Xswiftc", "-module-cache-path", "-Xswiftc", str(work / "module-cache"),
    ]
    # 상위 환경을 읽거나 API 인증 값을 검증 프로세스에 전달하지 않는다.
    environment = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "CLANG_MODULE_CACHE_PATH": str(work / "module-cache"),
    }
    result = subprocess.run(command, env=environment)
    print(f"검증 경로: {work}")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
