import XCTest

/// The seeded server the UI tests sign in to. `scripts/run-ui-tests.sh` starts it and passes these through
/// `TEST_RUNNER_`-prefixed environment variables (xcodebuild hands them to the test runner without the prefix).
struct TestServer {
    let url: String
    let username: String
    let password: String

    static let current = TestServer(
        url: ProcessInfo.processInfo.environment["SPOONMATE_TEST_SERVER"] ?? "http://127.0.0.1:5078",
        username: ProcessInfo.processInfo.environment["SPOONMATE_TEST_USERNAME"] ?? "Alex",
        password: ProcessInfo.processInfo.environment["SPOONMATE_TEST_PASSWORD"] ?? "Spoonmate-demo-1")
}

/// A shopping item as the server sees it (for checking that a tick really arrived).
struct ServerShoppingItem: Decodable {
    let id: Int
    let name: String
    let checked: Bool
}

/// Talks to the test server directly, to check what the app sent rather than only what it shows.
enum ServerAPI {
    private struct Login: Decodable { let token: String }
    private struct Shopping: Decodable { let items: [ServerShoppingItem] }

    static func token(_ server: TestServer = .current) async throws -> String {
        var request = URLRequest(url: URL(string: server.url + "/api/v1/auth/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": server.username, "password": server.password,
                                                    "device_name": "UI tests"])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Login.self, from: data).token
    }

    static func shoppingItems(token: String, _ server: TestServer = .current) async throws -> [ServerShoppingItem] {
        var request = URLRequest(url: URL(string: server.url + "/api/v1/shopping")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Shopping.self, from: data).items
    }

    /// Waits (up to `timeout`) until the server has an item called `name` with the wanted tick.
    static func waitForItem(_ name: String, checked: Bool, timeout: TimeInterval = 30) async throws -> Bool {
        let token = try await token()
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if try await shoppingItems(token: token).contains(where: { $0.name == name && $0.checked == checked }) { return true }
            try await Task.sleep(for: .milliseconds(500))   // a poll interval, not a fixed wait: it returns as soon as it's true
        }
        return false
    }
}

/// Launch arguments understood by the app's DEBUG-only `UITestHooks`.
enum Launch {
    /// Start signed out with nothing saved on the simulator.
    static let reset = "-UITestReset"
    /// Treat the server as unreachable for this launch.
    static let offline = "-UITestForceOffline"
}

@MainActor
extension XCUIApplication {
    /// Launches the app with the given hooks, light mode and English.
    static func spoonmate(_ hooks: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = hooks + ["-AppleLanguages", "(en)", "-AppleLocale", "en_AU"]
        app.launch()
        return app
    }

    /// Signs in from the welcome screen and waits for the Recipes tab.
    func signIn(_ server: TestServer = .current, file: StaticString = #filePath, line: UInt = #line) {
        let start = buttons["onboarding.signIn"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "The welcome screen didn't appear", file: file, line: line)
        start.tap()

        let address = textFields["signIn.server"]
        XCTAssertTrue(address.waitForExistence(timeout: 10), "No server address field", file: file, line: line)
        address.tap()
        // Return moves on to the next field (the keyboard would cover the password field for a tap), and Go signs in.
        address.typeText(server.url + "\n")
        let user = textFields["signIn.username"]
        XCTAssertTrue(user.wait(until: "hasKeyboardFocus == true", timeout: 5), "Return didn't move to Username", file: file, line: line)
        user.typeText(server.username + "\n")
        let password = secureTextFields["signIn.password"]
        XCTAssertTrue(password.wait(until: "hasKeyboardFocus == true", timeout: 5), "Return didn't move to Password", file: file, line: line)
        password.typeText(server.password)
        XCTAssertTrue(buttons["signIn.submit"].isEnabled)
        password.typeText("\n")

        let recipes = tabBars.buttons["Recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 30), "Didn't land on Recipes after signing in",
                      file: file, line: line)
        dismissSavePasswordOffer(until: recipes)
    }

    /// iOS offers to save the password (a system sheet over the app) after a signed build signs in. Turn it down,
    /// waiting until either it's gone or `element` can be tapped.
    func dismissSavePasswordOffer(until element: XCUIElement, timeout: TimeInterval = 15) {
        // The sheet belongs to SafariViewService, not to the app or SpringBoard.
        let notNow = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService").buttons["Not Now"]
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if notNow.exists { notNow.tap(); continue }
            if element.wait(until: "hittable == true", timeout: 1) { return }
        }
    }

    func tab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No \(title) tab", file: file, line: line)
        // Right after signing in the tab bar is still animating in, and a tap then can miss.
        XCTAssertTrue(button.wait(until: "hittable == true"), "The \(title) tab can't be tapped", file: file, line: line)
        for _ in 0..<3 {
            button.tap()
            if button.wait(until: "selected == true", timeout: 3) { return }
        }
        XCTFail("Couldn't switch to the \(title) tab", file: file, line: line)
    }

    /// Searches for `query` on the Search tab and opens the recipe called `title`.
    func openRecipe(_ title: String, searchingFor query: String) {
        // The Search tab turns into the search field when it's tapped (so it never shows as selected).
        let searchTab = tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10), "No Search tab")
        XCTAssertTrue(searchTab.wait(until: "hittable == true"), "The Search tab can't be tapped")
        searchTab.tap()
        let field = searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No search field")
        field.tap()
        field.typeText(query)
        let card = buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "\(title) isn't in the results")
        card.tap()
        XCTAssertTrue(staticTexts["recipe.title"].waitForExistence(timeout: 15), "The recipe page didn't open")
    }

    /// The first element of any kind whose label starts with `prefix`.
    func element(labelStartingWith prefix: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// A shopping-list row (its label is the item's name, then "Added by …" for someone else's).
    func shoppingRow(_ name: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, name + ",")).firstMatch
    }

    /// Finds a shopping-list row, scrolling the list down to it (rows below the fold aren't on screen, so they don't exist yet).
    func revealShoppingRow(_ name: String, swipes maxSwipes: Int = 12) -> XCUIElement {
        let row = shoppingRow(name)
        XCTAssertTrue(navigationBars["Shopping list"].waitForExistence(timeout: 10), "Not on the shopping list")
        for attempt in 0..<maxSwipes {
            // The first look also waits for the list to load.
            if row.waitForExistence(timeout: attempt == 0 ? 10 : 2), row.isHittable { break }
            windows.firstMatch.swipeUp(velocity: .slow)
        }
        return row
    }

    /// Scrolls the main scroll view up until `element` can be tapped.
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            swipeUp(velocity: .slow)
            swipes += 1
        }
    }
}

@MainActor
extension XCUIElement {
    /// Waits until `predicate` (e.g. "isSelected == true") holds for this element.
    func wait(until predicate: String, timeout: TimeInterval = 15) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
