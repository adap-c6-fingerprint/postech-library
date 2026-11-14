//
//  LocationDiagnosticsSharedKeys.swift
//  fingerprint-library
//
//  실시간 안내 위치 측정 모드(실험 브랜치 전용).
//  검색창에 `/test`를 입력해 켜고 끈다. 켜져 있으면 길안내를 시작할 때마다 진단 기록이 자동으로 시작되고,
//  안내가 끝나면 자동으로 저장된다. QA와 현장 데이터 확보용이며 앱을 다시 켜도 유지된다.
//

import ComposableArchitecture
import Foundation

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    nonisolated static var locationDiagnosticsAutoRecord: Self {
        Self[.appStorage("locationDiagnosticsAutoRecord"), default: false]
    }
}
