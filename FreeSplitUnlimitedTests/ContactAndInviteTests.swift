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
        XCTAssertTrue(payloads[0].body.contains("apps.apple.com"))
    }

    func testPayloadsSendsOneEmailPerAddress() {
        let payloads = FriendInvite.payloads(
            for: [
                PickedContact(name: "Alex", email: "alex@example.com"),
                PickedContact(name: "Blair", email: "blair@example.com")
            ],
            splitName: "Safari"
        )
        XCTAssertEqual(payloads.map(\.recipients), [["alex@example.com"], ["blair@example.com"]])
        XCTAssertTrue(payloads[0].body.contains("Email: alex@example.com"))
        XCTAssertTrue(payloads[1].body.contains("Email: blair@example.com"))
        XCTAssertFalse(payloads[0].body.contains("blair@example.com"))
    }

    func testInviteMessageUsesJoinLinkWhenProvided() {
        let join = URL(string: "https://paste.rs/abc123.html")!
        let payloads = FriendInvite.payloads(
            for: [PickedContact(name: "Alex", phone: "5551112222")],
            splitName: "Cabin",
            joinURL: join
        )
        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(payloads[0].body.contains(join.absoluteString))
        XCTAssertTrue(payloads[0].body.contains("Tap this link"))
        XCTAssertFalse(payloads[0].body.contains("apps.apple.com"))
        XCTAssertFalse(payloads[0].body.contains("freesplit://"))
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
        XCTAssertTrue(payloads[0].isPhoneInvite)
        XCTAssertEqual(payloads[1].recipients, ["casey@example.com"])
        XCTAssertFalse(payloads[1].isPhoneInvite)
        XCTAssertTrue(payloads[1].body.contains("Email: casey@example.com"))
        XCTAssertFalse(payloads[0].body.contains("@"))
    }

    func testPayloadsSendsEmailEvenWhenThePersonAlsoHasAPhone() {
        let payloads = FriendInvite.payloads(
            for: [PickedContact(name: "Casey", email: "casey@example.com", phone: "5551112222")],
            splitName: "Trip"
        )
        XCTAssertEqual(payloads.map(\.recipients), [["+15551112222"], ["casey@example.com"]])
        XCTAssertTrue(payloads[1].body.contains("casey@example.com"))
        XCTAssertFalse(payloads[0].body.contains("casey@example.com"))
    }

    func testEmailInviteBodyMentionsAddressAndShortLink() {
        let join = URL(string: "https://paste.rs/abc123.html")!
        let payloads = FriendInvite.payloads(
            for: [PickedContact(name: "Casey", email: "casey@example.com")],
            splitName: "Safari",
            joinURL: join
        )
        XCTAssertEqual(payloads.count, 1)
        XCTAssertFalse(payloads[0].isPhoneInvite)
        XCTAssertTrue(payloads[0].body.contains("Email: casey@example.com"))
        XCTAssertTrue(payloads[0].body.contains(join.absoluteString))
        XCTAssertFalse(payloads[0].body.contains("apps.apple.com"))
        XCTAssertFalse(payloads[0].body.contains("freesplit://"))
    }

    func testMailAndGmailFallbacksStayAvailableTogether() {
        let payload = ComposePayload(
            recipients: ["casey@example.com"],
            body: "I added you to 'Safari' on Free Split.\nEmail: casey@example.com",
            subject: "Join my split on Free Split"
        )
        let urls = FriendInvite.emailFallbackURLs(for: payload)
        XCTAssertEqual(urls.map(\.scheme), ["mailto", "googlegmail"])
        XCTAssertTrue(urls.contains { $0.absoluteString.contains("casey@example.com") })
    }

    func testMailURLIncludesGmailAddress() {
        let url = FriendInvite.mailURL(
            to: "name@gmail.com",
            subject: "Join my split on Free Split",
            body: "I added you to 'Trip' on Free Split."
        )
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "mailto")
        XCTAssertTrue(url?.absoluteString.contains("name@gmail.com") == true)
        XCTAssertTrue(url?.absoluteString.contains("subject=") == true)
    }

    func testGmailFallbackURLIncludesRecipient() {
        let url = FriendInvite.gmailURL(
            to: ["name@gmail.com"],
            subject: "Join my split on Free Split",
            body: "I added you to 'Trip' on Free Split."
        )
        XCTAssertEqual(url?.scheme, "googlegmail")
        XCTAssertTrue(url?.absoluteString.contains("name@gmail.com") == true)
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

    func testMultiplePhoneNumbersRequireAChoice() {
        let contact = PickedContact(
            name: "Alex",
            phone: "",
            phones: ["(555) 111-2222", "555-333-4444"]
        )
        XCTAssertTrue(contact.needsContactChoice)
        XCTAssertEqual(contact.uniquePhones.count, 2)
        let chosen = contact.selectingPhone("5553334444")
        XCTAssertEqual(ContactUniqueness.phoneKey(chosen.phone), "5553334444")
        XCTAssertEqual(chosen.phones, [chosen.phone])
        XCTAssertFalse(chosen.needsContactChoice)
    }

    func testSelectingAPhoneKeepsASingleEmail() {
        let contact = PickedContact(
            name: "Blair",
            email: "blair@example.com",
            phones: ["5551112222", "5553334444"]
        )
        let chosen = contact.selectingPhone("5551112222")
        XCTAssertEqual(chosen.email, "blair@example.com")
        XCTAssertEqual(ContactUniqueness.phoneKey(chosen.phone), "5551112222")
    }

    func testEnteredEmailClearsSavedPhoneFromContactCard() {
        var contact = PickedContact(
            name: "Alex",
            email: "",
            phone: "(555) 111-2222",
            phones: ["(555) 111-2222"]
        )
        contact.setEnteredContact(email: "alex@gmail.com", phone: "")
        XCTAssertEqual(contact.email, "alex@gmail.com")
        XCTAssertEqual(contact.phone, "")
        XCTAssertEqual(contact.phones, [])
        let resolved = contact.resolvedContact()
        XCTAssertEqual(resolved?.email, "alex@gmail.com")
        XCTAssertNil(ContactUniqueness.phoneKey(resolved?.phone ?? ""))
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

final class FriendContactInputTests: XCTestCase {
    func testLettersAreNotWipedAsPhoneFormatting() {
        XCTAssertFalse(looksLikePhoneTyping("pat"))
        XCTAssertFalse(looksLikePhoneTyping("pat@example.com"))
        XCTAssertTrue(looksLikePhoneTyping("555"))
        XCTAssertTrue(looksLikePhoneTyping("(555) 123"))
    }

    func testGmailValidatesLikeOtherEmailScreens() {
        var entry = ContactEntryState()
        entry.kind = .email
        entry.email = "name@gmail.com"
        XCTAssertTrue(isValidEmail(entry.email))
        XCTAssertTrue(entry.isValid)
        XCTAssertNil(entry.hint)

        entry.email = "name@gmail"
        XCTAssertFalse(entry.isValid)
        XCTAssertEqual(entry.hint, "Enter a valid email address.")
    }

    func testSavedEmailReplacesTypedLetters() {
        let change = resolvedEmailFieldChange(
            current: "pra",
            replacement: "pramela@gmail.com",
            range: NSRange(location: 3, length: 0)
        )
        XCTAssertEqual(change.text, "pramela@gmail.com")
        XCTAssertEqual(change.cursorUTF16Offset, "pramela@gmail.com".utf16.count)
    }

    func testDeletingALetterKeepsCursorInPlace() {
        let change = resolvedEmailFieldChange(
            current: "name@gmail.com",
            replacement: "",
            range: NSRange(location: 2, length: 1)
        )
        XCTAssertEqual(change.text, "nae@gmail.com")
        XCTAssertEqual(change.cursorUTF16Offset, 2)
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
