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

    func testShareLinkRoundTripsJSON() throws {
        let original = Data(#"{"exportedAt":"2026-09-03T18:19:07Z","kind":"freeSplit.share","version":1}"#.utf8)
        let url = try SplitShare.shareURL(fromJSON: original)
        XCTAssertEqual(url.scheme, "freesplit")
        XCTAssertEqual(url.host, "i")
        XCTAssertFalse(url.absoluteString.contains("{"))
        let roundTrip = try SplitShare.json(fromShareURL: url)
        XCTAssertEqual(roundTrip, original)
    }

    func testCompactShareRoundTrip() throws {
        let occasion = BackupOccasion(
            id: UUID(uuidString: "99133D8A-3547-4620-8B87-03BE3222D22F")!,
            name: "Vegas Trip",
            note: "",
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_100),
            isDeleted: false,
            groupType: "trip",
            members: [
                BackupPerson(id: UUID(uuidString: "F6F1ED8A-228A-4410-8D51-F578AC3761F6")!, name: "Me", email: "", phone: "")
            ],
            expenses: []
        )
        let package = SplitShare.Package(exportedAt: Date(timeIntervalSince1970: 1_000_200), occasion: occasion)
        let data = try ShareLink.payload(from: package)
        let decoded = try ShareLink.package(fromPayload: data)
        XCTAssertEqual(decoded.occasion.name, "Vegas Trip")
        XCTAssertEqual(decoded.occasion.id, occasion.id)
        XCTAssertEqual(decoded.occasion.members.first?.name, "Me")
    }

    func testOneToOneSplitPromotesToGroupAtThreePeople() {
        let occasion = Occasion(name: "Alex", groupType: SplitKind.oneToOne)
        occasion.members = [Person(name: "Me"), Person(name: "Alex")]

        XCTAssertTrue(occasion.isOneToOne)
        XCTAssertFalse(occasion.appearsInGroups)

        occasion.members.append(Person(name: "Blair"))
        occasion.promoteToGroupIfNeeded()

        XCTAssertFalse(occasion.isOneToOne)
        XCTAssertTrue(occasion.appearsInGroups)
        XCTAssertEqual(occasion.groupType, GroupKind.other.rawValue)
    }

    func testNamedGroupsStayOnHomeWithTwoPeople() {
        let occasion = Occasion(name: "Trip", groupType: GroupKind.trip.rawValue)
        occasion.members = [Person(name: "Me"), Person(name: "Alex")]

        XCTAssertFalse(occasion.isOneToOne)
        XCTAssertTrue(occasion.appearsInGroups)
    }

    func testDeletedGroupIsHiddenFromHome() {
        DeletedGroupsStore.resetForTesting()
        let occasion = Occasion(name: "Dallas", groupType: GroupKind.other.rawValue)
        occasion.members = [Person(name: "Me"), Person(name: "dhruv"), Person(name: "suresh")]
        XCTAssertTrue(occasion.appearsInGroups)
        XCTAssertTrue(occasion.shouldAppearInLists)

        occasion.markDeleted()

        XCTAssertTrue(occasion.isDeleted)
        XCTAssertTrue(DeletedGroupsStore.contains(occasion.id))
        XCTAssertFalse(occasion.shouldAppearInLists)

        occasion.isDeleted = false
        XCTAssertTrue(DeletedGroupsStore.contains(occasion.id))
        XCTAssertFalse(occasion.shouldAppearInLists)
        DeletedGroupsStore.resetForTesting()
    }

    func testGoogleOAuthOpensGoogleAuthLogin() {
        let pkce = GoogleOAuth.makePKCE()
        XCTAssertFalse(pkce.verifier.isEmpty)
        XCTAssertFalse(pkce.challenge.isEmpty)
        XCTAssertNotEqual(pkce.verifier, pkce.challenge)

        let url = GoogleOAuth.authorizationURL(
            clientID: "123-abc.apps.googleusercontent.com",
            redirectURI: "com.googleusercontent.apps.123-abc:/oauth2redirect",
            challenge: pkce.challenge,
            loginHint: "pat.lee@gmail.com"
        )
        XCTAssertEqual(url?.host, "accounts.google.com")
        XCTAssertTrue(url?.path.contains("oauth2") == true)
        let query = url?.absoluteString ?? ""
        XCTAssertTrue(query.contains("code_challenge"))
        XCTAssertTrue(query.contains("select_account"))
        XCTAssertTrue(query.contains("openid"))
        XCTAssertTrue(query.contains("pat.lee"))
    }

    func testGoogleOAuthReadsAuthorizationCode() {
        let url = URL(string: "com.pramela.freesplitunlimited:/oauth2redirect?code=abc123&scope=email")!
        XCTAssertEqual(GoogleOAuth.authCode(from: url), "abc123")
        let denied = URL(string: "com.pramela.freesplitunlimited:/oauth2redirect?error=access_denied")!
        XCTAssertNil(GoogleOAuth.authCode(from: denied))
    }
}
