//
//  AuthSessionTests.swift
//  FreeSplitUnlimitedTests
//

import XCTest
import LocalAuthentication
@testable import FreeSplitUnlimited

@MainActor
final class AuthSessionTests: XCTestCase {
    private var session: AuthSession { AuthSession.shared }

    override func setUp() {
        super.setUp()
        session.resetForTesting()
    }

    override func tearDown() {
        session.resetForTesting()
        super.tearDown()
    }

    func testLogInRequiresEmailOrPhone() {
        XCTAssertEqual(session.logIn(username: "   ", password: "secret1"), "Enter your email or phone number.")
        XCTAssertFalse(session.isAuthenticated)
    }

    func testLogInRequiresPassword() {
        XCTAssertEqual(session.logIn(username: "pat@example.com", password: ""), "Enter a password.")
        XCTAssertFalse(session.isAuthenticated)
    }

    func testLogInUnknownAccount() {
        XCTAssertEqual(
            session.logIn(username: "missing@example.com", password: "secret1"),
            "No account with that email or phone. Create an account first."
        )
        XCTAssertFalse(session.isAuthenticated)
    }

    func testRegistrationValidatesEveryField() {
        XCTAssertEqual(
            session.beginRegistration(firstName: "", lastName: "Lee", email: "pat@example.com", phone: "", password: "secret1", confirmPassword: "secret1"),
            "Enter your first name."
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "", email: "pat@example.com", phone: "", password: "secret1", confirmPassword: "secret1"),
            "Enter your last name."
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "Lee", email: "", phone: "", password: "secret1", confirmPassword: "secret1"),
            "Enter an email or a 10-digit US phone number."
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "Lee", email: "not-an-email", phone: "", password: "secret1", confirmPassword: "secret1"),
            "Enter a valid email address."
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "Lee", email: "pramela@gmail.comffghh@nm@vhn", phone: "", password: "secret1", confirmPassword: "secret1"),
            "Enter a valid email address."
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "Lee", email: "pat@example", phone: "", password: "secret1", confirmPassword: "secret1"),
            "Enter a valid email address."
        )
        XCTAssertEqual(
            constrainedEmailInput("pramela@gmail.comffghh@nm@ vhn", previous: ""),
            "pramela@gmail.com"
        )
        XCTAssertEqual(
            constrainedEmailInput("pramela@gmail.comf", previous: "pramela@gmail.com"),
            "pramela@gmail.com"
        )
        XCTAssertEqual(
            constrainedEmailInput("pramela@gmail.com", previous: "pramela@gmail.co"),
            "pramela@gmail.com"
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "Lee", email: "", phone: "5551234", password: "secret1", confirmPassword: "secret1"),
            "Enter a 10-digit US phone number."
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "Lee", email: "pat@example.com", phone: "", password: "123", confirmPassword: "123"),
            "Password needs at least 6 characters."
        )
        XCTAssertEqual(
            session.beginRegistration(firstName: "Pat", lastName: "Lee", email: "pat@example.com", phone: "", password: "secret1", confirmPassword: "secret2"),
            "Passwords don't match."
        )
        XCTAssertNil(session.pendingVerification)
    }

    func testEmailRegistrationAndLogin() {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.displayName, "Pat Lee")
        XCTAssertEqual(session.email, "pat@example.com")
        XCTAssertEqual(session.signedInHandle, "pat@example.com")
        XCTAssertEqual(session.provider.title, "Email or phone")
        XCTAssertEqual(session.provider, .password)

        session.signOut()
        XCTAssertFalse(session.isAuthenticated)

        XCTAssertEqual(session.logIn(username: "pat@example.com", password: "wrong-password"), "Wrong password.")
        XCTAssertNil(session.logIn(username: "PAT@example.com", password: "secret1"))
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.displayName, "Pat Lee")
    }

    func testPhoneRegistrationAndLoginIgnoresFormatting() {
        XCTAssertNil(register(first: "Sam", last: "Ortiz", phone: "(555) 123-4567", password: "phone12"))
        session.signOut()

        XCTAssertNil(session.logIn(username: "5551234567", password: "phone12"))
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.displayName, "Sam Ortiz")
        XCTAssertEqual(session.signedInHandle, "(555) 123-4567")
    }

    func testDuplicateEmailOrPhoneIsRejected() {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()

        XCTAssertEqual(
            session.beginRegistration(firstName: "Other", lastName: "Person", email: "pat@example.com", phone: "", password: "secret1", confirmPassword: "secret1"),
            "An account with that email already exists. Sign in, or use a different phone or email."
        )
    }

    func testDuplicatePhoneIsRejected() {
        XCTAssertNil(register(first: "Sam", last: "Ortiz", phone: "5551234567", password: "phone12"))
        session.signOut()

        XCTAssertEqual(
            session.beginRegistration(
                firstName: "Other",
                lastName: "Person",
                contact: "(555) 123-4567",
                password: "secret1",
                confirmPassword: "secret1"
            ),
            "An account with that phone number already exists. Sign in, or use a different phone or email."
        )
    }

    func testCreateAccountSavesOnDeviceWithoutSigningIn() {
        XCTAssertNil(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                contact: "pat@example.com",
                password: "secret1",
                confirmPassword: "secret1"
            )
        )
        XCTAssertNil(session.pendingVerification)
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertEqual(session.rememberedLogin, "pat@example.com")

        XCTAssertNil(session.logIn(username: "pat@example.com", password: "secret1"))
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.displayName, "Pat Lee")
    }

    func testContactFieldRequiresTenDigitPhoneOrEmail() {
        XCTAssertEqual(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                contact: "5551234",
                password: "secret1",
                confirmPassword: "secret1"
            ),
            "Enter a 10-digit US phone number."
        )
        XCTAssertEqual(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                contact: "not-an-email",
                password: "secret1",
                confirmPassword: "secret1"
            ),
            "Enter a 10-digit US phone number."
        )
        XCTAssertNil(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                contact: "+1 555-123-4567",
                password: "secret1",
                confirmPassword: "secret1"
            )
        )
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(session.logIn(username: "+15551234567", password: "secret1"))
        XCTAssertTrue(session.isAuthenticated)
        session.signOut()
        XCTAssertNil(session.logIn(username: "5551234567", password: "secret1"))
        XCTAssertTrue(session.isAuthenticated)
    }

    func testExistingAccountPointsDuplicateEmailAndPhoneToSignIn() {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        XCTAssertEqual(session.existingAccount(matching: "pat@example.com"), .email)

        XCTAssertNil(register(first: "Sam", last: "Ortiz", phone: "5551234567", password: "phone12"))
        XCTAssertEqual(session.existingAccount(matching: "+1 (555) 123-4567"), .phone)
        XCTAssertNil(session.existingAccount(matching: "new@example.com"))
    }

    func testFaceIDOptInYesKeepsPreferenceAfterSignOut() {
        session.testingAsksFaceIDOptIn = true
        BiometricAuth.canEvaluateOverride = true
        XCTAssertNil(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                contact: "pat@example.com",
                password: "secret1",
                confirmPassword: "secret1"
            )
        )

        XCTAssertNil(session.logIn(username: "pat@example.com", password: "secret1"))
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(session.needsFaceIDOptIn)

        session.answerFaceIDOptIn(true)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertTrue(session.prefersFaceIDLogin)
        XCTAssertFalse(session.needsFaceIDOptIn)

        session.signOut()
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(session.prefersFaceIDLogin)
        XCTAssertFalse(session.shouldAutoPromptFaceID)
        XCTAssertTrue(session.isFaceIDInSignOutCooldown)
        XCTAssertTrue(session.hasUnlockableAccount)

        session.expireFaceIDSignOutCooldownForTesting()
        BiometricAuth.canEvaluateOverride = true
        XCTAssertTrue(session.shouldAutoPromptFaceID)
        XCTAssertGreaterThan(AuthSession.signOutFaceIDCooldown, 4)
    }

    func testFaceIDOptInNoShowsLoginOnReturn() {
        session.testingAsksFaceIDOptIn = true
        BiometricAuth.canEvaluateOverride = true
        XCTAssertNil(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                contact: "pat@example.com",
                password: "secret1",
                confirmPassword: "secret1"
            )
        )

        XCTAssertNil(session.logIn(username: "pat@example.com", password: "secret1"))
        session.answerFaceIDOptIn(false)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertFalse(session.prefersFaceIDLogin)

        session.signOut()
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertFalse(session.shouldAutoPromptFaceID)
        XCTAssertTrue(session.hasUnlockableAccount)
    }

    func testResetPasswordKeepsNameAndEmail() {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()

        XCTAssertEqual(session.resetPassword(username: "", newPassword: "newer12", confirmPassword: "newer12"), "Enter your email or phone number.")
        XCTAssertEqual(session.resetPassword(username: "not-an-email", newPassword: "newer12", confirmPassword: "newer12"), "Enter a 10-digit phone number.")
        XCTAssertEqual(session.resetPassword(username: "pat@example", newPassword: "newer12", confirmPassword: "newer12"), "Enter a valid email address.")
        XCTAssertEqual(session.resetPassword(username: "pat@example.com", newPassword: "short", confirmPassword: "short"), "Password needs at least 6 characters.")
        XCTAssertEqual(session.resetPassword(username: "pat@example.com", newPassword: "newer12", confirmPassword: "nope12"), "Passwords don't match.")
        XCTAssertEqual(session.resetPassword(username: "missing@example.com", newPassword: "newer12", confirmPassword: "newer12"), "No account with that email or phone on this iPhone.")

        XCTAssertNil(session.resetPassword(username: "pat@example.com", newPassword: "newer12", confirmPassword: "newer12"))
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertEqual(session.rememberedLogin, "pat@example.com")

        XCTAssertEqual(session.logIn(username: "pat@example.com", password: "secret1"), "Wrong password.")
        XCTAssertNil(session.logIn(username: "pat@example.com", password: "newer12"))
        XCTAssertEqual(session.displayName, "Pat Lee")
        XCTAssertEqual(session.email, "pat@example.com")
    }

    func testGuestDoesNotCreateUnlockableAccount() {
        session.continueAsGuest()
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertTrue(session.isGuest)
        XCTAssertEqual(session.displayName, "Guest")
        session.signOut()
        XCTAssertFalse(session.hasUnlockableAccount)
    }

    func testGoogleEmailConfirmation() {
        XCTAssertEqual(session.confirmGoogleEmail("not-an-email"), "Enter the Google email you just signed in with.")
        XCTAssertNil(session.confirmGoogleEmail("pat.lee@gmail.com"))
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.provider, .google)
        XCTAssertEqual(session.email, "pat.lee@gmail.com")
        XCTAssertEqual(session.displayName, "pat.lee")
        XCTAssertTrue(session.shouldOpenGoogleSignIn)
    }

    func testFaceIDRequiresAnExistingAccount() async {
        let message = await session.unlockWithFaceID()
        XCTAssertEqual(message, "Create an account and sign in first, then you can use Face ID.")
        XCTAssertFalse(session.canOfferFaceID)
    }

    func testFaceIDUnavailableWhenBiometricsAreOff() async {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()
        XCTAssertTrue(session.hasUnlockableAccount)

        BiometricAuth.canEvaluateOverride = false
        XCTAssertFalse(session.canOfferFaceID)
        let message = await session.unlockWithFaceID()
        XCTAssertEqual(message, "Face ID isn’t available on this iPhone.")
        XCTAssertFalse(session.isAuthenticated)
    }

    func testFaceIDUnlocksExistingAccount() async {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()
        XCTAssertFalse(session.isAuthenticated)

        BiometricAuth.canEvaluateOverride = true
        BiometricAuth.evaluateOverride = { true }
        XCTAssertTrue(session.canOfferFaceID)
        XCTAssertEqual(session.faceIDButtonTitle, "Open with Face ID")
        XCTAssertEqual(session.unlockAccountHint, "pat@example.com")

        let message = await session.unlockWithFaceID()
        XCTAssertNil(message)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertFalse(session.isGuest)
        XCTAssertEqual(session.displayName, "Pat Lee")
        XCTAssertEqual(session.email, "pat@example.com")
        XCTAssertEqual(session.provider, .password)
    }

    func testFaceIDMismatchDoesNotOpenTheAccount() async {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()

        BiometricAuth.canEvaluateOverride = true
        BiometricAuth.evaluateOverride = { false }
        let mismatch = await session.unlockWithFaceID()
        XCTAssertEqual(mismatch, "Face ID didn’t match.")
        XCTAssertFalse(session.isAuthenticated)
    }

    func testFaceIDCancelLeavesUserOnLogin() async {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()

        BiometricAuth.canEvaluateOverride = true
        BiometricAuth.evaluateOverride = {
            throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue)
        }
        let cancelMessage = await session.unlockWithFaceID()
        XCTAssertNil(cancelMessage)
        XCTAssertFalse(session.isAuthenticated)
    }

    func testGuestCannotUseFaceID() {
        session.continueAsGuest()
        session.signOut()
        BiometricAuth.canEvaluateOverride = true
        XCTAssertFalse(session.hasUnlockableAccount)
        XCTAssertFalse(session.canOfferFaceID)
    }

    func testCreatedAccountCanUseFaceIDAfterSave() {
        XCTAssertNil(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                contact: "pat@example.com",
                password: "secret1",
                confirmPassword: "secret1"
            )
        )
        BiometricAuth.canEvaluateOverride = true
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(session.hasUnlockableAccount)
        XCTAssertTrue(session.canOfferFaceID)
    }

    func testGoogleSignInDoesNotEnableFaceID() {
        XCTAssertNil(session.confirmGoogleEmail("pat.lee@gmail.com"))
        session.signOut()
        BiometricAuth.canEvaluateOverride = true
        XCTAssertFalse(session.hasUnlockableAccount)
        XCTAssertFalse(session.canOfferFaceID)
    }

    func testSignOutStaysOnLoginUntilFaceIDMatches() async {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(session.hasUnlockableAccount)

        BiometricAuth.canEvaluateOverride = true
        BiometricAuth.evaluateOverride = { false }
        _ = await session.unlockWithFaceID()
        XCTAssertFalse(session.isAuthenticated)
    }

    func testVerifiedPasswordAccountBecomesUnlockable() {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        XCTAssertTrue(session.hasUnlockableAccount)
        XCTAssertEqual(session.unlockAccountHint, "pat@example.com")
        XCTAssertEqual(session.lastUnlockProvider, .password)
    }

    func testNewPhoneAccountIsOpenedInsteadOfOlderEmailAccount() async {
        XCTAssertNil(register(first: "Pat", last: "Lee", email: "pat@example.com", password: "secret1"))
        session.signOut()
        XCTAssertEqual(session.unlockAccountHint, "pat@example.com")

        XCTAssertNil(
            session.beginRegistration(
                firstName: "Pat",
                lastName: "Lee",
                email: "",
                phone: "5551234567",
                password: "phone12",
                confirmPassword: "phone12"
            )
        )
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertEqual(session.rememberedLogin, "5551234567")
        XCTAssertEqual(session.unlockAccountHint, "5551234567")

        XCTAssertNil(session.logIn(username: "5551234567", password: "phone12"))
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.displayName, "Pat Lee")
        XCTAssertEqual(session.email, "")

        session.signOut()
        BiometricAuth.canEvaluateOverride = true
        BiometricAuth.evaluateOverride = { true }
        let message = await session.unlockWithFaceID()
        XCTAssertNil(message)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.email, "")
        XCTAssertEqual(session.unlockAccountHint, "5551234567")
    }

    private func register(first: String, last: String, email: String = "", phone: String = "", password: String) -> String? {
        if let error = session.beginRegistration(
            firstName: first,
            lastName: last,
            email: email,
            phone: phone,
            password: password,
            confirmPassword: password
        ) {
            return error
        }
        let login = email.isEmpty ? phone : email
        return session.logIn(username: login, password: password)
    }
}
