import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

@Observable
final class SpotifyClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private enum Constants {
        static let clientID = "e8c52f832486497fa1b6a7f5912923cd"
        static let redirectURI = "spotify-alarm-login://callback"
        static let callbackScheme = "spotify-alarm-login"
        static let scopes = "playlist-read-private playlist-read-collaborative user-read-email user-top-read"
    }

    private struct TokenResponse: Decodable, Encodable {
        let accessToken: String
        let tokenType: String
        let scope: String?
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private struct StoredToken: Codable {
        var accessToken: String
        var refreshToken: String?
        var expirationDate: Date
    }

    private struct PlaylistTracksResponse: Decodable {
        let items: [PlaylistItem]
    }

    private struct PlaylistItem: Decodable {
        let track: SpotifyAPITrack?
    }

    private struct AlbumTracksResponse: Decodable {
        let items: [SpotifyAPITrack]
    }

    private struct UserPlaylistsResponse: Decodable {
        let items: [SpotifyAPIPlaylist]
        let next: String?
    }

    private struct TopTracksResponse: Decodable {
        let items: [SpotifyAPITrack]
    }

    private struct SpotifyAPIPlaylist: Decodable {
        let id: String
        let name: String
        let externalURLs: [String: String]?
        let tracks: PlaylistTrackSummary

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case externalURLs = "external_urls"
            case tracks
        }
    }

    private struct PlaylistTrackSummary: Decodable {
        let total: Int
    }

    private struct SpotifyAPITrack: Decodable {
        let id: String?
        let name: String
        let uri: String?
        let externalURLs: [String: String]?
        let previewURL: URL?
        let artists: [Artist]

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case uri
            case externalURLs = "external_urls"
            case previewURL = "preview_url"
            case artists
        }
    }

    private struct Artist: Decodable {
        let name: String
    }

    var isLoggedIn = false
    var statusText = "Nicht mit Spotify verbunden"

    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let tokenStorageKey = "spotifyToken"
    @ObservationIgnored private let jsonDecoder = JSONDecoder()
    @ObservationIgnored private let jsonEncoder = JSONEncoder()

    override init() {
        super.init()
        isLoggedIn = loadStoredToken() != nil
        statusText = isLoggedIn ? "Mit Spotify verbunden" : "Nicht mit Spotify verbunden"
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let windowScene else {
            preconditionFailure("Spotify login needs an active window scene.")
        }

        return ASPresentationAnchor(windowScene: windowScene)
    }

    func login() async throws {
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.makeCodeChallenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Constants.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Constants.redirectURI),
            URLQueryItem(name: "scope", value: Constants.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "show_dialog", value: "true")
        ]

        guard let authURL = components?.url else { throw SpotifyError.invalidAuthorizationURL }
        guard Self.isCallbackSchemeRegistered else { throw SpotifyError.missingCallbackURLScheme }

        let callbackURL = try await authenticate(with: authURL)
        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let returnedState = callbackComponents?.queryItems?.first(where: { $0.name == "state" })?.value
        let code = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value
        let error = callbackComponents?.queryItems?.first(where: { $0.name == "error" })?.value

        if let error {
            throw SpotifyError.authorizationFailed(error)
        }

        guard returnedState == state, let code else { throw SpotifyError.invalidCallback }

        let tokenResponse = try await requestToken(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Constants.redirectURI,
            "client_id": Constants.clientID,
            "code_verifier": verifier
        ])

        storeToken(tokenResponse)
        isLoggedIn = true
        statusText = "Mit Spotify verbunden"
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenStorageKey)
        isLoggedIn = false
        statusText = "Nicht mit Spotify verbunden"
    }

    func userPlaylists() async throws -> [SpotifyPlaylist] {
        var endpoint: String? = "https://api.spotify.com/v1/me/playlists?limit=50"
        var playlists: [SpotifyPlaylist] = []

        while let currentEndpoint = endpoint {
            let data = try await authenticatedData(from: currentEndpoint)
            let response = try jsonDecoder.decode(UserPlaylistsResponse.self, from: data)

            playlists.append(contentsOf: response.items.map { playlist in
                SpotifyPlaylist(
                    id: playlist.id,
                    name: playlist.name,
                    trackCount: playlist.tracks.total,
                    spotifyURL: spotifyURL(from: playlist)
                )
            })

            endpoint = response.next
        }

        return playlists
    }

    func topTracks() async throws -> [SpotifyTrack] {
        let data = try await authenticatedData(from: "https://api.spotify.com/v1/me/top/tracks?limit=50&time_range=medium_term")
        let response = try jsonDecoder.decode(TopTracksResponse.self, from: data)
        return response.items.compactMap { spotifyTrack(from: $0) }
    }

    func tracks(from playlist: SpotifyPlaylist) async throws -> [SpotifyTrack] {
        let source = SpotifySource.playlist(id: playlist.id, name: playlist.name, url: playlist.spotifyURL)
        return try await tracks(from: source)
    }

    func randomPreviewTrack(from sources: [SpotifySource]) async throws -> SpotifyTrack? {
        guard sources.isEmpty == false else { return nil }

        let shuffledSources = sources.shuffled()

        for source in shuffledSources {
            let tracks = try await tracks(from: source).filter(\.hasPreview)
            if let track = tracks.randomElement() {
                return track
            }
        }

        return nil
    }

    func randomTrack(from sources: [SpotifySource]) async throws -> SpotifyTrack? {
        guard sources.isEmpty == false else { return nil }

        let shuffledSources = sources.shuffled()

        for source in shuffledSources {
            let tracks = try await tracks(from: source)
            if let track = tracks.randomElement() {
                return track
            }
        }

        return nil
    }

    private func tracks(from source: SpotifySource) async throws -> [SpotifyTrack] {
        guard let spotifyID = source.spotifyID else { return [] }

        let endpoint: String
        switch source.kind {
        case .playlist:
            endpoint = "https://api.spotify.com/v1/playlists/\(spotifyID)/tracks?limit=100&market=from_token"
        case .album:
            endpoint = "https://api.spotify.com/v1/albums/\(spotifyID)/tracks?limit=50&market=from_token"
        }

        let data = try await authenticatedData(from: endpoint)

        switch source.kind {
        case .playlist:
            let response = try jsonDecoder.decode(PlaylistTracksResponse.self, from: data)
            return response.items.compactMap { item in
                guard let apiTrack = item.track else { return nil }
                return spotifyTrack(from: apiTrack)
            }
        case .album:
            let response = try jsonDecoder.decode(AlbumTracksResponse.self, from: data)
            return response.items.compactMap { spotifyTrack(from: $0) }
        }
    }

    private func spotifyURL(from playlist: SpotifyAPIPlaylist) -> URL? {
        guard let urlString = playlist.externalURLs?["spotify"] else { return nil }
        return URL(string: urlString)
    }

    private func spotifyTrack(from apiTrack: SpotifyAPITrack) -> SpotifyTrack? {
        guard let spotifyURL = spotifyURL(from: apiTrack) else { return nil }

        return SpotifyTrack(
            name: apiTrack.name,
            artistNames: apiTrack.artists.map(\.name),
            spotifyURL: spotifyURL,
            previewURL: apiTrack.previewURL
        )
    }

    private func spotifyURL(from apiTrack: SpotifyAPITrack) -> URL? {
        if let urlString = apiTrack.externalURLs?["spotify"], let url = URL(string: urlString) {
            return url
        }

        if let uri = apiTrack.uri, uri.hasPrefix("spotify:track:") {
            let id = uri.replacingOccurrences(of: "spotify:track:", with: "")
            return URL(string: "https://open.spotify.com/track/\(id)")
        }

        if let id = apiTrack.id {
            return URL(string: "https://open.spotify.com/track/\(id)")
        }

        return nil
    }

    private func authenticatedData(from endpoint: String) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw SpotifyError.invalidEndpoint }
        let accessToken = try await validAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validAccessToken() async throws -> String {
        guard var storedToken = loadStoredToken() else { throw SpotifyError.notLoggedIn }

        if storedToken.expirationDate.timeIntervalSinceNow > 60 {
            return storedToken.accessToken
        }

        guard let refreshToken = storedToken.refreshToken else { throw SpotifyError.notLoggedIn }

        let tokenResponse = try await requestToken(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Constants.clientID
        ])

        storedToken.accessToken = tokenResponse.accessToken
        storedToken.refreshToken = tokenResponse.refreshToken ?? refreshToken
        storedToken.expirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        save(storedToken)
        return storedToken.accessToken
    }

    private func authenticate(with url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Constants.callbackScheme) { callbackURL, error in
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyError.loginCanceled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: SpotifyError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session

            if session.start() == false {
                continuation.resume(throwing: SpotifyError.authorizationSessionFailed)
            }
        }
    }

    private func requestToken(parameters: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { throw SpotifyError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(parameters).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try jsonDecoder.decode(TokenResponse.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpotifyError.requestFailed(message)
        }
    }

    private func storeToken(_ tokenResponse: TokenResponse) {
        let storedToken = StoredToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
        save(storedToken)
    }

    private func save(_ token: StoredToken) {
        guard let data = try? jsonEncoder.encode(token) else { return }
        UserDefaults.standard.set(data, forKey: tokenStorageKey)
    }

    private func loadStoredToken() -> StoredToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenStorageKey) else { return nil }
        return try? jsonDecoder.decode(StoredToken.self, from: data)
    }

    private static var isCallbackSchemeRegistered: Bool {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }

        return urlTypes.contains { urlType in
            guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else { return false }
            return schemes.contains(Constants.callbackScheme)
        }
    }

    private static func makeCodeVerifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<96).compactMap { _ in characters.randomElement() })
    }

    private static func makeCodeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formURLEncoded(_ parameters: [String: String]) -> String {
        parameters
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
    }
}

struct SpotifyPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let trackCount: Int
    let spotifyURL: URL?

    var detailText: String {
        "\(trackCount) Songs"
    }
}

struct SpotifyTrack: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let artistNames: [String]
    let spotifyURL: URL
    let previewURL: URL?

    var hasPreview: Bool {
        previewURL != nil
    }

    var displayName: String {
        if artistNames.isEmpty {
            return name
        }

        return "\(name) - \(artistNames.joined(separator: ", "))"
    }
}


enum SpotifyError: LocalizedError {
    case authorizationFailed(String)
    case authorizationSessionFailed
    case invalidAuthorizationURL
    case invalidCallback
    case invalidEndpoint
    case loginCanceled
    case missingCallbackURLScheme
    case noPreviewAvailable
    case notLoggedIn
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let message):
            "Spotify Login fehlgeschlagen: \(message)"
        case .authorizationSessionFailed:
            "Spotify Login konnte nicht gestartet werden. Starte die App im Simulator oder auf dem iPhone, nicht in der Preview."
        case .invalidAuthorizationURL:
            "Spotify Login-URL ist ungueltig."
        case .invalidCallback:
            "Spotify Redirect konnte nicht gelesen werden."
        case .invalidEndpoint:
            "Spotify API-Endpunkt ist ungueltig."
        case .loginCanceled:
            "Spotify Login wurde abgebrochen. Falls du nicht abgebrochen hast: pruefe, ob das URL-Schema spotify-alarm-login im Target registriert ist."
        case .missingCallbackURLScheme:
            "URL-Schema fehlt: Registriere spotify-alarm-login unter Target > Info > URL Types."
        case .noPreviewAvailable:
            "Für diese Auswahl ist keine Spotify Preview-MP3 verfügbar. Wähle einen anderen Song."
        case .notLoggedIn:
            "Bitte zuerst mit Spotify verbinden."
        case .requestFailed(let message):
            "Spotify Anfrage fehlgeschlagen: \(message)"
        }
    }
}


private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}
