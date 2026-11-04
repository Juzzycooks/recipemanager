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
    func testAllRecipesButtonOpensASearchableList() {
        let app = XCUIApplication.spoonmate([Launch.reset])
        app.signIn()
        let allRecipes = app.buttons["home.allRecipes"]
        XCTAssertTrue(allRecipes.waitForExistence(timeout: 15), "No All recipes button under the shelf")
        if !allRecipes.isHittable { app.swipeUp() }
        allRecipes.tap()
        XCTAssertTrue(app.navigationBars["All recipes"].waitForExistence(timeout: 10), "All recipes didn't open")
        XCTAssertTrue(app.element(labelStartingWith: "Shakshuka").waitForExistence(timeout: 15), "The list didn't load")

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "All recipes has no search field")
        field.tap()
        field.typeText("Coconut")
        XCTAssertTrue(app.element(labelStartingWith: "Coconut Chicken Curry").waitForExistence(timeout: 15), "Search didn't find it")
        XCTAssertTrue(app.element(labelStartingWith: "Shakshuka").wait(until: "exists == false", timeout: 10), "Search didn't narrow the list")
    }

    /// Regression: on All recipes, tapping Category or Ingredient opened a recipe instead of the filter sheet. The first
    /// card's tall photo, filled and clipped, still took taps above the card, over the chips. The demo pictures are all
    /// landscape, so this adds a recipe with a portrait photo (the newest, so it comes first) and removes it afterwards.
    @MainActor
    func testFilterChipsOpenTheirSheetsNotARecipe() async throws {
        let tallID = try await ServerAPI.addTallPhotoRecipe("Tall Photo Tart")
        addTeardownBlock { try? await ServerAPI.deleteRecipe(tallID) }
        let app = XCUIApplication.spoonmate([Launch.reset])
        app.signIn()

        // All recipes
        let allRecipes = app.buttons["home.allRecipes"]
        XCTAssertTrue(allRecipes.waitForExistence(timeout: 15), "No All recipes button under the shelf")
        if !allRecipes.isHittable { app.swipeUp() }
        allRecipes.tap()
        XCTAssertTrue(app.navigationBars["All recipes"].waitForExistence(timeout: 10), "All recipes didn't open")
        XCTAssertTrue(app.element(labelStartingWith: "Tall Photo Tart").waitForExistence(timeout: 15), "The list didn't load")
        checkChipOpensSheet(app, chip: "Category")
        checkChipOpensSheet(app, chip: "Ingredient")

        // Choosing in the sheets filters the list and stays on it.
        app.buttons["Category"].firstMatch.tap()
        let categorySheet = app.navigationBars["Category"]
        XCTAssertTrue(categorySheet.waitForExistence(timeout: 5))
        let firstCategory = app.cells.buttons.firstMatch
        XCTAssertTrue(firstCategory.waitForExistence(timeout: 10), "No categories in the sheet")
        firstCategory.tap()
        categorySheet.buttons["Done"].tap()
        XCTAssertTrue(categorySheet.wait(until: "exists == false", timeout: 5))
        XCTAssertFalse(app.staticTexts["recipe.title"].waitForExistence(timeout: 2), "Choosing a category opened a recipe")
        XCTAssertTrue(app.navigationBars["All recipes"].exists, "Choosing a category left All recipes")

        app.element(labelStartingWith: "Ingredient").tap()
        let ingredientSheet = app.navigationBars["Ingredient"]
        XCTAssertTrue(ingredientSheet.waitForExistence(timeout: 5))
        app.textFields.firstMatch.typeText("egg")
        ingredientSheet.buttons["Done"].tap()
        XCTAssertTrue(ingredientSheet.wait(until: "exists == false", timeout: 5))
        XCTAssertFalse(app.staticTexts["recipe.title"].waitForExistence(timeout: 2), "Choosing an ingredient opened a recipe")
        XCTAssertTrue(app.navigationBars["All recipes"].exists, "Choosing an ingredient left All recipes")

        // Search: the chips over the results
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.wait(until: "hittable == true"))
        searchTab.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("a")
        XCTAssertTrue(app.element(labelStartingWith: "Shakshuka").waitForExistence(timeout: 15), "Search found nothing")
        checkChipOpensSheet(app, chip: "Category")
        checkChipOpensSheet(app, chip: "Ingredient")
    }

    @MainActor
    private func checkChipOpensSheet(_ app: XCUIApplication, chip: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[chip].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No \(chip) chip", file: file, line: line)
        button.tap()
        let sheet = app.navigationBars[chip]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "The \(chip) sheet didn't open", file: file, line: line)
        XCTAssertFalse(app.staticTexts["recipe.title"].exists, "Tapping \(chip) opened a recipe", file: file, line: line)
        sheet.buttons["Done"].tap()
        XCTAssertTrue(sheet.wait(until: "exists == false", timeout: 5), "The \(chip) sheet didn't close", file: file, line: line)
        XCTAssertFalse(app.staticTexts["recipe.title"].exists, "Closing the \(chip) sheet opened a recipe", file: file, line: line)

        // Again, closed by tapping the dimmed screen above the sheet (where the recipe cards are).
        button.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "The \(chip) sheet didn't open again", file: file, line: line)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(sheet.wait(until: "exists == false", timeout: 5), "Tapping outside didn't close the \(chip) sheet", file: file, line: line)
        XCTAssertFalse(app.staticTexts["recipe.title"].waitForExistence(timeout: 2), "Tapping outside the \(chip) sheet opened a recipe", file: file, line: line)
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
