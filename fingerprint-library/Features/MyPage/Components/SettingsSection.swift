//
//  SettingsSection.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지 "설정 및 안내" 목록
//  행마다 오른쪽에 chevron이 있고, 행 사이에 구분선이 있다.
//

import SwiftUI

struct SettingsSection: View {
    struct Row: Identifiable {
        let title: String
        var action: (() -> Void)?
        // nil이면 아직 기능명세가 없는 행이다. 눌러도 아무 일이 없다.
        var id: String { title }
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("설정 및 안내")
                .typography(.title2)
                .foregroundStyle(Color.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().overlay(Color.textTertiary.opacity(0.3))
                    }
                    rowView(row)
                }
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        Button {
            row.action?()
        } label: {
            HStack {
                Text(row.title)
                    .typography(.body1)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
