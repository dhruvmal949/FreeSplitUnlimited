//
//  ContactAndInviteTests.swift
//  FreeSplitUnlimitedTests
//

import XCTest
@testable import FreeSplitUnlimited

final class ContactUniquenessTests: XCTestCase {
    func testSamePhoneIsDetectedAcrossFormats() {
        let suresh = PickedContact(
            id: "suresh",
            name: "Suresh",
            phone: "(555) 123-4567"
        )
        let duplicate = PickedContact(
            id: "other",
            name: "Alex",
            phone: "5551234567"
        )

        XCTAssertEqual(
            ContactUniqueness.ownerName(usingPhone: duplicate.phone, in: [suresh]),
            "Suresh"
        )
        XCTAssertEqual(
            ContactUniqueness.duplicateMessage(for: duplicate, in: [suresh]),
            "Suresh already uses this phone number. Enter a different number."
        )
    }

    func testSameEmailIsDetectedCaseInsensitively() {
        let pat = PickedContact(id: "pat", name: "Pat", email: "Pat@Example.com")
        let duplicate = PickedContact(id: "blair", name: "Blair", email: "pat@example.com")

        XCTAssertEqual(
            ContactUniqueness.ownerName(usingEmail: duplicate.email, in: [pat]),
            "Pat"
        )
        XCTAssertEqual(
            ContactUniqueness.duplicateMessage(for: duplicate, in: [pat]),
            "Pat already uses this email. Enter a different email."
        )
    }

    func testPersonIsNotFlaggedAsDuplicateOfThemselves() {
        let alex = PickedContact(id: "alex", name: "Alex", phone: "5551112222")
        XCTAssertNil(ContactUniqueness.duplicateMessage(for: alex, in: [alex]))
        XCTAssertNil(ContactUniqueness.ownerName(usingPhone: alex.phone, in: [alex], excludingID: "alex"))
    }

    func testDifferentNumbersAreAllowed() {
        let alex = PickedContact(id: "alex", name: "Alex", phone: "5551112222")
        let blair = PickedContact(id: "blair", name: "Blair", phone: "5553334444")
        XCTAssertNil(ContactUniqueness.duplicateMessage(for: blair, in: [alex]))
    }

    func testIncompletePhoneIsNotTreatedAsDuplicate() {
        let alex = PickedContact(id: "alex", name: "Alex", phone: "555")
        let blair = PickedContact(id: "blair", name: "Blair", phone: "555")
        XCTAssertNil(ContactUniqueness.phoneKey("555"))
        XCTAssertNil(ContactUniqueness.duplicateMessage(for: blair, in: [alex]))
    }
}

@MainActor
final class FriendInviteTests: XCTestCase {
    func testNeedsInviteRequiresUsableNameAndContact() {
        XCTAssertFalse(FriendInvite.needsInvite(PickedContact(name: "Me", phone: "5551112222", isMe: true)))
        XCTAssertFalse(FriendInvite.needsInvite(PickedContact(name: "Pat Lee", phone: "5551112222", isMe: true)))
        XCTAssertFalse(FriendInvite.needsInvite(PickedContact(name: "Alex")))
        XCTAssertFalse(FriendInvite.needsInvite(PickedContact(name: "Alex", phone: "5551112222", didInvite: true)))
        XCTAssertTrue(FriendInvite.needsInvite(PickedContact(name: "Alex", phone: "5551112222")))
        XCTAssertTrue(FriendInvite.needsInvite(PickedContact(name: "Blair", email: "blair@example.com")))
    }

    func testPayloadsPutsEveryPhoneOnOneText() {
        let alexID = UUID()
        let blairID = UUID()
        let payloads = FriendInvite.payloads(
            for: [
                PickedContact(name: "Alex", phone: "(555) 111-2222", personID: alexID),
                PickedContact(name: "Blair", phone: "5553334444", personID: blairID),
                PickedContact(name: "Me", isMe: true)
            ],
            splitName: "Cabin"
        )

        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(payloads[0].isPhoneInvite)
        XCTAssertEqual(payloads[0].recipients, ["+15551112222", "+15553334444"])
        XCTAssertEqual(payloads[0].personIDs, [alexID, blairID])
        XCTAssertTrue(payloads[0].body.contains("Cabin"))
    }

    func testPayloadsIncludesEmailOnlyPeopleSeparately() {
        let payloads = FriendInvite.payloads(
            for: [
                PickedContact(name: "Alex", phone: "5551112222"),
                PickedContact(name: "Casey", email: "casey@example.com")
            ],
            splitName: "Trip"
        )

        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0].recipients, ["+15551112222"])
        XCTAssertEqual(payloads[1].recipients, ["casey@example.com"])
        XCTAssertFalse(payloads[1].isPhoneInvite)
    }

    func testAlreadyInvitedPeopleAreSkipped() {
        let payloads = FriendInvite.payloads(
            for: [
                PickedContact(name: "Alex", phone: "5551112222", didInvite: true),
                PickedContact(name: "Blair", phone: "5553334444")
            ],
            splitName: "Dinner"
        )

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0].recipients, ["+15553334444"])
    }

    func testPersonContactInfoAndInviteMapping() {
        let person = Person(name: "Suresh", email: "", phone: "(555) 123-4567")
        XCTAssertTrue(person.hasContactInfo)
        let picked = person.asPickedContact
        XCTAssertEqual(picked.personID, person.id)
        XCTAssertEqual(picked.phone, person.phone)
        XCTAssertTrue(picked.hasUsableContactInfo)
        XCTAssertTrue(FriendInvite.needsInvite(picked))
    }

    func testSavedPhoneSkipsAddContactScreen() {
        let fromContacts = PickedContact(
            name: "Suresh",
            phone: "",
            phones: ["(555) 123-4567", "555-000-1111"]
        )
        let resolved = fromContacts.resolvedContact()
        XCTAssertNotNil(resolved)
        XCTAssertEqual(ContactUniqueness.phoneKey(resolved?.phone ?? ""), "5551234567")
        XCTAssertTrue(fromContacts.hasUsableContactInfo)
        XCTAssertNil(PickedContact(name: "New Person").resolvedContact())
        XCTAssertFalse(PickedContact(name: "New Person").hasUsableContactInfo)
    }

    func testEnteredPhoneStaysOnTheContactCard() {
        var contact = PickedContact(name: "Suresh")
        contact.setEnteredContact(email: "", phone: formattedUSPhone("5551234567"))
        XCTAssertEqual(ContactUniqueness.phoneKey(contact.phone), "5551234567")
        XCTAssertTrue(contact.phones.contains(contact.phone))
        XCTAssertTrue(contact.contactSummary.contains("555"))
        XCTAssertNotNil(contact.resolvedContact())
    }
}

final class KnownFriendsStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KnownFriendsStore.resetForTesting()
    }

    override func tearDown() {
        KnownFriendsStore.resetForTesting()
        super.tearDown()
    }

    func testSavedPhoneSurvivesBeingRemovedFromASplit() {
        let suresh = Person(name: "Suresh", email: "", phone: "(555) 123-4567")
        KnownFriendsStore.remember([suresh])

        XCTAssertEqual(
            ContactUniqueness.phoneKey(KnownFriendsStore.contact(named: "suresh")?.phone ?? ""),
            "5551234567"
        )

        KnownFriendsStore.remember([Person]())

        let saved = KnownFriendsStore.contact(named: "Suresh")
        XCTAssertNotNil(saved)
        XCTAssertTrue(saved?.hasUsableContactInfo == true)
        XCTAssertEqual(ContactUniqueness.phoneKey(saved?.phone ?? ""), "5551234567")
    }

    func testRememberedPickedContactCanBeAddedWithoutAskingAgain() {
        KnownFriendsStore.remember([
            PickedContact(name: "Blair", phone: "5553334444")
        ])
        let saved = KnownFriendsStore.contact(named: "Blair")
        XCTAssertEqual(ContactUniqueness.phoneKey(saved?.phone ?? ""), "5553334444")
        XCTAssertNotNil(saved?.resolvedContact())
    }
}

final class HiddenSelfMemberTests: XCTestCase {
    func testMeIsHiddenFromGroupPeopleAndStillRecognizedAsSelf() {
        let me = FriendDraft(contact: ContactDirectory.me())
        let friend = FriendDraft(name: "Alex", phone: "5551112222")

        XCTAssertTrue(me.isSelf)
        XCTAssertFalse(friend.isSelf)
        XCTAssertTrue(FriendPairing.isPlaceholderSelf("Me"))
        XCTAssertTrue(FriendPairing.isUsableName("Alex"))
    }
}
