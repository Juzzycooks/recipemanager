import XCTest

/// Takes the README and App Store screenshots from the seeded demo server. Only `scripts/run-ui-tests.sh --screenshots`
/// runs it (it sets `SPOONMATE_SCREENSHOTS_DIR`, and the status bar and light mode on the simulator); anywhere else it
/// skips. Files are written as `docs-<name>.png` (docs/screenshots/ios) and `appstore-<NN-name>.png`
/// (AppStore/Screenshots/raw, the names generate.sh frames); the script copies and resizes them.
final class ScreenshotTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["SPOONMATE_SCREENSHOTS_DIR"], !path.isEmpty else {
            throw XCTSkip("Screenshots are taken by scripts/run-ui-tests.sh --screenshots")
        }
        folder = URL(fileURLWithPath: path)
        continueAfterFailure = false
    }

    @MainActor
    func testTakeScreenshots() {
        var app = XCUIApplication.spoonmate([Launch.reset])

        // Welcome
        XCTAssertTrue(app.buttons["onboarding.signIn"].waitForExistence(timeout: 20))
        shot(app, docs: "onboarding", appStore: "01-sign-in")

        // Home
        app.signIn()
        XCTAssertTrue(app.staticTexts["Banana Bread"].waitForExistence(timeout: 15))
        shot(app, docs: "home", appStore: "02-home")

        // All recipes (the button under the newest shelf)
        let allRecipes = app.buttons["home.allRecipes"]
        XCTAssertTrue(allRecipes.waitForExistence(timeout: 10))
        if !allRecipes.isHittable { app.swipeUp() }
        allRecipes.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(labelStartingWith: "Shakshuka").waitForExistence(timeout: 15))
        shot(app, appStore: "07-all-recipes")
        back(app, from: "All recipes")

        // Search, then a recipe from the results
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.wait(until: "hittable == true"))
        searchTab.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("tomato\n")
        let card = app.buttons.containing(.staticText, identifier: "Shakshuka").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        shot(app, docs: "search", appStore: "06-search")

        card.tap()
        XCTAssertTrue(app.staticTexts["recipe.title"].waitForExistence(timeout: 15))
        shot(app, docs: "recipe", appStore: "03-recipe-detail")
        app.buttons["Steps"].tap()
        XCTAssertTrue(app.element(labelStartingWith: "Step 1.").waitForExistence(timeout: 10))
        shot(app, docs: "steps")

        // Cook mode, on the step with a timer
        app.buttons["Start cooking"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 5"].waitForExistence(timeout: 10))
        for step in 2...4 {
            app.buttons["Next step"].tap()
            XCTAssertTrue(app.staticTexts["Step \(step) of 5"].waitForExistence(timeout: 5))
        }
        shot(app, docs: "cooking", appStore: "04-cooking")
        app.buttons["Close cook mode"].tap()

        // Collections
        app.tab("Collections")
        let weeknight = app.element(labelStartingWith: "Weeknight Dinners")
        XCTAssertTrue(weeknight.waitForExistence(timeout: 15))
        shot(app, docs: "collections", appStore: "08-collections")
        weeknight.tap()
        XCTAssertTrue(app.navigationBars["Weeknight Dinners"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(labelStartingWith: "Coconut Chicken Curry").waitForExistence(timeout: 15))
        shot(app, appStore: "09-collection-detail")

        // Meal plan and shopping list
        app.tab("Plan")
        XCTAssertTrue(app.element(labelStartingWith: "Garlic Butter Pasta").waitForExistence(timeout: 15))
        shot(app, docs: "meal-plan")
        app.tab("Shop")
        XCTAssertTrue(app.shoppingRow("Lemons").waitForExistence(timeout: 15))
        shot(app, docs: "shopping")

        // Add a recipe
        app.tab("Recipes")
        app.buttons["Add recipe"].tap()
        XCTAssertTrue(app.navigationBars["Add recipe"].waitForExistence(timeout: 10))
        shot(app, docs: "add-recipe", appStore: "10-add")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Add recipe"].wait(until: "exists == false", timeout: 10))

        // Profile: cook history, household, settings
        openProfile(app)
        app.buttons["Cook history"].tap()
        XCTAssertTrue(app.navigationBars["Cook history"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(labelStartingWith: "Added spinach").waitForExistence(timeout: 15))
        shot(app, docs: "cook-history")
        back(app, from: "Cook history")

        app.buttons["Household"].tap()
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(labelStartingWith: "Sam").waitForExistence(timeout: 15), "The second member isn't listed")
        shot(app, docs: "household")
        back(app, from: "Household")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        shot(app, docs: "settings", appStore: "11-settings")
        app.terminate()

        // Offline: the saved recipes, with the indicator
        app = XCUIApplication.spoonmate([Launch.offline])
        XCTAssertTrue(app.element(labelStartingWith: "Offline").waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Banana Bread"].waitForExistence(timeout: 15))
        shot(app, docs: "offline")
        app.terminate()

        // Dark mode with the Terracotta theme
        app = XCUIApplication.spoonmate()
        openProfile(app)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["Dark"].tap()
        app.buttons["Terracotta theme"].tap()
        XCTAssertTrue(app.buttons["Terracotta theme"].wait(until: "isSelected == true", timeout: 5))
        back(app, from: "Settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Banana Bread"].waitForExistence(timeout: 15))
        shot(app, docs: "dark-terracotta")
    }

    @MainActor
    private func openProfile(_ app: XCUIApplication) {
        app.tab("Recipes")
        app.buttons["Profile and settings"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10))
    }

    /// Taps the back button on the screen called `title` and waits for it to go.
    @MainActor
    private func back(_ app: XCUIApplication, from title: String) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "Not on \(title)")
        bar.buttons.firstMatch.tap()
        XCTAssertTrue(bar.wait(until: "exists == false", timeout: 10), "Didn't go back from \(title)")
    }

    /// Waits for pictures and animations to settle, then saves the screen under the given names.
    @MainActor
    private func shot(_ app: XCUIApplication, docs: String? = nil, appStore: String? = nil) {
        // Pictures show a spinner until they've loaded.
        XCTAssertTrue(app.activityIndicators.firstMatch.wait(until: "exists == false", timeout: 20), "Pictures didn't load")
        // Let any transition finish: wait until two screenshots a moment apart are the same.
        var png = XCUIScreen.main.screenshot().pngRepresentation
        for _ in 0..<20 {
            let next = XCUIScreen.main.screenshot().pngRepresentation
            if next == png { break }
            png = next
        }
        for name in [docs.map { "docs-\($0)" }, appStore.map { "appstore-\($0)" }].compactMap({ $0 }) {
            XCTAssertNoThrow(try png.write(to: folder.appendingPathComponent(name + ".png")))
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = docs ?? appStore
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
