//
//  FreeSplitUnlimitedTests.swift
//  FreeSplitUnlimitedTests
//

import XCTest
@testable import FreeSplitUnlimited

final class FreeSplitUnlimitedTests: XCTestCase {

    func testEqualSplitBalances() throws {
        let occasion = Occasion(name: "Dinner")
        let alex = Person(name: "Alex")
        let blair = Person(name: "Blair")
        occasion.members = [alex, blair]

        let expense = Expense(
            title: "Pizza",
            amount: 40,
            splitMethod: .equal,
            paidBy: alex,
            participants: [alex, blair]
        )
        occasion.expenses = [expense]

        let balances = BalanceCalculator.balances(for: occasion)
        XCTAssertEqual(balances.first { $0.person.name == "Alex" }?.net, 20)
        XCTAssertEqual(balances.first { $0.person.name == "Blair" }?.net, -20)
    }

    func testPercentageSplitBalances() throws {
        let occasion = Occasion(name: "Groceries")
        let mom = Person(name: "Mom")
        let dad = Person(name: "Dad")
        occasion.members = [mom, dad]

        let expense = Expense(
            title: "Milk",
            amount: 100,
            splitMethod: .percentage,
            paidBy: mom,
            participants: [mom, dad],
            shares: [
                ExpenseShare(person: mom, value: 70),
                ExpenseShare(person: dad, value: 30)
            ]
        )
        occasion.expenses = [expense]

        let balances = BalanceCalculator.balances(for: occasion)
        // Mom paid 100, owes 70 → net +30. Dad owes 30 → net -30.
        XCTAssertEqual(balances.first { $0.person.name == "Mom" }?.net, 30)
        XCTAssertEqual(balances.first { $0.person.name == "Dad" }?.net, -30)
    }

    func testPartsSplitBalances() throws {
        let occasion = Occasion(name: "Trip")
        let alex = Person(name: "Alex")
        let blair = Person(name: "Blair")
        occasion.members = [alex, blair]

        let expense = Expense(
            title: "Hotel",
            amount: 90,
            splitMethod: .parts,
            paidBy: blair,
            participants: [alex, blair],
            shares: [
                ExpenseShare(person: alex, value: 1),
                ExpenseShare(person: blair, value: 2)
            ]
        )
        occasion.expenses = [expense]

        let balances = BalanceCalculator.balances(for: occasion)
        // Alex owes 30, Blair paid 90 and owes 60 → net +30.
        XCTAssertEqual(balances.first { $0.person.name == "Alex" }?.net, -30)
        XCTAssertEqual(balances.first { $0.person.name == "Blair" }?.net, 30)
    }
}
