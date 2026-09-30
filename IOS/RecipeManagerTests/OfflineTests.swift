import Foundation
import Testing
@testable import RecipeManager

private final class FixtureToken {}

private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let url = try #require(Bundle(for: FixtureToken.self).url(forResource: name, withExtension: "json"))
    return try APIClient.decoder.decode(T.self, from: Data(contentsOf: url))
}

/// A response cache that answers from a dictionary, so the client's offline fallback can be tested with no server.
private actor StubCache: ResponseCaching {
    var saved: [URL: Data] = [:]
    var built: Data?
    var reachable: [Bool] = []
    init(built: Data? = nil) { self.built = built }
    func store(_ data: Data, for url: URL) { saved[url] = data }
    func cached(for url: URL) -> Data? { saved[url] }
    func generated(path: String, query: [String: String]) -> Data? { path == "/recipes" ? built : nil }
    func reachability(_ reachable: Bool) { self.reachable.append(reachable) }
}

struct OfflineTests {
    // Nothing listens on this port, so every request fails with "cannot connect": the same as being offline.
    private let deadServer = URL(string: "http://127.0.0.1:9")!

    @Test func clientAnswersFromTheCacheWhenTheServerIsUnreachable() async throws {
        let stub = StubCache()
        let client = APIClient(baseURL: deadServer, token: "t", cache: stub)
        let url = try #require(client.url("/categories"))
        await stub.store(Data(#"{"items":[{"id":1,"name":"Dinner"}]}"#.utf8), for: url)
        let cats: ItemList<RecipeManager.Category> = try await client.get("/categories")
        #expect(cats.items.first?.name == "Dinner")
        #expect(await stub.reachable.contains(false))
    }

    @Test func clientPrefersLocallyBuiltListsWhenOffline() async throws {
        let stub = StubCache(built: Data(#"{"items":[],"page":1,"per_page":24,"total":0,"pages":1}"#.utf8))
        let client = APIClient(baseURL: deadServer, token: "t", cache: stub)
        let page: Page<RecipeSummary> = try await client.get("/recipes", query: ["q": "x"])
        #expect(page.total == 0)
    }

    @Test func offlineWithNothingSavedIsAnOfflineError() async {
        let client = APIClient(baseURL: deadServer, token: "t", cache: StubCache())
        do {
            let _: ItemList<RecipeManager.Category> = try await client.get("/categories")
            Issue.record("expected an error")
        } catch let error as APIError {
            #expect(error.isOffline)
            #expect(error.localizedDescription.contains("offline"))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func recipeIDsAreParsedFromPaths() {
        #expect(OfflineStore.recipeID(in: "/recipes/7") == 7)
        #expect(OfflineStore.recipeID(in: "/api/v1/recipes/42") == 42)
        #expect(OfflineStore.recipeID(in: "/recipes") == nil)
        #expect(OfflineStore.recipeID(in: "/recipes/7/comments") == nil)
        #expect(OfflineStore.recipeID(in: "/recipes/random") == nil)
    }

    @Test func libraryBuildsFilteredAndPagedLists() async throws {
        let store = OfflineStore.shared
        await store.clear()
        defer { Task { await store.clear() } }
        let base: RecipeDetail = try fixture("recipe_detail")          // "Shish Barak", favourite, category Dinner
        var soup = base; soup = RecipeDetail(copying: base, id: 2, title: "Tomato Soup", ingredients: "4 tomatoes", favorite: false)
        await store.upsert(base); await store.upsert(soup)

        func list(_ query: [String: String]) async throws -> Page<RecipeSummary> {
            let data = try #require(await store.generated(path: "/recipes", query: query))
            return try APIClient.decoder.decode(Page<RecipeSummary>.self, from: data)
        }
        #expect(try await list([:]).total == 2)
        #expect(try await list(["q": "tomato"]).items.map(\.title) == ["Tomato Soup"])
        #expect(try await list(["ingredient": "flour"]).items.map(\.title) == ["Shish Barak"])
        #expect(try await list(["favorites": "1"]).items.map(\.title) == ["Shish Barak"])
        #expect(try await list(["sort": "title_az"]).items.map(\.title) == ["Shish Barak", "Tomato Soup"])
        let paged = try await list(["per_page": "1", "page": "2", "sort": "title_az"])
        #expect(paged.items.map(\.title) == ["Tomato Soup"] && paged.pages == 2)
        // a single recipe, and an offline favourite showing up in the local copy
        let detailData = try #require(await store.generated(path: "/recipes/2", query: [:]))
        #expect(try APIClient.decoder.decode(RecipeDetail.self, from: detailData).title == "Tomato Soup")
        await store.apply(.favorite(recipeID: 2, wanted: true))
        #expect(try await list(["favorites": "1"]).total == 2)
    }

    @MainActor @Test func outboxReplacesEarlierChangesToTheSameThing() {
        let box = Outbox.shared
        box.clear()
        defer { box.clear() }
        box.enqueue(.favorite(recipeID: 1, wanted: true))
        box.enqueue(.favorite(recipeID: 1, wanted: false))
        box.enqueue(.setShoppingChecked(itemID: 5, checked: true))
        box.enqueue(.deleteShoppingItem(itemID: 5))
        box.enqueue(.addShoppingItem(name: "milk", checked: false))
        box.setAddChecked(name: "milk", checked: true)
        #expect(box.ops == [.favorite(recipeID: 1, wanted: false), .deleteShoppingItem(itemID: 5), .addShoppingItem(name: "milk", checked: true)])
        box.cancelAdd(name: "milk")
        #expect(box.count == 2)
    }

    @Test func sharedLinksAndTextAreRecognised() {
        #expect(SharedContent.firstWebLink(in: "Try this https://example.com/pasta?x=1 tonight") == URL(string: "https://example.com/pasta?x=1"))
        #expect(SharedContent.firstWebLink(in: "no link here") == nil)
        #expect(SharedContent.firstWebLink(in: "mailto:a@b.co") == nil)
        #expect(SharedContent.source(fromText: ["Great soup https://example.com/soup"]) == .link(URL(string: "https://example.com/soup")!))
        #expect(SharedContent.source(fromText: ["Ingredients: 2 cups flour, 1 tsp salt. Method: mix."]) != nil)
        #expect(SharedContent.source(fromText: ["hi"]) == nil)
    }

    @Test func credentialsRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(Credentials(server: "https://r.example", token: "rm_abc"))
        #expect(try JSONDecoder().decode(Credentials.self, from: data) == Credentials(server: "https://r.example", token: "rm_abc"))
    }
}

private extension RecipeDetail {
    /// A copy of a fixture recipe with a few fields changed (RecipeDetail has no memberwise-copy helper).
    init(copying base: RecipeDetail, id: Int, title: String, ingredients: String, favorite: Bool) {
        var data = (try? JSONSerialization.jsonObject(with: APIClient.encoder.encode(base))) as? [String: Any] ?? [:]
        data["id"] = id; data["title"] = title; data["ingredients"] = ingredients; data["is_favorite"] = favorite
        data["created_at"] = DateParsing.format(.now.addingTimeInterval(-3600))
        self = try! APIClient.decoder.decode(RecipeDetail.self, from: JSONSerialization.data(withJSONObject: data))
    }
}
