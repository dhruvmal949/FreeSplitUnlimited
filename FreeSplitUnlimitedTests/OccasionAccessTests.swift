//
//  OccasionAccessTests.swift
//  FreeSplitUnlimitedTests
//

import XCTest
@testable import FreeSplitUnlimited

final class OccasionAccessTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DeletedGroupsStore.resetForTesting()
        OccasionAccess.resetForTesting()
    }

    override func tearDown() {
        DeletedGroupsStore.resetForTesting()
        OccasionAccess.resetForTesting()
        super.tearDown()
    }

    func testOwnerSeesEveryGroupTheyCreated() {
        let ownerID = UUID()
        let owner = AccountIdentity(
            accountID: ownerID,
            email: "owner@example.com",
            phone: "5551112222",
            names: ["Pat"]
        )
        let cabin = group(name: "Cabin", owner: ownerID, members: [
            Person(name: "Me"),
            Person(name: "Alex", email: "alex@example.com")
        ])
        let dinner = group(name: "Dinner", owner: ownerID, members: [
            Person(name: "Me"),
            Person(name: "Blair")
        ])

        XCTAssertTrue(OccasionAccess.isVisible(cabin, as: owner))
        XCTAssertTrue(OccasionAccess.isVisible(dinner, as: owner))
    }

    func testParticipantSeesOnlyTheGroupTheyAreIn() {
        let ownerID = UUID()
        let alex = AccountIdentity(
            accountID: UUID(),
            email: "alex@example.com",
            phone: "5553334444",
            names: ["Alex"]
        )
        let cabin = group(name: "Cabin", owner: ownerID, members: [
            Person(name: "Me"),
            Person(name: "Alex", email: "alex@example.com")
        ])
        let secret = group(name: "Secret", owner: ownerID, members: [
            Person(name: "Me"),
            Person(name: "Sam")
        ])

        XCTAssertTrue(OccasionAccess.isVisible(cabin, as: alex))
        XCTAssertFalse(OccasionAccess.isVisible(secret, as: alex))
    }

    func testPlaceholderMeDoesNotRevealOtherPeoplesGroups() {
        let stranger = AccountIdentity(
            accountID: UUID(),
            email: "zoe@example.com",
            phone: "5550001111",
            names: []
        )
        let cabin = group(name: "Cabin", owner: UUID(), members: [
            Person(name: "Me"),
            Person(name: "Alex")
        ])

        XCTAssertFalse(OccasionAccess.canAccess(cabin, as: stranger))
        XCTAssertFalse(OccasionAccess.isVisible(cabin, as: stranger))
    }

    func testShareGrantShowsThatGroupToTheNewUser() {
        let joinerID = UUID()
        let joiner = AccountIdentity(
            accountID: joinerID,
            email: "new@example.com",
            phone: "",
            names: ["New User"]
        )
        let cabin = group(name: "Cabin", owner: UUID(), members: [
            Person(name: "Me"),
            Person(name: "Alex")
        ])
        XCTAssertFalse(OccasionAccess.canAccess(cabin, as: joiner))

        cabin.grantAccess(to: joinerID)
        XCTAssertTrue(OccasionAccess.canAccess(cabin, as: joiner))
    }

    func testNearbySyncSendsAGroupOnlyToAMember() {
        let ownerID = UUID()
        let owner = AccountIdentity(
            accountID: ownerID,
            email: "owner@example.com",
            phone: "5551112222",
            names: ["Pat"]
        )
        let cabin = group(name: "Cabin", owner: ownerID, members: [
            Person(name: "Me"),
            Person(name: "Alex")
        ])

        XCTAssertTrue(OccasionAccess.canSend(cabin, toPeerNamed: "Alex", as: owner))
        XCTAssertFalse(OccasionAccess.canSend(cabin, toPeerNamed: "Zoe", as: owner))
        XCTAssertFalse(OccasionAccess.canSend(cabin, toPeerNamed: "Me", as: owner))
    }

    func testPhoneMatchCountsAsParticipation() {
        let blair = AccountIdentity(
            accountID: UUID(),
            email: "",
            phone: "(555) 333-4444",
            names: ["Blair"]
        )
        let trip = group(name: "Trip", owner: UUID(), members: [
            Person(name: "Me"),
            Person(name: "Blair Lee", phone: "5553334444")
        ])

        XCTAssertTrue(OccasionAccess.canAccess(trip, as: blair))
    }

    private func group(name: String, owner: UUID, members: [Person]) -> Occasion {
        let occasion = Occasion(name: name)
        occasion.ownerAccountID = owner
        occasion.members = members
        return occasion
    }
}
