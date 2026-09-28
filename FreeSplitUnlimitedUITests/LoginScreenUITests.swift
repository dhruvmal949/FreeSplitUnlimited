//
//  LoginScreenUITests.swift
//  FreeSplitUnlimitedUITests
//

import XCTest

final class LoginScreenUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLoginScreenShowsAllFields() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["loginAppleButton"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["loginGoogleButton"].exists)
        XCTAssertFalse(app.buttons["loginFacebookButton"].exists)
        XCTAssertFalse(app.textFields["loginEmailField"].exists)
        XCTAssertFalse(app.secureTextFields["loginPasswordField"].exists)
        XCTAssertFalse(app.buttons["loginRememberMe"].exists)
        XCTAssertFalse(app.buttons["loginForgotPassword"].exists)
        XCTAssertFalse(app.buttons["loginSignInButton"].exists)
        XCTAssertFalse(app.buttons["loginCreateAccount"].exists)
        XCTAssertFalse(app.buttons["loginGuestButton"].exists)
        XCTAssertFalse(app.buttons["Guest"].exists)
        XCTAssertFalse(app.buttons["loginFaceIDButton"].exists)
    }

    @MainActor
    func testSignInStaysDisabledUntilBothFieldsAreFilled() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp()
        let email = app.textFields["loginEmailField"]
        let password = app.secureTextFields["loginPasswordField"]
        let signIn = app.buttons["loginSignInButton"]

        XCTAssertTrue(email.waitForExistence(timeout: 6))
        XCTAssertFalse(signIn.isEnabled)

        email.tap()
        email.typeText("pat@example.com")
        XCTAssertFalse(signIn.isEnabled)

        password.tap()
        password.typeText("secret1")
        XCTAssertTrue(signIn.isEnabled)
    }

    @MainActor
    func testUnknownAccountShowsErrorOnSignIn() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp()
        fillLogin(app, email: "missing@example.com", password: "secret1")
        dismissKeyboard(app)
        app.buttons["loginSignInButton"].tap()

        let error = app.staticTexts["loginErrorLabel"]
        XCTAssertTrue(error.waitForExistence(timeout: 4))
        XCTAssertTrue(error.label.contains("No account"))
        XCTAssertTrue(app.textFields["loginEmailField"].exists)
    }

    @MainActor
    func testRememberMeToggleFlips() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp()
        let rememberMe = app.buttons["loginRememberMe"]
        XCTAssertTrue(rememberMe.waitForExistence(timeout: 6))
        rememberMe.tap()
        XCTAssertTrue(rememberMe.exists)
    }

    @MainActor
    func testCreateAccountShowsAllFieldsAndSaveStaysDisabledUntilValid() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp()
        app.buttons["loginCreateAccount"].tap()

        XCTAssertTrue(app.navigationBars["New Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["createFirstNameField"].exists)
        XCTAssertTrue(app.textFields["createLastNameField"].exists)
        XCTAssertTrue(app.textFields["createContactField"].exists)
        XCTAssertFalse(app.textFields["createPhoneField"].exists)
        XCTAssertTrue(app.secureTextFields["createPasswordField"].exists)
        XCTAssertTrue(app.secureTextFields["createConfirmPasswordField"].exists)

        let save = app.buttons["createSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertFalse(save.isEnabled)

        type(app.textFields["createFirstNameField"], "Pat")
        type(app.textFields["createLastNameField"], "Lee")
        type(app.textFields["createContactField"], "not-an-email")
        tapKeyboardDone(app)
        type(app.secureTextFields["createPasswordField"], "secret1")
        type(app.secureTextFields["createConfirmPasswordField"], "secret1")
        tapKeyboardDone(app)
        XCTAssertFalse(save.isEnabled, "Invalid email or phone should keep Save disabled")

        setText(app.textFields["createContactField"], "pat.ui@example.com")
        tapKeyboardDone(app)
        XCTAssertTrue(waitUntilEnabled(save))
    }

    @MainActor
    func testForgotPasswordShowsAllFields() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp()
        app.buttons["loginForgotPassword"].tap()

        XCTAssertTrue(app.textFields["forgotEmailField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["forgotNewPasswordField"].exists)
        XCTAssertTrue(app.secureTextFields["forgotConfirmPasswordField"].exists)

        let reset = app.buttons["forgotResetButton"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        XCTAssertFalse(reset.isEnabled)

        setText(app.textFields["forgotEmailField"], "missing@example.com")
        setText(app.secureTextFields["forgotNewPasswordField"], "newer12")
        setText(app.secureTextFields["forgotConfirmPasswordField"], "newer12")
        XCTAssertTrue(waitUntilEnabled(reset), "Reset should enable once email and matching passwords are filled")
        reset.tap()

        let error = app.staticTexts["forgotErrorLabel"]
        XCTAssertTrue(error.waitForExistence(timeout: 4))
        XCTAssertTrue(error.label.contains("No account"))
    }

    @MainActor
    func testLoginScreenDoesNotOfferGuest() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["loginAppleButton"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["loginGuestButton"].exists)
        XCTAssertFalse(app.buttons["Guest"].exists)
        XCTAssertFalse(app.buttons["Continue as Guest"].exists)
    }

    @MainActor
    func testCreateAccountEmailFlowThenSignInAndResetPassword() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp()
        let email = "login.ui.\(Int(Date().timeIntervalSince1970))@example.com"
        let firstPassword = "secret1"
        let nextPassword = "newer12"

        app.buttons["loginCreateAccount"].tap()
        XCTAssertTrue(app.navigationBars["New Account"].waitForExistence(timeout: 5))
        type(app.textFields["createFirstNameField"], "Pat")
        type(app.textFields["createLastNameField"], "Lee")
        type(app.textFields["createContactField"], email)
        tapKeyboardDone(app)
        type(app.secureTextFields["createPasswordField"], firstPassword)
        type(app.secureTextFields["createConfirmPasswordField"], firstPassword)
        tapKeyboardDone(app)
        XCTAssertTrue(waitUntilEnabled(app.buttons["createSaveButton"]))
        app.buttons["createSaveButton"].tap()

        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.textFields["loginEmailField"].value as? String, email)
        setText(app.secureTextFields["loginPasswordField"], firstPassword)
        dismissKeyboard(app)
        app.buttons["loginSignInButton"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 8))

        tapTab(app, "Settings")
        XCTAssertTrue(app.staticTexts["Pat Lee"].waitForExistence(timeout: 5))
        app.buttons["Sign Out"].tap()
        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 5))

        XCTAssertEqual(app.textFields["loginEmailField"].value as? String, email)
        setText(app.secureTextFields["loginPasswordField"], "wrong-password")
        dismissKeyboard(app)
        app.buttons["loginSignInButton"].tap()
        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 3))
        let loginError = app.staticTexts["loginErrorLabel"]
        XCTAssertTrue(loginError.waitForExistence(timeout: 4))
        XCTAssertTrue(
            loginError.label.contains("Wrong password"),
            "Unexpected login error: \(loginError.label)"
        )

        setText(app.secureTextFields["loginPasswordField"], firstPassword)
        dismissKeyboard(app)
        app.buttons["loginSignInButton"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 8))

        tapTab(app, "Settings")
        app.buttons["Sign Out"].tap()
        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 5))

        app.buttons["loginForgotPassword"].tap()
        XCTAssertTrue(app.textFields["forgotEmailField"].waitForExistence(timeout: 5))
        type(app.textFields["forgotEmailField"], email)
        tapKeyboardDone(app)
        type(app.secureTextFields["forgotNewPasswordField"], nextPassword)
        type(app.secureTextFields["forgotConfirmPasswordField"], nextPassword)
        tapKeyboardDone(app)
        XCTAssertTrue(waitUntilEnabled(app.buttons["forgotResetButton"]))
        app.buttons["forgotResetButton"].tap()
        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.textFields["loginEmailField"].value as? String, email)

        fillLogin(app, email: email, password: nextPassword)
        dismissKeyboard(app)
        app.buttons["loginSignInButton"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testCreateAccountPhoneFieldEnablesSaveWithoutEmail() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp()
        app.buttons["loginCreateAccount"].tap()
        XCTAssertTrue(app.navigationBars["New Account"].waitForExistence(timeout: 5))

        type(app.textFields["createFirstNameField"], "Sam")
        type(app.textFields["createLastNameField"], "Ortiz")
        tapKeyboardDone(app)
        let phoneKind = app.segmentedControls["createContactKind"].buttons["Phone"]
        XCTAssertTrue(phoneKind.waitForExistence(timeout: 3))
        phoneKind.tap()
        type(app.textFields["createContactField"], "5551234567")
        tapKeyboardDone(app)
        type(app.secureTextFields["createPasswordField"], "phone12")
        type(app.secureTextFields["createConfirmPasswordField"], "phone12")
        tapKeyboardDone(app)
        XCTAssertTrue(waitUntilEnabled(app.buttons["createSaveButton"]))
    }

    @MainActor
    func testFaceIDButtonUnlocksExistingAccount() throws {
        try skipUnlessPasswordLoginEnabled()
        let app = launchApp(arguments: ["-stub-biometrics"])
        let email = "faceid.ui.\(Int(Date().timeIntervalSince1970))@example.com"

        app.buttons["loginCreateAccount"].tap()
        XCTAssertTrue(app.navigationBars["New Account"].waitForExistence(timeout: 5))
        type(app.textFields["createFirstNameField"], "Pat")
        type(app.textFields["createLastNameField"], "Lee")
        type(app.textFields["createContactField"], email)
        tapKeyboardDone(app)
        type(app.secureTextFields["createPasswordField"], "secret1")
        type(app.secureTextFields["createConfirmPasswordField"], "secret1")
        tapKeyboardDone(app)
        XCTAssertTrue(waitUntilEnabled(app.buttons["createSaveButton"]))
        app.buttons["createSaveButton"].tap()

        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 6))
        setText(app.secureTextFields["loginPasswordField"], "secret1")
        dismissKeyboard(app)
        app.buttons["loginSignInButton"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 8))

        tapTab(app, "Settings")
        app.buttons["Sign Out"].tap()
        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 5))

        let faceID = app.buttons["loginFaceIDButton"]
        XCTAssertTrue(faceID.waitForExistence(timeout: 5), "Returning accounts should show Face ID")
        XCTAssertTrue(faceID.label.contains("Face ID"), "Face ID control label: \(faceID.label)")
        faceID.tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 8))

        tapTab(app, "Settings")
        XCTAssertTrue(app.staticTexts["Pat Lee"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func skipUnlessPasswordLoginEnabled(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try XCTSkipUnless(
            false,
            "Email/phone password login is hidden until that flow is finished.",
            file: file,
            line: line
        )
    }

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.buttons["tab-\(name)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab \(name)")
        tab.tap()
    }

    @MainActor
    private func fillLogin(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["loginEmailField"]
        let passwordField = app.secureTextFields["loginPasswordField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        setText(emailField, email)
        setText(passwordField, password)
    }

    @MainActor
    private func type(_ field: XCUIElement, _ text: String) {
        setText(field, text)
    }

    @MainActor
    private func replaceText(_ field: XCUIElement, with text: String) {
        setText(field, text)
    }

    @MainActor
    private func setText(_ field: XCUIElement, _ text: String) {
        let app = XCUIApplication()
        tapKeyboardDone(app)
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        if app.keyboards.count == 0 {
            field.tap()
        }
        if let current = field.value as? String,
           !current.isEmpty,
           current != field.placeholderValue {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4))
        }
        field.typeText(text)
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        tapKeyboardDone(app)
    }

    @MainActor
    private func tapKeyboardDone(_ app: XCUIApplication) {
        let done = app.buttons["keyboardDone"]
        if done.waitForExistence(timeout: 1), done.isHittable {
            done.tap()
        }
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
