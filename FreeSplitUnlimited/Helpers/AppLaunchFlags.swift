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
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["XCTestBundlePath"] != nil { return true }
        if env["XCTestSessionIdentifier"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }

    static var isAutomatedTesting: Bool {
        isUITesting || isUnitTesting
    }

    /// UI tests use this so Face ID can be tapped without Simulator enrollment.
    static var stubBiometrics: Bool {
        ProcessInfo.processInfo.arguments.contains("-stub-biometrics")
    }
}
