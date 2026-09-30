import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case server(status: Int, code: String, message: String)
    case invalidServer
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "You've been signed out. Sign in again."
        case .server(_, _, let message): message
        case .invalidServer: "That doesn't look like a server address."
        case .network(let error): "Couldn't reach the server. \(error.localizedDescription)"
        case .decoding: "The server sent something the app didn't understand. Is it up to date?"
        }
    }
}

/// Thin wrapper over URLSession for the `/api/v1` JSON API (see API.md).
struct APIClient: Sendable {
    let baseURL: URL
    var token: String?

    struct Empty: Decodable, Sendable {}
    private struct Envelope: Decodable { struct Inner: Decodable { let code: String; let message: String }; let error: Inner }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = DateParsing.parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: Requests

    func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try decode(try await data("GET", path, query: query, body: nil))
    }

    func send<T: Decodable & Sendable>(_ method: String, _ path: String, body: (any Encodable & Sendable)? = nil) async throws -> T {
        try decode(try await data(method, path, query: [:], body: body))
    }

    func send(_ method: String, _ path: String, body: (any Encodable & Sendable)? = nil, query: [String: String] = [:]) async throws {
        _ = try await data(method, path, query: query, body: body)
    }

    struct UploadFile: Sendable { let filename: String; let mime: String; let data: Data }

    /// Multipart upload of one or more files under the same field name (pictures, photo import).
    func upload<T: Decodable & Sendable>(_ method: String, _ path: String, field: String, files: [UploadFile],
                                        fields: [String: String] = [:]) async throws -> T {
        let boundary = "rm-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        for file in files {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(file.filename)\"\r\nContent-Type: \(file.mime)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        var request = try makeRequest(method, path, query: [:])
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try decode(try await perform(request))
    }

    // MARK: Plumbing

    private func makeRequest(_ method: String, _ path: String, query: [String: String]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidServer }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = prefix + "/api/v1" + path
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw APIError.invalidServer }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func data(_ method: String, _ path: String, query: [String: String], body: (any Encodable & Sendable)?) async throws -> Data {
        var request = try makeRequest(method, path, query: query)
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw APIError.network(error) }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidServer }
        guard (200..<300).contains(http.statusCode) else {
            let env = try? Self.decoder.decode(Envelope.self, from: data)
            if http.statusCode == 401, env?.error.code != "invalid_credentials" { throw APIError.unauthorized }
            throw APIError.server(status: http.statusCode, code: env?.error.code ?? "error",
                                  message: env?.error.message ?? "The server answered with an error (\(http.statusCode)).")
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == Empty.self || data.isEmpty, let empty = Empty() as? T { return empty }
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// Resolves the API's image paths (`/admin/uploads/x.jpg`) against the server; absolute links pass through.
    func resolve(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}

enum DateParsing {
    // ISO8601DateFormatter isn't Sendable; formatters are created per call (cheap enough for JSON decoding of pages).
    static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: text) { return d }
        // Python emits 6 fractional digits; trim to 3 for the formatter
        if let dot = text.firstIndex(of: "."), let end = text[dot...].firstIndex(where: { $0 == "+" || $0 == "Z" || $0 == "-" }) {
            let fraction = text[text.index(after: dot)..<end]
            let trimmed = text[..<dot] + "." + fraction.prefix(3) + text[end...]
            return withFraction.date(from: String(trimmed))
        }
        return nil
    }
}

private extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}
