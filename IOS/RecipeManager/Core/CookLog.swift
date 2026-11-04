import Foundation

/// Cook history requests (API.md, "Cook history"), shared by the recipe page, cook mode's finish panel, the Outbox and
/// the timeline, so "I made this" is sent the same way whether it goes now or later.
enum CookLog {
    private struct Note: Encodable, Sendable { let note: String }

    /// `POST /recipes/{id}/made`: no body, JSON `{note}`, or multipart `note` + `photo` (one request).
    static func logMade(_ client: APIClient, recipeID: Int, note: String?, photo: Data?) async throws -> MadeResult {
        let path = "/recipes/\(recipeID)/made"
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let photo {
            return try await client.upload("POST", path, field: "photo", files: [photoFile(photo)],
                                           fields: note.isEmpty ? [:] : ["note": note])
        }
        if !note.isEmpty { return try await client.send("POST", path, body: Note(note: note)) }
        return try await client.send("POST", path)
    }

    static func setNote(_ client: APIClient, entryID: Int, note: String) async throws -> CookEntry {
        try await client.send("PATCH", "/cook-log/\(entryID)", body: Note(note: note))
    }

    static func setPhoto(_ client: APIClient, entryID: Int, photo: Data) async throws -> CookEntry {
        try await client.upload("POST", "/cook-log/\(entryID)/photo", field: "photo", files: [photoFile(photo)])
    }

    static func removePhoto(_ client: APIClient, entryID: Int) async throws -> CookEntry {
        try await client.send("DELETE", "/cook-log/\(entryID)/photo")
    }

    static func delete(_ client: APIClient, entryID: Int) async throws {
        try await client.send("DELETE", "/cook-log/\(entryID)")
    }

    /// The server refused the picture itself (422 not an image, 413 too big), not the request.
    static func isPhotoRejection(_ status: Int) -> Bool { status == 413 || status == 415 || status == 422 }

    private static func photoFile(_ jpeg: Data) -> APIClient.UploadFile {
        APIClient.UploadFile(filename: "cook.jpg", mime: "image/jpeg", data: jpeg)
    }
}
