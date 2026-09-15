//
//  AppLaunchFlags.swift
//  FreeSplitUnlimited
//

import Foundation

enum AppLaunchFlags {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isAutomatedTesting: Bool {
        isUITesting || isUnitTesting
    }

    /// UI tests use this so Face ID can be tapped without Simulator enrollment.
    static var stubBiometrics: Bool {
        ProcessInfo.processInfo.arguments.contains("-stub-biometrics")
    }
}
