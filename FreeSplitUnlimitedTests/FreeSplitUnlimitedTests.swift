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

    func testFriendNetAcrossAGroupMatchesWhoOwesWhom() throws {
        let me = Person(name: "Me")
        let alex = Person(name: "Alex")
        let occasion = Occasion(name: "Cabin")
        occasion.members = [me, alex]
        occasion.expenses = [
            Expense(
                title: "Dinner",
                amount: 40,
                splitMethod: .equal,
                paidBy: me,
                participants: [me, alex]
            )
        ]

        XCTAssertEqual(BalanceCalculator.net(withFriend: "Alex", in: occasion), 20)
        XCTAssertEqual(
            BalanceCalculator.net(withFriend: "Alex", in: occasion, myNames: ["Me", "Dhruv"]),
            20
        )
        let summary = BalanceCalculator.friendSummaries(from: [occasion]).first { $0.name == "Alex" }
        XCTAssertEqual(summary?.net, 20)
    }

    func testFriendSummaryAddsWhatTheyOweInEachGroup() throws {
        let dinnerMe = Person(name: "Me")
        let dinnerAlex = Person(name: "Alex")
        let dinner = Occasion(name: "Ramp Reality")
        dinner.members = [dinnerMe, dinnerAlex]
        dinner.expenses = [
            Expense(
                title: "Taxi",
                amount: 40,
                splitMethod: .equal,
                paidBy: dinnerMe,
                participants: [dinnerMe, dinnerAlex]
            )
        ]

        let partyMe = Person(name: "Me")
        let partyAlex = Person(name: "Alex")
        let party = Occasion(name: "New Year 2021")
        party.members = [partyMe, partyAlex]
        party.expenses = [
            Expense(
                title: "Snacks",
                amount: 16,
                splitMethod: .equal,
                paidBy: partyAlex,
                participants: [partyMe, partyAlex]
            )
        ]

        XCTAssertEqual(BalanceCalculator.net(withFriend: "Alex", in: dinner, myNames: ["Me", "Pat"]), 20)
        XCTAssertEqual(BalanceCalculator.net(withFriend: "Alex", in: party, myNames: ["Me", "Pat"]), -8)
        let summary = BalanceCalculator.friendSummaries(from: [dinner, party], myNames: ["Me", "Pat"]).first { $0.name == "Alex" }
        XCTAssertEqual(summary?.net, 12)
    }

    func testRecordingAPaymentSettlesWhatYouOweAFriend() throws {
        let me = Person(name: "Me")
        let alex = Person(name: "Alex")
        let occasion = Occasion(name: "Colorado")
        occasion.members = [me, alex]
        occasion.expenses = [
            Expense(
                title: "Cabin",
                amount: 40,
                splitMethod: .equal,
                paidBy: alex,
                participants: [me, alex]
            )
        ]

        XCTAssertEqual(BalanceCalculator.net(withFriend: "Alex", in: occasion), -20)
        BalanceCalculator.recordFriendPayment(
            amount: 20,
            friendPaidYou: false,
            friendName: "Alex",
            occasions: [occasion],
            note: "Venmo"
        )
        XCTAssertEqual(BalanceCalculator.net(withFriend: "Alex", in: occasion), 0)
        XCTAssertEqual(occasion.expenses.last?.note, "Venmo")
        let settlement = BalanceCalculator.activity(from: [occasion]).first {
            $0.title.contains("settled")
        }
        XCTAssertEqual(settlement?.title.contains("Alex"), true)
        XCTAssertEqual(settlement?.subtitle.contains("Venmo"), true)
    }

    func testRecordingAPaymentSettlesWhatAFriendOwesYou() throws {
        let me = Person(name: "Me")
        let alex = Person(name: "Alex")
        let occasion = Occasion(name: "Safari")
        occasion.members = [me, alex]
        occasion.expenses = [
            Expense(
                title: "Tickets",
                amount: 40,
                splitMethod: .equal,
                paidBy: me,
                participants: [me, alex]
            )
        ]

        XCTAssertEqual(BalanceCalculator.net(withFriend: "Alex", in: occasion), 20)
        BalanceCalculator.recordFriendPayment(
            amount: 20,
            friendPaidYou: true,
            friendName: "Alex",
            occasions: [occasion]
        )
        XCTAssertEqual(BalanceCalculator.net(withFriend: "Alex", in: occasion), 0)
    }

    func testGroupSettlePaymentRecordsFromDebtorToCreditor() throws {
        let me = Person(name: "Me")
        let ramesh = Person(name: "Ramesh")
        let occasion = Occasion(name: "KPMC Dining")
        occasion.members = [me, ramesh]
        occasion.expenses = [
            Expense(
                title: "Dinner",
                amount: 40,
                splitMethod: .equal,
                paidBy: ramesh,
                participants: [me, ramesh]
            )
        ]

        XCTAssertEqual(BalanceCalculator.net(withFriend: "Ramesh", in: occasion), -20)
        let payment = BalanceCalculator.recordDirectedPayment(
            amount: 20,
            payerName: "Me",
            receiverName: "Ramesh",
            in: occasion,
            note: "Cash"
        )
        XCTAssertEqual(payment?.note, "Cash")
        XCTAssertEqual(BalanceCalculator.net(withFriend: "Ramesh", in: occasion), 0)
    }

    func testTotalSpentIgnoresSettlementPayments() {
        let me = Person(name: "Me")
        let praveen = Person(name: "Praveen")
        let occasion = Occasion(name: "Trip")
        occasion.members = [me, praveen]
        occasion.expenses = [
            Expense(
                title: "Dinner",
                amount: 200,
                splitMethod: .equal,
                paidBy: me,
                participants: [me, praveen]
            )
        ]
        XCTAssertEqual(occasion.totalSpent, 200)

        BalanceCalculator.recordDirectedPayment(
            amount: 50,
            payerName: "Praveen",
            receiverName: "Me",
            in: occasion
        )
        XCTAssertEqual(occasion.totalSpent, 200)
        XCTAssertEqual(BalanceCalculator.net(withFriend: "Praveen", in: occasion), 50)
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

    func testJoinPageOpensFreeSplitDeepLink() {
        let html = JoinPage.html(payloadID: "abc123", groupName: "Cabin")
        XCTAssertTrue(html.contains("href=\"freesplit://p/abc123\""))
        XCTAssertTrue(html.contains("abc123"))
        XCTAssertTrue(html.contains("Cabin"))
        XCTAssertTrue(html.contains("apps.apple.com"))
        XCTAssertTrue(html.contains("og:title\" content=\"Join Cabin on Free Split\""))
        XCTAssertTrue(html.contains("og:site_name\" content=\"Free Split\""))
        XCTAssertFalse(html.contains("location.href = store"))
        XCTAssertFalse(html.contains("preventDefault"))
        XCTAssertFalse(html.contains("Rocket Powered Pastebin"))
        XCTAssertFalse(html.contains("paste.rs"))
    }

    func testJoinMarkdownRendersOpenAndStoreLinks() {
        let markdown = JoinPage.markdown(payloadID: "abc123", groupName: "Safari")
        XCTAssertTrue(markdown.contains("freesplit://p/abc123"))
        XCTAssertTrue(markdown.contains("Join Safari on Free Split"))
        XCTAssertTrue(markdown.contains("apps.apple.com"))
        XCTAssertFalse(markdown.contains("<script"))
    }

    func testJoinPreviewTitleUsesSplitName() {
        XCTAssertEqual(JoinPage.previewTitle(groupName: "Cabin"), "Join Cabin on Free Split")
        XCTAssertEqual(JoinPage.previewTitle(groupName: "  "), "Join a split on Free Split")
    }

    func testPublishedJoinURLUsesMarkdownNotHighlightedHTML() throws {
        let url = try ShareLink.publishedPageURL(pageID: "gDlm0")
        XCTAssertEqual(url.pathExtension, "md")
        XCTAssertFalse(url.absoluteString.hasSuffix(".html"))
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

    func testDeletedGroupIDsAreStoredInBackupSnapshot() throws {
        DeletedGroupsStore.resetForTesting()
        let id = UUID()
        DeletedGroupsStore.remember(id, notify: false)
        let snapshot = SplitsBackupSnapshot(savedAt: .now, occasions: [], deletedIDs: Array(DeletedGroupsStore.ids()))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SplitsBackupSnapshot.self, from: data)
        XCTAssertTrue(decoded.deletedIDs.contains(id))
        DeletedGroupsStore.resetForTesting()
    }

    func testDeletedFriendSplitIsHiddenFromFriends() {
        DeletedGroupsStore.resetForTesting()
        let occasion = Occasion(name: "Alex", groupType: SplitKind.oneToOne)
        occasion.members = [Person(name: "Me"), Person(name: "Alex")]
        XCTAssertFalse(occasion.appearsInGroups)
        XCTAssertTrue(occasion.shouldAppearInLists)

        occasion.markDeleted()

        XCTAssertTrue(occasion.isDeleted)
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

    func testPaidNotificationsStayWithRecentUntilThereAreMoreThanFifteen() {
        let events = activityEvents(paid: 10, created: 4)
        let feed = NotificationFeed.sections(from: events)
        XCTAssertEqual(feed.recent.count, 14)
        XCTAssertTrue(feed.paid.isEmpty)
        XCTAssertFalse(feed.showsPaidStack)
    }

    func testPaidNotificationsBeyondFifteenMoveToPaidStack() {
        let events = activityEvents(paid: 18, created: 2)
        let feed = NotificationFeed.sections(from: events)
        XCTAssertEqual(feed.recent.count, 17)
        XCTAssertEqual(feed.paid.count, 3)
        XCTAssertTrue(feed.showsPaidStack)
        XCTAssertTrue(feed.paid.allSatisfy { $0.kind == .amountPaid })
        XCTAssertEqual(feed.recent.filter { $0.kind == .splitCreated }.count, 2)
    }

    func testDeletedNotificationsAreHiddenFromFeed() {
        DeletedNotificationsStore.resetForTesting()
        let events = activityEvents(paid: 3, created: 1)
        DeletedNotificationsStore.remember(events[0].id)
        let feed = NotificationFeed.sections(from: events, hiddenIDs: DeletedNotificationsStore.ids())
        XCTAssertEqual(feed.recent.count, 3)
        XCTAssertFalse(feed.recent.contains { $0.id == events[0].id })
        DeletedNotificationsStore.resetForTesting()
    }

    func testSettledFriendsStayWithRecentUntilThereAreMoreThanFifteen() {
        let friends = friendSummaries(outstanding: 10, settled: 4)
        let feed = FriendFeed.sections(from: friends)
        XCTAssertEqual(feed.recent.count, 14)
        XCTAssertTrue(feed.paid.isEmpty)
        XCTAssertFalse(feed.showsPaidStack)
    }

    func testSettledFriendsBeyondFifteenMoveToPaidStack() {
        let friends = friendSummaries(outstanding: 2, settled: 18)
        let feed = FriendFeed.sections(from: friends)
        XCTAssertEqual(feed.recent.count, 17)
        XCTAssertEqual(feed.paid.count, 3)
        XCTAssertTrue(feed.showsPaidStack)
        XCTAssertTrue(feed.paid.allSatisfy { $0.net == 0 })
        XCTAssertEqual(feed.recent.filter { $0.net != 0 }.count, 2)
    }

    func testExistingOneToOneIsReusedByFriendName() {
        let occasion = Occasion(name: "Alex", groupType: SplitKind.oneToOne)
        occasion.members = [Person(name: "Me"), Person(name: "Alex")]
        let found = FriendPairing.existingOccasion(
            friendName: "alex",
            selfNames: ["Me", "Pat"],
            in: [occasion]
        )
        XCTAssertEqual(found?.id, occasion.id)
    }

    func testEmptyOneToOneDisplayNameIsUntitledSplit() {
        let occasion = Occasion(name: "  ", groupType: SplitKind.oneToOne)
        XCTAssertEqual(occasion.displayName, "Untitled split")
        XCTAssertEqual(occasion.kindTitle, "Split")
    }

    private func activityEvents(paid: Int, created: Int) -> [ActivityEvent] {
        let occasionID = UUID()
        var items: [ActivityEvent] = []
        for index in 0..<paid {
            items.append(
                ActivityEvent(
                    id: "paid-\(index)",
                    date: Date().addingTimeInterval(TimeInterval(-index)),
                    kind: .amountPaid,
                    title: "Paid \(index)",
                    subtitle: "Dinner",
                    occasionID: occasionID
                )
            )
        }
        for index in 0..<created {
            items.append(
                ActivityEvent(
                    id: "created-\(index)",
                    date: Date().addingTimeInterval(TimeInterval(-(paid + index))),
                    kind: .splitCreated,
                    title: "Split created",
                    subtitle: "Trip",
                    occasionID: occasionID
                )
            )
        }
        return items.sorted { $0.date > $1.date }
    }

    private func friendSummaries(outstanding: Int, settled: Int) -> [FriendSummary] {
        var items: [FriendSummary] = []
        for index in 0..<settled {
            items.append(
                FriendSummary(
                    id: "paid-\(index)",
                    name: "Paid \(index)",
                    net: 0,
                    occasionIDs: [],
                    occasionNames: ["Trip"]
                )
            )
        }
        for index in 0..<outstanding {
            items.append(
                FriendSummary(
                    id: "owe-\(index)",
                    name: "Owe \(index)",
                    net: Decimal(index + 1),
                    occasionIDs: [],
                    occasionNames: ["Trip"]
                )
            )
        }
        return items
    }
}
