import Foundation
import Testing
@testable import RecipeManager

private final class HouseholdFixtureToken {}

private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let url = try #require(Bundle(for: HouseholdFixtureToken.self).url(forResource: name, withExtension: "json"))
    return try APIClient.decoder.decode(T.self, from: Data(contentsOf: url))
}

private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: HouseholdFixtureToken.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

// MARK: Households and the shared shopping list (real server responses)

struct HouseholdFixtureTests {
    @Test func createdHousehold() throws {
        let response: HouseholdResponse = try fixture("household_created")
        let h = try #require(response.household)
        #expect(h.name == "Home")
        #expect(h.inviteCode == "V2JS-B28Z")
        #expect(h.isOwner)
        #expect(h.members.map(\.username) == ["sam"])
    }

    @Test func joinedHousehold() throws {
        let h = try #require(try fixture("household_joined", as: HouseholdResponse.self).household)
        #expect(!h.isOwner)
        #expect(h.members.map(\.id) == [1, 2])
    }

    @Test func noHousehold() throws {
        let none = try APIClient.decoder.decode(HouseholdResponse.self, from: Data(#"{"household": null}"#.utf8))
        #expect(none.household == nil)
        // An odd household (missing fields) still reads.
        let odd = try APIClient.decoder.decode(HouseholdResponse.self, from: Data(#"{"household": {"id": 3}}"#.utf8))
        #expect(odd.household?.members == [])
        #expect(odd.household?.isOwner == false)
    }

    @Test func inviteCodesAreTidied() {
        #expect(Household.normaliseCode("v2js b28z") == "V2JS-B28Z")
        #expect(Household.normaliseCode(" V2JS-B28Z ") == "V2JS-B28Z")
        #expect(Household.normaliseCode("v2jsb28z") == "V2JS-B28Z")
        #expect(Household.normaliseCode("v2 js-b2 8z") == "V2JS-B28Z")
        #expect(Household.normaliseCode("abc") == "ABC")
        #expect(Household.normaliseCode("  - ") == "")
    }

    @Test func sharedShoppingListSaysWhoAddedWhat() throws {
        let list: ShoppingList = try fixture("shopping_household")
        #expect(list.version == "29dcdf555980a605")
        #expect(list.items.count == 3)
        let milk = try #require(list.items.first { $0.name == "1 litre milk" })
        #expect(milk.mine == false)
        #expect(milk.addedBy?.username == "alex")
        #expect(milk.addedByLine == "Added by alex")
        #expect(milk.createdAt != nil)
        let bread = try #require(list.items.first { $0.name == "Bread" })
        #expect(bread.mine == true)
        #expect(bread.addedByLine == nil)
    }

    @Test func olderShoppingListsStillRead() throws {
        // The older fixture has no version, added_by or mine: all items are yours, and nothing says who added them.
        let list: ShoppingList = try fixture("shopping")
        #expect(list.version == nil)
        #expect(list.items.allSatisfy { $0.addedByLine == nil })
    }

    @Test func versionReadsAndSurvivesSaving() throws {
        let v: ShoppingVersion = try fixture("shopping_version")
        #expect(v.version == "29dcdf555980a605")
        #expect(try APIClient.decoder.decode(ShoppingVersion.self, from: Data("{}".utf8)).version == nil)
        // The list is saved for offline use with its version, so a relaunch doesn't reload needlessly.
        let list: ShoppingList = try fixture("shopping_household")
        let again = try APIClient.decoder.decode(ShoppingList.self, from: APIClient.encoder.encode(list))
        #expect(again.version == list.version)
        #expect(again.items.first?.addedBy?.username == "alex")
    }
}

// MARK: The shopping version poll

struct ShoppingPollTests {
    @Test func asksOnlyWhenNothingOfOursIsOnTheWay() {
        #expect(ShoppingPoll.shouldAsk(.init()))
        #expect(!ShoppingPoll.shouldAsk(.init(offline: true)))
        #expect(!ShoppingPoll.shouldAsk(.init(unsupported: true)))
        #expect(!ShoppingPoll.shouldAsk(.init(hasList: false)))
        #expect(!ShoppingPoll.shouldAsk(.init(pendingChanges: true)))
        #expect(!ShoppingPoll.shouldAsk(.init(busy: true)))
        #expect(!ShoppingPoll.shouldAsk(.init(undoOffered: true)))
    }

    @Test func reloadsOnlyWhenTheVersionMoved() {
        #expect(!ShoppingPoll.needsReload(have: "a", server: "a"))
        #expect(ShoppingPoll.needsReload(have: "a", server: "b"))
        #expect(ShoppingPoll.needsReload(have: nil, server: "b"))      // saved before the update
        #expect(!ShoppingPoll.needsReload(have: "a", server: nil))     // an older server
        #expect(!ShoppingPoll.needsReload(have: nil, server: ""))
    }

    @Test func shoppingChangesInTheOutboxHoldThePollBack() {
        #expect(OutboxOp.addShoppingItem(name: "milk", checked: false).isShopping)
        #expect(OutboxOp.setShoppingChecked(itemID: 1, checked: true).isShopping)
        #expect(OutboxOp.deleteShoppingItem(itemID: 1).isShopping)
        #expect(!OutboxOp.favorite(recipeID: 1, wanted: true).isShopping)
        #expect(!OutboxOp.madeIt(recipeID: 1).isShopping)
    }
}

// MARK: Collections: soft delete

struct CollectionDeleteTests {
    @Test func newerServersCanRestore() throws {
        let deleted = CollectionDeleted.read(try fixtureData("collection_deleted"))
        #expect(deleted.ok == true)
        #expect(deleted.canRestore)
        let restored: CollectionDetail = try fixture("collection_restored")
        #expect(restored.name == "Weeknights")
    }

    @Test func olderServersNeverFailAndOfferNoUndo() {
        #expect(!CollectionDeleted.read(Data()).canRestore)                       // 204, no body
        #expect(!CollectionDeleted.read(Data(#"{"ok": true}"#.utf8)).canRestore)
        #expect(!CollectionDeleted.read(Data("not json".utf8)).canRestore)
        #expect(!CollectionDeleted.read(Data(#"{"restorable_until": 5}"#.utf8)).canRestore)
    }
}

// MARK: Cook history

struct CookLogFixtureTests {
    @Test func madeWithoutAnything() throws {
        let made: MadeResult = try fixture("cook_made")
        #expect(made.madeCount == 1)
        let entry = try #require(made.entry)
        #expect(entry.note == "")
        #expect(!entry.hasPhoto)
        #expect(entry.recipe?.title == "Lemon risotto")
        #expect(entry.cookedAt != nil)
    }

    @Test func madeWithNoteAndPhoto() throws {
        let made: MadeResult = try fixture("cook_made_photo")
        #expect(made.madeCount == 2)
        #expect(made.entry?.note == "Extra zest, less stock.")
        #expect(made.entry?.photoUrl == "/admin/uploads/cook_af09efc98c4c.jpg")
    }

    @Test func olderMadeAnswerHasNoEntry() throws {
        let made = try APIClient.decoder.decode(MadeResult.self, from: Data(#"{"made_count": 4}"#.utf8))
        #expect(made.madeCount == 4)
        #expect(made.entry == nil)
    }

    @Test func pageAndCursor() throws {
        let page: CookLogPage = try fixture("cook_log_page")
        #expect(page.entries.map(\.id) == [2])
        #expect(page.nextBefore == 2)
        let last = try APIClient.decoder.decode(CookLogPage.self, from: Data(#"{"entries": [{"id": 1}, {"bad": true}], "next_before": null}"#.utf8))
        #expect(last.entries.map(\.id) == [1])   // the unreadable one is skipped, not the page
        #expect(last.nextBefore == nil)
    }

    @Test func patchedEntryAndRecipeHistory() throws {
        let entry: CookEntry = try fixture("cook_entry_patched")
        #expect(entry.note == "Extra zest, less stock. Great.")
        let history: ItemList<CookEntry> = try fixture("cook_history")
        #expect(history.items.map(\.id) == [2, 1])
        #expect(history.items.filter(\.hasPhoto).count == 1)
    }

    @Test func emptyPhotoMeansNone() throws {
        let entry = try APIClient.decoder.decode(CookEntry.self, from: Data(#"{"id": 9, "photo_url": ""}"#.utf8))
        #expect(!entry.hasPhoto)
    }

    @Test func queuedMadeItFromBeforeTheUpdateStillReads() throws {
        // An Outbox saved by build 12 (no note or photo) must still replay after updating.
        let old = Data(#"[{"madeIt":{"recipeID":3}}]"#.utf8)
        let ops = try JSONDecoder().decode([OutboxOp].self, from: old)
        #expect(ops == [.madeIt(recipeID: 3, note: nil, photo: nil)])
        let new = OutboxOp.madeIt(recipeID: 3, note: "Good", photo: "a.jpg")
        #expect(try JSONDecoder().decode(OutboxOp.self, from: JSONEncoder().encode(new)) == new)
        #expect(new.photoName == "a.jpg")
    }

    @Test func keptPhotosRoundTripAndGo() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])
        let name = try #require(Outbox.keepPhoto(jpeg))
        #expect(Outbox.keptPhoto(name) == jpeg)
        Outbox.discardPhoto(name)
        #expect(Outbox.keptPhoto(name) == nil)
    }
}

// MARK: Step timers in seconds (parity with findDurations in static/js/cook.js; same cases in tests/test_cook.js)

struct StepDurationParityTests {
    private func seconds(_ text: String) -> [Int] { StepDurations.find(in: text).map(\.seconds) }

    @Test func decimalsWithAPointOrAComma() {
        #expect(seconds("Bake for 1.5 hours") == [5400])
        #expect(seconds("Bake for 1,5 hours") == [5400])
    }

    @Test func fractions() {
        #expect(seconds("Rest for 1/2 hour") == [1800])
        #expect(seconds("Rest for ½ hour") == [1800])
        #expect(seconds("Bake for 1½ hours") == [5400])
        #expect(seconds("Bake for 1 1/2 hours") == [5400])
    }

    @Test func wordsForOne() {
        #expect(seconds("Simmer for one hour") == [3600])
        #expect(seconds("Stir for a minute") == [60])
        #expect(seconds("Leave for an hour") == [3600])
    }

    @Test func secondsStayWhole() {
        #expect(seconds("Whisk for 45 secs") == [45])
        #expect(seconds("Microwave 2 minutes 30 seconds") == [150])
        let d = StepDurations.find(in: "Whisk for 45 secs")
        #expect(d.first?.label == "45 sec")
    }

    @Test func joinedTimes() {
        #expect(seconds("Bake 1 hour and 30 minutes") == [5400])
        #expect(seconds("Roast 1 hr, 15 min") == [4500])
        #expect(StepDurations.find(in: "Roast 1 hr, 15 min").first?.text == "1 hr, 15 min")
        let range = StepDurations.find(in: "Bake 2-3 hours and 30 minutes")
        #expect(range.first?.maxSeconds == 9000)   // the web's 150 minutes
    }

    @Test func onlyASmallerUnitJoins() {
        #expect(seconds("Rest 10 minutes and 1 hour") == [600, 3600])
        #expect(seconds("Bake 2 hours, then 30 minutes more") == [7200, 1800])
    }

    @Test func seventyTwoHourCap() {
        #expect(seconds("Cure for 72 hours") == [259_200])
        #expect(seconds("Age for 100 hours").isEmpty)
    }
}
