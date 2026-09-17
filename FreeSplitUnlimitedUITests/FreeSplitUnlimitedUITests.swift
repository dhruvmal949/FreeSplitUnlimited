//
//  FreeSplitUnlimitedUITests.swift
//  FreeSplitUnlimitedUITests
//

import XCTest

final class FreeSplitUnlimitedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEndToEndFriendSplitBecomesGroup() throws {
        let app = launchApp()
        allowSystemAlerts(app)

        continueAsGuest(app)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))

        // Friends + creates a one-person split, not a group.
        tapTab(app, "Friends")
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 5))
        app.buttons["New Split"].tap()
        XCTAssertTrue(app.navigationBars["New Split"].waitForExistence(timeout: 5))

        let friendName = "Alex"
        let friendField = app.textFields["friendNameField"]
        XCTAssertTrue(friendField.waitForExistence(timeout: 5))
        friendField.tap()
        friendField.typeText(friendName)
        app.buttons["createSplitButton"].tap()

        XCTAssertTrue(app.staticTexts[friendName].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Add people"].waitForExistence(timeout: 4))

        addExpense(app, title: "Dinner", amount: "40")
        XCTAssertTrue(app.staticTexts["Dinner"].waitForExistence(timeout: 5))

        // One-to-one splits stay off Home until a third person is added.
        app.buttons["Back to groups"].tap()
        tapTab(app, "Groups")
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[friendName].waitForExistence(timeout: 1))

        tapTab(app, "Friends")
        XCTAssertTrue(app.staticTexts[friendName].waitForExistence(timeout: 5))
        tapRow(app, containing: friendName)
        XCTAssertTrue(app.navigationBars[friendName].waitForExistence(timeout: 5))
        tapRow(app, containing: friendName)
        XCTAssertTrue(app.buttons["Add people"].waitForExistence(timeout: 5))

        addPerson(app, named: "Blair")
        XCTAssertFalse(
            app.staticTexts["This split is just the two of you. Adding more people saves it as a group."].waitForExistence(timeout: 1)
        )

        app.buttons["Back to groups"].tap()
        tapTab(app, "Groups")
        XCTAssertTrue(app.staticTexts[friendName].waitForExistence(timeout: 5), "Adding a third person should save the split as a group on Home")

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
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cabin Trip"].waitForExistence(timeout: 4))

        tapTab(app, "Notifications")
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))

        tapTab(app, "Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Guest"].waitForExistence(timeout: 4))
        app.buttons["Sign Out"].tap()

        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["loginEmailField"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.secureTextFields["loginPasswordField"].exists)
        XCTAssertTrue(app.buttons["loginSignInButton"].exists)
        XCTAssertTrue(app.buttons["loginGuestButton"].exists)
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
    private func continueAsGuest(_ app: XCUIApplication) {
        let guest = app.buttons["Guest"]
        XCTAssertTrue(guest.waitForExistence(timeout: 8), "Login screen should show Guest")
        guest.tap()
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
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
    }
}
