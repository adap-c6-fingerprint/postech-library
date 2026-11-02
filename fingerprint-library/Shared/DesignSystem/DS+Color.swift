//
//  DS+Color.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/2/26.
//

import SwiftUI

enum DS {
    enum lime {
        static let C5E300 = Color(red: 0xC5 / 255, green: 0xE3 / 255, blue: 0x00 / 255)
        static let F7FDCE = Color(red: 0xF7 / 255, green: 0xFD / 255, blue: 0xCE / 255)
        static let EEFA9E = Color(red: 0xEE / 255, green: 0xFA / 255, blue: 0x9E / 255)
        static let E6F86D = Color(red: 0xE6 / 255, green: 0xF8 / 255, blue: 0x6D / 255)
        static let DDF53C = Color(red: 0xDD / 255, green: 0xF5 / 255, blue: 0x3C / 255)
        static let BBCE3A = Color(red: 0xBB / 255, green: 0xCE / 255, blue: 0x3A / 255)
        static let _99A738 = Color(red: 0x99 / 255, green: 0xA7 / 255, blue: 0x38 / 255)
        static let _778137 = Color(red: 0x77 / 255, green: 0x81 / 255, blue: 0x37 / 255)
    }

    enum key {
        static let dark = lime.C5E300
        static let _100 = lime.F7FDCE
        static let _200 = lime.EEFA9E
        static let _300 = lime.E6F86D
        static let base = lime.DDF53C
        static let _700 = lime.BBCE3A
        static let _800 = lime._99A738
        static let _900 = lime._778137
    }

    enum gray {
        static let _121212 = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
        static let F9F9F9 = Color(red: 0xF9 / 255, green: 0xF9 / 255, blue: 0xF9 / 255)
        static let F3F3F3 = Color(red: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF3 / 255)
        static let D9D9D9 = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
    }

    enum background {
        static let `default` = gray._121212
    }

    enum text {
        static let primary = gray.F9F9F9
        static let secondary = gray.F3F3F3
        static let tertiary = gray.D9D9D9
    }
}
