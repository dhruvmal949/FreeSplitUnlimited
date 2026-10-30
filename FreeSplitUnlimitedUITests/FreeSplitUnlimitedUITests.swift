//
//  FreeSplitUnlimitedUITests.swift
//  FreeSplitUnlimitedUITests
//

import XCTest

final class FreeSplitUnlimitedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testEndToEndFriendSplitStaysOffHome() throws {
        let app = launchApp()
        allowSystemAlerts(app)

        signInWithNewAccount(app)
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 8))

        // Friends + creates a one-person split, not a group.
        tapTab(app, "Friends")
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 5))
        app.buttons["New Split"].tap()
        XCTAssertTrue(app.navigationBars["New Split"].waitForExistence(timeout: 5))

        let friendName = "Alex"
        addPerson(app, named: friendName)
        app.buttons["createSplitButton"].tap()

        XCTAssertTrue(app.staticTexts[friendName].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Back to friends"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Add people"].waitForExistence(timeout: 1))

        addExpense(app, title: "Dinner", amount: "40")
        XCTAssertTrue(app.staticTexts["Dinner"].waitForExistence(timeout: 5))

        // One-to-one splits stay on Friends, not Home.
        app.buttons["Back to friends"].tap()
        tapTab(app, "Groups")
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[friendName].waitForExistence(timeout: 1))

        tapTab(app, "Friends")
        XCTAssertTrue(app.staticTexts[friendName].waitForExistence(timeout: 5))
        tapRow(app, containing: friendName)
        XCTAssertTrue(app.buttons["Back to friends"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[friendName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["friendSharedGroup"].waitForExistence(timeout: 5))
        app.buttons["friendSharedGroup"].tap()
        XCTAssertTrue(app.buttons["Back to friends"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add people"].waitForExistence(timeout: 1))

        app.buttons["Back to friends"].tap()
        tapTab(app, "Groups")
        XCTAssertFalse(app.staticTexts[friendName].waitForExistence(timeout: 1), "A one-to-one split should stay off Home")

        // Home Create Group still makes a group immediately.
        app.buttons["Create Group"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 5))
        let groupField = app.textFields["groupNameField"]
        XCTAssertTrue(groupField.waitForExistence(timeout: 5))
        groupField.tap()
        groupField.typeText("Cabin Trip")
        app.buttons["createGroupSubmit"].tap()
        XCTAssertTrue(app.staticTexts["Cabin Trip"].waitForExistence(timeout: 6))
        app.buttons["Back to groups"].tap()
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cabin Trip"].waitForExistence(timeout: 4))

        tapTab(app, "Notifications")
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))

        tapTab(app, "Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign Out"].waitForExistence(timeout: 4))
        app.buttons["Sign Out"].tap()

        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["loginPasswordField"].exists)
        XCTAssertTrue(app.buttons["loginSignInButton"].exists)
        XCTAssertFalse(app.buttons["loginGuestButton"].exists)
        XCTAssertFalse(app.buttons["Guest"].exists)
    }

    @MainActor
    func testDeleteAsksBeforeRemovingGroupAndFriend() throws {
        let app = launchApp()
        allowSystemAlerts(app)
        signInWithNewAccount(app)
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 8))

        app.buttons["Create Group"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 5))
        let groupField = app.textFields["groupNameField"]
        XCTAssertTrue(groupField.waitForExistence(timeout: 5))
        groupField.tap()
        groupField.typeText("Cabin Trip")
        app.buttons["createGroupSubmit"].tap()
        XCTAssertTrue(app.staticTexts["Cabin Trip"].waitForExistence(timeout: 6))

        app.buttons["Group settings"].tap()
        XCTAssertTrue(app.navigationBars["Group Settings"].waitForExistence(timeout: 5))
        app.buttons["deleteGroupButton"].tap()

        let groupAlert = app.alerts["Are you sure you want to delete?"]
        XCTAssertTrue(groupAlert.waitForExistence(timeout: 4))
        groupAlert.buttons["No"].tap()
        XCTAssertTrue(app.navigationBars["Group Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(groupAlert.waitForExistence(timeout: 1))

        app.buttons["deleteGroupButton"].tap()
        XCTAssertTrue(groupAlert.waitForExistence(timeout: 4))
        groupAlert.buttons["Yes"].tap()
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Cabin Trip"].waitForExistence(timeout: 2))

        tapTab(app, "Friends")
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 5))
        app.buttons["New Split"].tap()
        XCTAssertTrue(app.navigationBars["New Split"].waitForExistence(timeout: 5))
        addPerson(app, named: "Alex")
        app.buttons["createSplitButton"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 6))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["deleteGroupButton"].tap()
        let friendAlert = app.alerts["Are you sure you want to delete?"]
        XCTAssertTrue(friendAlert.waitForExistence(timeout: 4))
        friendAlert.buttons["No"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        app.buttons["deleteGroupButton"].tap()
        XCTAssertTrue(friendAlert.waitForExistence(timeout: 4))
        friendAlert.buttons["Yes"].tap()
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Alex"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    @MainActor
    private func allowSystemAlerts(_ app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "System permission alerts") { alert in
            let denyTitles = ["Don’t Allow", "Don't Allow", "Not Now", "Cancel", "OK"]
            for title in denyTitles where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    @MainActor
    private func signInWithNewAccount(_ app: XCUIApplication) {
        let email = "e2e.\(Int(Date().timeIntervalSince1970))@example.com"
        let createAccount = app.buttons["loginCreateAccount"].firstMatch
        XCTAssertTrue(createAccount.waitForExistence(timeout: 8))
        if !createAccount.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(createAccount.waitForExistence(timeout: 2))
        createAccount.tap()
        XCTAssertTrue(app.navigationBars["New Account"].waitForExistence(timeout: 5))

        type(app.textFields["createFirstNameField"], "Pat")
        type(app.textFields["createLastNameField"], "Lee")
        type(app.textFields["createContactField"], email)
        tapKeyboardDone(app)
        type(app.secureTextFields["createPasswordField"], "secret1")
        type(app.secureTextFields["createConfirmPasswordField"], "secret1")
        tapKeyboardDone(app)
        let save = app.buttons["createSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: save)], timeout: 4) == .completed)
        save.tap()

        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 6))
        setText(app.secureTextFields["loginPasswordField"], "secret1")
        tapKeyboardDone(app)
        app.buttons["loginSignInButton"].tap()
    }

    @MainActor
    private func type(_ field: XCUIElement, _ text: String) {
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
    private func tapKeyboardDone(_ app: XCUIApplication) {
        let done = app.buttons["keyboardDone"]
        if done.waitForExistence(timeout: 1), done.isHittable {
            done.tap()
        }
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.buttons["tab-\(name)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab \(name)")
        tab.tap()
    }

    @MainActor
    private func tapRow(_ app: XCUIApplication, containing text: String) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing row containing \(text)")
        row.tap()
    }

    @MainActor
    private func addExpense(_ app: XCUIApplication, title: String, amount: String) {
        let addExpense = app.buttons["Add expense"]
        XCTAssertTrue(addExpense.waitForExistence(timeout: 5))
        addExpense.tap()

        let titleField = app.textFields["expenseTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)

        let amountField = app.textFields["expenseAmountField"]
        amountField.tap()
        amountField.typeText(amount)

        if app.buttons["Save Expense"].exists {
            app.swipeUp()
            app.buttons["Save Expense"].tap()
        } else {
            app.buttons["Add"].tap()
        }

        let saveAnyway = app.alerts.buttons["Save Anyway"]
        if saveAnyway.waitForExistence(timeout: 3) {
            saveAnyway.tap()
        }
    }

    @MainActor
    private func addPerson(_ app: XCUIApplication, named name: String) {
        app.buttons["Add people"].firstMatch.tap()
        let search = app.textFields["friendSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8), "Friend picker should open")
        search.tap()
        search.typeText(name)

        let typed = app.buttons["addTypedName"]
        XCTAssertTrue(typed.waitForExistence(timeout: 5), "Should be able to add \(name) by typing")
        typed.tap()

        let contactField = app.textFields["addFriendContactField"]
        XCTAssertTrue(contactField.waitForExistence(timeout: 5), "Add friend details should open")
        contactField.tap()
        contactField.typeText("\(name.lowercased())@example.com")
        app.buttons["addFriendNextButton"].tap()

        let confirm = app.buttons["confirmAddFriends"]
        if confirm.waitForExistence(timeout: 3) {
            confirm.tap()
        }
    }
}
