import Foundation
import Testing
@testable import RecipeManager

private final class CookFixtureToken {}

/// A repeatable random source, so pool choices can be checked.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: Step timers (parity with findDurations in static/js/cook.js)

struct StepDurationTests {
    private func found(_ text: String) -> [[Int]] {
        StepDurations.find(in: text).map { [$0.minutes, $0.maxMinutes] }
    }

    @Test func overnightIsAnApproximateLongTimer() {
        let d = StepDurations.find(in: "Cover and refrigerate overnight.")
        #expect(d.map { [$0.minutes, $0.maxMinutes] } == [[480, 720]])
        #expect(d.first?.approx == true)
        #expect(d.first?.label == "Overnight · about 8 hr")
    }

    @Test func doublingIsAboutAnHourWhenNoTimeIsGiven() {
        let d = StepDurations.find(in: "Leave to rise until doubled in size.")
        #expect(d.map { [$0.minutes, $0.maxMinutes] } == [[60, 90]])
        #expect(d.first?.approx == true)
    }

    @Test func aGivenRangeWinsOverDoubling() {
        let d = StepDurations.find(in: "Leave for 1-2 hours until doubled.")
        #expect(d.map { [$0.minutes, $0.maxMinutes] } == [[60, 120]])
        #expect(d.first?.approx == false)
        #expect(d.first?.isRange == true)
        #expect(d.first?.extraMinutes == 60)
    }

    @Test func severalTimesInOneStepInOrder() {
        #expect(found("Simmer 2–3 hours, then rest 10 minutes.") == [[120, 180], [10, 10]])
    }

    @Test func doublingIsIgnoredWhenTheStepHasAnOrdinaryTime() {
        #expect(found("Prove until it has doubled, then bake for 25 minutes.") == [[25, 25]])
    }

    @Test func hoursAndMinutesTogether() {
        let d = StepDurations.find(in: "Bake 1 hour 30 minutes.")
        #expect(d.map { [$0.minutes, $0.maxMinutes] } == [[90, 90]])
        #expect(d.first?.isRange == false)
        #expect(d.first?.extraMinutes == 0)
    }

    @Test func noTimeNoTimer() {
        #expect(StepDurations.find(in: "Stir well and season.").isEmpty)
    }
}

// MARK: Step ingredients: whole sections named by a group noun

struct StepGroupTests {
    private let sections = [
        RecipeSection(heading: "Dough", lines: ["500 g flour", "7 g yeast", "300 ml water"]),
        RecipeSection(heading: "Filling", lines: ["200 g ricotta", "1 lemon, zested"]),
    ]

    @Test func namingBothGroupsBringsInBothSections() {
        let lines = StepIngredients.match(step: "Roll out the dough and spread the filling over it", section: nil, in: sections)
        #expect(lines == ["500 g flour", "7 g yeast", "300 ml water", "200 g ricotta", "1 lemon, zested"])
    }

    @Test func aStepInsideItsOwnSectionDoesNotListItAgain() {
        #expect(StepIngredients.match(step: "Knead the dough for 10 minutes", section: "Dough", in: sections).isEmpty)
    }

    @Test func aGroupWithNoMatchingHeadingChangesNothing() {
        #expect(StepIngredients.match(step: "Add the mixture to the pan", section: nil, in: sections).isEmpty)
    }

    @Test func withoutHeadingsMatchingIsUnchanged() {
        let plain = [RecipeSection(heading: nil, lines: ["400 g pasta", "1 cup tomato sauce"])]
        #expect(StepIngredients.match(step: "Pour the sauce over the pasta", section: nil, in: plain) == ["400 g pasta", "1 cup tomato sauce"])
    }
}

// MARK: Calendar and Reminders

struct CalendarExportTests {
    private func meal(_ id: Int, _ date: String, _ title: String = "Dinner: Lasagne", recipe: Int = 7) -> MealEvent {
        MealEvent(entryID: id, recipeID: recipe, title: title, date: date)
    }

    private func current(_ m: MealEvent) -> ExistingEvent {
        ExistingEvent(title: m.title, date: m.date, link: m.link, notes: m.notes)
    }

    @Test func newChangedUnchangedAndRemoved() {
        let unchanged = meal(1, "2026-11-02")
        let moved = meal(2, "2026-11-04", "Dinner: Curry", recipe: 8)
        let new = meal(3, "2026-11-05", "Lunch: Soup", recipe: 9)
        let exported: [Int: ExportedEvent] = [
            1: ExportedEvent(eventID: "e1", date: "2026-11-02"),
            2: ExportedEvent(eventID: "e2", date: "2026-11-03"),
            4: ExportedEvent(eventID: "e4", date: "2026-11-06"),     // no longer planned this week
            5: ExportedEvent(eventID: "e5", date: "2026-11-12"),     // next week: left alone
        ]
        let existing: [String: ExistingEvent] = [
            "e1": current(unchanged),
            "e2": ExistingEvent(title: "Dinner: Curry", date: "2026-11-03", link: moved.link, notes: moved.notes),
        ]
        let plan = CalendarExportDiff.plan(wanted: [new, moved, unchanged], exported: exported, existing: existing,
                                           from: "2026-11-02", to: "2026-11-08")
        #expect(plan.create == [new])
        #expect(plan.update == [CalendarExportDiff.Update(eventID: "e2", event: moved)])
        #expect(plan.unchanged == [1])
        #expect(plan.remove == [CalendarExportDiff.Removal(entryID: 4, eventID: "e4")])
    }

    @Test func anEventDeletedInCalendarIsMadeAgain() {
        let m = meal(1, "2026-11-02")
        let plan = CalendarExportDiff.plan(wanted: [m], exported: [1: ExportedEvent(eventID: "gone", date: "2026-11-02")],
                                           existing: [:], from: "2026-11-02", to: "2026-11-08")
        #expect(plan.create == [m])
        #expect(plan.update.isEmpty && plan.remove.isEmpty)
    }

    @Test func exportingTheSameWeekAgainChangesNothing() {
        let m = meal(1, "2026-11-02")
        let plan = CalendarExportDiff.plan(wanted: [m], exported: [1: ExportedEvent(eventID: "e1", date: m.date)],
                                           existing: ["e1": current(m)], from: "2026-11-02", to: "2026-11-08")
        #expect(plan.isEmpty)
        #expect(plan.unchanged == [1])
    }

    @Test func eventTitleAndLink() throws {
        let json = #"{"id": 12, "date": "2026-11-04", "meal_type": "dinner", "recipe": {"id": 5, "title": "Lasagne", "description": "", "prep_time": "", "cook_time": "", "servings": "", "image_url": "", "thumb_url": ""}}"#
        let entry = try APIClient.decoder.decode(PlanEntry.self, from: Data(json.utf8))
        let event = MealEvent(entry)
        #expect(event.title == "Dinner: Lasagne")
        #expect(event.link.absoluteString == "spoonmate://recipe/5")
        #expect(event.notes == "spoonmate://recipe/5")
    }

    @Test func summaries() {
        #expect(CalendarExportDiff.summary(added: 5, updated: 0, removed: 0) == "Added 5 meals to Calendar")
        #expect(CalendarExportDiff.summary(added: 1, updated: 0, removed: 0) == "Added 1 meal to Calendar")
        #expect(CalendarExportDiff.summary(added: 2, updated: 1, removed: 1) == "Calendar updated: 2 added, 1 updated, 1 removed")
        #expect(CalendarExportDiff.summary(added: 0, updated: 0, removed: 0) == "Calendar already has this week.")
        #expect(ReminderExport.summary(added: 3) == "Added 3 items to Reminders")
    }

    @Test func remindersSkipOpenDuplicatesIgnoringCase() {
        let names = ReminderExport.namesToAdd(open: ["Milk", " flour ", "Eggs", "milk", ""], existingOpen: ["FLOUR", "butter"])
        #expect(names == ["Milk", "Eggs"])
    }
}

// MARK: Widgets

struct WeekAndPoolTests {
    @Test func weekStartsTodayAndPrefersDinner() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15)))
        func m(_ id: Int, _ date: String, _ type: String) -> WidgetMeal {
            WidgetMeal(id: id, recipeID: id, title: "R\(id)", date: date, mealType: type, time: "", imageURL: nil)
        }
        let plan = PlanSnapshot(meals: [m(1, "2026-11-03", "dinner"), m(2, "2026-11-04", "lunch"), m(3, "2026-11-04", "dinner"),
                                        m(4, "2026-11-06", "breakfast"), m(5, "2026-11-11", "dinner")])
        let week = plan.week(from: now, calendar: calendar)
        #expect(week.map(\.date) == ["2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09", "2026-11-10"])
        #expect(week.map(\.isToday) == [true, false, false, false, false, false, false])
        #expect(week[0].meal?.id == 3 && week[0].others == 1)
        #expect(week[2].meal?.id == 4)
        #expect(week[1].meal == nil)
    }

    @Test func poolKeepsWhatItHadAndTopsUp() {
        var rng = SeededRandom(state: 1)
        let picked = RecipePoolSnapshot.select(Array(1...10), previous: [3, 99, 4, 3], cap: 5, using: &rng)
        #expect(picked.count == 5)
        #expect(Array(picked.prefix(2)) == [3, 4])           // still there, kept; 99 is gone
        #expect(Set(picked).count == 5 && Set(picked).isSubset(of: Set(1...10)))
        #expect(RecipePoolSnapshot.select([1, 2], previous: [], cap: 5, using: &rng).sorted() == [1, 2])
    }

    @Test func picksAreDifferentUntilThePoolRunsOut() {
        var rng = SeededRandom(state: 7)
        let pool = (1...8).map { PoolRecipe(id: $0, title: "R\($0)", image: nil) }
        let five = RecipePoolSnapshot.picks(from: pool, count: 5, using: &rng)
        #expect(five.count == 5 && Set(five.map(\.id)).count == 5)

        let two = Array(pool.prefix(2))
        let many = RecipePoolSnapshot.picks(from: two, count: 6, using: &rng)
        #expect(many.count == 6)
        #expect(zip(many, many.dropFirst()).allSatisfy { $0.id != $1.id })   // never the same twice running
        #expect(RecipePoolSnapshot.picks(from: [], count: 5, using: &rng).isEmpty)
    }

    @Test func poolByCollection() {
        let a = PoolRecipe(id: 1, title: "A", image: "1-x.jpg"), b = PoolRecipe(id: 2, title: "B", image: nil)
        let pool = RecipePoolSnapshot(all: [a, b], collections: [PoolCollection(id: 9, name: "Baking", recipes: [b])])
        #expect(pool.recipes(in: nil) == [a, b])
        #expect(pool.recipes(in: 9) == [b])
        #expect(pool.recipes(in: 404) == [a, b])
        #expect(pool.imageNames == ["1-x.jpg"])
    }
}

// MARK: Offline library recovery

struct LibraryRecoveryTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("library-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func oneBadRecipeIsSkippedNotTheLibrary() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try #require(Bundle(for: CookFixtureToken.self).url(forResource: "recipe_detail", withExtension: "json"))
        let good = try APIClient.decoder.decode(RecipeDetail.self, from: Data(contentsOf: url))
        var bad = try #require(try JSONSerialization.jsonObject(with: APIClient.encoder.encode(good)) as? [String: Any])
        bad["id"] = good.id + 1
        bad["title"] = ["not": "a title"]
        let file = dir.appendingPathComponent("library.json")
        let goodJSON = try JSONSerialization.jsonObject(with: APIClient.encoder.encode(good))
        try JSONSerialization.data(withJSONObject: [goodJSON, bad]).write(to: file)

        let read = OfflineStore.readLibrary(at: file)
        #expect(read.recipes.map(\.id) == [good.id])
        #expect(read.skipped == 1)
        #expect(read.firstError != nil)
        #expect(read.movedAside == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func anUnreadableFileIsMovedAsideAndOnlyTwoAreKept() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        for i in 0..<3 {
            try Data("garbage {".utf8).write(to: file)
            let read = OfflineStore.readLibrary(at: file, now: Date(timeIntervalSince1970: 1_000 + Double(i)))
            #expect(read.recipes.isEmpty)
            #expect(read.movedAside?.lastPathComponent == "library-corrupt-\(1_000_000 + i * 1000).json")
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(left == ["library-corrupt-1001000.json", "library-corrupt-1002000.json"])
    }

    @Test func noFileIsAnEmptyLibrary() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let read = OfflineStore.readLibrary(at: dir.appendingPathComponent("library.json"))
        #expect(read.recipes.isEmpty && read.skipped == 0 && read.movedAside == nil)
    }
}
