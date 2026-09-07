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

    func testPairOccasionIDsAreSymmetric() {
        let aliceBob = FriendPairing.occasionID("Alice", "Bob")
        let bobAlice = FriendPairing.occasionID(" Bob ", "alice")
        XCTAssertEqual(aliceBob, bobAlice)
        XCTAssertEqual(
            FriendPairing.personID("Alice", "Bob", person: "Alice"),
            FriendPairing.personID("bob", "ALICE", person: " alice ")
        )
    }

    func testIncomingOneToOneRewritesMeToPeerName() {
        let backup = BackupOccasion(
            id: UUID(),
            name: "Alice",
            note: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            isDeleted: false,
            groupType: SplitKind.oneToOne,
            members: [
                BackupPerson(id: UUID(), name: "Me", email: "", phone: ""),
                BackupPerson(id: UUID(), name: "Alice", email: "", phone: "")
            ],
            expenses: []
        )
        let prepared = FriendPairing.prepareIncoming(
            backup,
            peerName: "Bob",
            selfNames: ["Me", "Alice"],
            localOccasions: []
        )
        XCTAssertEqual(prepared.name, "Bob")
        XCTAssertTrue(prepared.members.contains(where: { $0.name == "Bob" }))
        XCTAssertTrue(prepared.members.contains(where: { $0.name == "Alice" }))
        XCTAssertFalse(prepared.members.contains(where: { $0.name == "Me" }))
    }

    func testIncomingOneToOneMergesIntoLocalSplitWithTheSameFriend() {
        let localID = UUID()
        let meID = UUID()
        let friendID = UUID()
        let local = Occasion(name: "Bob", id: localID, groupType: SplitKind.oneToOne)
        local.members = [Person(name: "Me", id: meID), Person(name: "Bob", id: friendID)]

        let remoteExpenseID = UUID()
        let remoteMe = UUID()
        let remoteAlice = UUID()
        let backup = BackupOccasion(
            id: UUID(),
            name: "Alice",
            note: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            isDeleted: false,
            groupType: SplitKind.oneToOne,
            members: [
                BackupPerson(id: remoteMe, name: "Me", email: "", phone: ""),
                BackupPerson(id: remoteAlice, name: "Alice", email: "", phone: "")
            ],
            expenses: [
                BackupExpense(
                    id: remoteExpenseID,
                    title: "Coffee",
                    amount: "6",
                    date: Date(timeIntervalSince1970: 2),
                    splitMethodRaw: SplitMethod.equal.rawValue,
                    paidByID: remoteMe,
                    participantIDs: [remoteMe, remoteAlice],
                    shares: []
                )
            ]
        )
        let prepared = FriendPairing.prepareIncoming(
            backup,
            peerName: "Bob",
            selfNames: ["Me", "Alice"],
            localOccasions: [local]
        )
        XCTAssertEqual(prepared.id, localID)
        XCTAssertEqual(prepared.expenses.count, 1)
        XCTAssertEqual(prepared.expenses.first?.id, remoteExpenseID)
        XCTAssertEqual(prepared.expenses.first?.paidByID, friendID)
        XCTAssertEqual(Set(prepared.expenses.first?.participantIDs ?? []), Set([meID, friendID]))
    }
}
