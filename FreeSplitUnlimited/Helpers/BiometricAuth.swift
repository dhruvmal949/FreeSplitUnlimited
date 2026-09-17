//
//  BiometricAuth.swift
//  FreeSplitUnlimited
//

import Foundation
import LocalAuthentication

@MainActor
enum BiometricAuth {
    static var canEvaluateOverride: Bool?
    static var evaluateOverride: (@MainActor () async throws -> Bool)?

    private static var activeContext: LAContext?

    static func resetOverrides() {
        canEvaluateOverride = nil
        evaluateOverride = nil
        cancel()
    }

    static func cancel() {
        let context = activeContext
        activeContext = nil
        context?.invalidate()
    }

    static func canEvaluate() -> (Bool, String?) {
        if let canEvaluateOverride {
            return (
                canEvaluateOverride,
                canEvaluateOverride ? nil : "Face ID isn’t available on this iPhone."
            )
        }
        if AppLaunchFlags.stubBiometrics {
            return (true, nil)
        }
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        guard ok else {
            return (false, error?.localizedDescription ?? "Face ID isn’t available on this iPhone.")
        }
        switch context.biometryType {
        case .faceID, .touchID, .opticID:
            return (true, nil)
        default:
            return (false, "Face ID isn’t available on this iPhone.")
        }
    }

    static func evaluate(reason: String) async throws -> Bool {
        if let evaluateOverride {
            return try await evaluateOverride()
        }
        if AppLaunchFlags.stubBiometrics {
            return true
        }
        cancel()
        let context = LAContext()
        activeContext = context
        context.localizedFallbackTitle = ""
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if activeContext === context { activeContext = nil }
            throw error ?? NSError(
                domain: LAError.errorDomain,
                code: LAError.biometryNotAvailable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Face ID isn’t available on this iPhone."]
            )
        }
        switch context.biometryType {
        case .faceID, .touchID, .opticID:
            break
        default:
            if activeContext === context { activeContext = nil }
            throw NSError(
                domain: LAError.errorDomain,
                code: LAError.biometryNotAvailable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Face ID isn’t available on this iPhone."]
            )
        }
        do {
            let matched = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if activeContext === context { activeContext = nil }
            return matched
        } catch {
            if activeContext === context { activeContext = nil }
            throw error
        }
    }
}
