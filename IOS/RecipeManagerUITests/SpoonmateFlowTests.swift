import XCTest

/// The main journeys, end to end against the seeded demo server (`tools/seed_demo.py`): sign in, open a recipe, cook it,
/// shop for it, and tick an item offline. Each test starts from a clean, signed-out app (`-UITestReset`).
final class SpoonmateFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInLandsOnRecipes() {
        let app = XCUIApplication.spoonmate([Launch.reset])
        app.signIn()
        XCTAssertTrue(app.staticTexts["Newest"].waitForExistence(timeout: 15), "Home's shelf didn't load")
        XCTAssertTrue(app.staticTexts["Banana Bread"].waitForExistence(timeout: 15), "The newest recipe isn't on the shelf")
    }

    @MainActor
    func testRecipeShowsTitleAndIngredients() {
        let app = XCUIApplication.spoonmate([Launch.reset])
        app.signIn()
        app.openRecipe("Coconut Chicken Curry", searchingFor: "Coconut")

        XCTAssertEqual(app.staticTexts["recipe.title"].label, "Coconut Chicken Curry")
        XCTAssertTrue(app.buttons["400 ml coconut milk"].waitForExistence(timeout: 10), "Ingredients aren't listed")
        XCTAssertTrue(app.buttons["600 g chicken thighs, cubed"].exists)

        app.buttons["Steps"].tap()
        XCTAssertTrue(app.element(labelStartingWith: "Step 1. Brown the chicken").waitForExistence(timeout: 10), "Steps aren't listed")
    }

    @MainActor
    func testCookModeToTheEndLogsACook() {
        let app = XCUIApplication.spoonmate([Launch.reset])
        app.signIn()
        app.openRecipe("Greek Salad", searchingFor: "Greek")

        app.buttons["Start cooking"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 10), "Cook mode didn't open on step 1")
        app.buttons["Next step"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 5))
        app.buttons["Next step"].tap()
        XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 5))
        app.buttons["Finish cooking"].tap()

        XCTAssertTrue(app.staticTexts["Nice. You made it."].waitForExistence(timeout: 5), "No finish sheet")
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.staticTexts["Nice. Marked as made."].waitForExistence(timeout: 15), "Skip didn't log the cook")
        app.buttons["Close"].tap()

        // The recipe page counts it ...
        let notes = app.buttons["Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        notes.tap()
        XCTAssertTrue(app.element(labelStartingWith: "Made 1 time").waitForExistence(timeout: 10), "The made count didn't go up")

        // ... and so does Profile → Cook history.
        app.tab("Recipes")
        app.buttons["Profile and settings"].tap()
        let history = app.buttons["Cook history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        XCTAssertTrue(app.buttons["Greek Salad"].waitForExistence(timeout: 15), "The cook isn't in Cook history")
    }

    @MainActor
    func testAddIngredientsToShoppingListAndTickOne() async throws {
        let app = XCUIApplication.spoonmate([Launch.reset])
        app.signIn()
        app.openRecipe("Garlic Butter Pasta", searchingFor: "Garlic Butter")

        let add = app.buttons["Add all to shopping list"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        app.scrollTo(add)
        add.tap()
        XCTAssertTrue(app.element(labelStartingWith: "Added").waitForExistence(timeout: 10), "No confirmation after adding")

        app.tab("Shop")
        // Produce comes first, so the garlic is above the pasta (the list is only scrolled down).
        XCTAssertTrue(app.revealShoppingRow("5 cloves garlic, minced").exists, "The recipe's garlic isn't on the list")
        let spaghetti = app.revealShoppingRow("200 g spaghetti")
        XCTAssertTrue(spaghetti.exists, "The recipe's ingredients aren't on the list")
        XCTAssertFalse(spaghetti.isSelected)
        spaghetti.tap()

        XCTAssertTrue(app.revealShoppingRow("200 g spaghetti").wait(until: "isSelected == true"), "The item isn't ticked")
        XCTAssertTrue(app.staticTexts["Completed"].exists, "The ticked item isn't under Completed")
        let sent = try await ServerAPI.waitForItem("200 g spaghetti", checked: true)
        XCTAssertTrue(sent, "The server doesn't have the tick")
    }

    @MainActor
    func testTickWhileOfflineIsSentWhenBackOnline() async throws {
        // On the seeded list (added by the other household member), and in no recipe the other tests add, so it isn't merged.
        let item = "Greek yoghurt"

        // Online first, so the list is saved on the phone.
        var app = XCUIApplication.spoonmate([Launch.reset])
        app.signIn()
        app.tab("Shop")
        XCTAssertTrue(app.revealShoppingRow(item).exists, "\(item) isn't on the list")
        XCTAssertFalse(app.shoppingRow(item).isSelected)
        app.terminate()

        // Offline: the indicator shows, and the tick is kept and queued.
        app = XCUIApplication.spoonmate([Launch.offline])
        XCTAssertTrue(app.tabBars.buttons["Recipes"].waitForExistence(timeout: 20), "The app didn't open offline")
        XCTAssertTrue(app.element(labelStartingWith: "Offline").waitForExistence(timeout: 10), "No offline indicator")
        app.tab("Shop")
        let row = app.revealShoppingRow(item)
        XCTAssertTrue(row.exists, "The saved list isn't shown offline")
        row.tap()
        XCTAssertTrue(app.element(labelStartingWith: "Offline · showing saved recipes · 1 change waiting").waitForExistence(timeout: 10),
                      "The tick isn't waiting to be sent")
        XCTAssertTrue(app.revealShoppingRow(item).wait(until: "isSelected == true"), "The offline tick didn't stick")
        let early = try await ServerAPI.waitForItem(item, checked: true, timeout: 1)
        XCTAssertFalse(early, "The tick reached the server while offline")
        app.terminate()

        // Back online: the queued tick is sent ...
        app = XCUIApplication.spoonmate()
        XCTAssertTrue(app.tabBars.buttons["Recipes"].waitForExistence(timeout: 20))
        let sent = try await ServerAPI.waitForItem(item, checked: true)
        XCTAssertTrue(sent, "The offline tick never reached the server")
        XCTAssertFalse(app.element(labelStartingWith: "Offline").exists, "Still showing the offline indicator")
        app.terminate()

        // ... and survives a reload: a fresh launch reads the list from the server.
        app = XCUIApplication.spoonmate()
        app.tab("Shop")
        XCTAssertTrue(app.revealShoppingRow(item).wait(until: "isSelected == true"), "The tick was lost after reloading")
        XCTAssertTrue(app.staticTexts["Completed"].exists)
    }
}
