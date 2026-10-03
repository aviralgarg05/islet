import Foundation
import IsletCore

/// Looks up time-synced lyrics on LRCLIB. Only the song's title, artist, album and length are
/// sent (for a browser's song, as `BrowserSong` reads its title), over an ephemeral session (no
/// cookies, no cache) that refuses redirects, so the song can't be carried to another host, and
/// each song's answer is kept in `cache` so it is asked once. Used only while the user has
/// lyrics turned on.
public final class LyricsService {
    public let cache: LyricsCache
    private let userAgent: String
    private let session: URLSession

    /// `protocolClasses` lets tests answer requests without a network.
    public init(cache: LyricsCache, version: String, protocolClasses: [AnyClass] = []) {
        self.cache = cache
        userAgent = LRCLIB.userAgent(version: version)
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        if !protocolClasses.isEmpty { c.protocolClasses = protocolClasses + (c.protocolClasses ?? []) }
        session = URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }

    /// The saved answer for a song, without going online.
    public func cached(_ query: LyricsQuery) -> LyricsLookup? {
        cache.load(query.cacheKey, now: Date())
    }

    /// The exact match first, then a search with the same details. A song LRCLIB doesn't know
    /// is remembered as missing; a network failure isn't remembered at all, so it is tried again
    /// next time. Completes on the main thread.
    public func lookUp(_ query: LyricsQuery, completion: @escaping (Result<LyricsLookup, Error>) -> Void) {
        if let saved = cached(query) {
            completion(.success(saved))
            return
        }
        Task {
            let result: Result<LyricsLookup, Error>
            do {
                let found = try await fetch(query)
                cache.save(query.cacheKey, found, now: Date())
                result = .success(found)
            } catch {
                result = .failure(error)
            }
            await MainActor.run { completion(result) }
        }
    }

    private func fetch(_ query: LyricsQuery) async throws -> LyricsLookup {
        if let record: LRCLIBRecord = try await get(LRCLIB.getURL(query)), let lyrics = LRCLIB.lyrics(from: record, for: query) {
            return .found(lyrics)
        }
        let records: [LRCLIBRecord] = try await get(LRCLIB.searchURL(query)) ?? []
        if let best = LRCLIB.best(records, for: query), let lyrics = LRCLIB.lyrics(from: best, for: query) {
            return .found(lyrics)
        }
        return .missing
    }

    /// The decoded body, nil for "not found" (404) or a request LRCLIB can't answer (400).
    private func get<T: Decodable>(_ url: URL) async throws -> T? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 || status == 400 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
