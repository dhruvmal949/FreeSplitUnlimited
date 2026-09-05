//
//  AppLaunchFlags.swift
//  FreeSplitUnlimited
//

import Foundation

enum AppLaunchFlags {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }
}
