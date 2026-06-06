import Foundation

struct DeezerPreview: Hashable {
    let previewURL: URL
    let coverURL: URL?
}

struct DeezerPreviewClient {
    private struct SearchResponse: Decodable {
        let data: [Track]
    }

    private struct Track: Decodable {
        let title: String
        let preview: String
        let artist: Artist
        let album: Album?
    }

    private struct Artist: Decodable {
        let name: String
    }

    private struct Album: Decodable {
        let coverMedium: String?
        let coverBig: String?
        let coverXL: String?

        enum CodingKeys: String, CodingKey {
            case coverMedium = "cover_medium"
            case coverBig = "cover_big"
            case coverXL = "cover_xl"
        }
    }

    func preview(for track: SpotifyTrack) async throws -> DeezerPreview {
        let artist = track.artistNames.first ?? ""
        let query = "artist:\"\(artist)\" track:\"\(track.name)\""
        let searchURL = try makeSearchURL(query: query)
        let response = try await fetchSearchResponse(from: searchURL)

        if let exactMatch = response.data.first(where: { deezerTrack in
            deezerTrack.preview.isEmpty == false
            && deezerTrack.title.localizedCaseInsensitiveContains(track.name)
            && (artist.isEmpty || deezerTrack.artist.name.localizedCaseInsensitiveContains(artist))
        }), let url = URL(string: exactMatch.preview) {
            return DeezerPreview(previewURL: url, coverURL: coverURL(from: exactMatch))
        }

        if let firstPreview = response.data.first(where: { $0.preview.isEmpty == false }),
           let url = URL(string: firstPreview.preview) {
            return DeezerPreview(previewURL: url, coverURL: coverURL(from: firstPreview))
        }

        throw SpotifyError.noPreviewAvailable
    }

    func previewURL(for track: SpotifyTrack) async throws -> URL {
        let artist = track.artistNames.first ?? ""
        let query = "artist:\"\(artist)\" track:\"\(track.name)\""
        let searchURL = try makeSearchURL(query: query)
        let response = try await fetchSearchResponse(from: searchURL)

        if let exactMatch = response.data.first(where: { deezerTrack in
            deezerTrack.preview.isEmpty == false
            && deezerTrack.title.localizedCaseInsensitiveContains(track.name)
            && (artist.isEmpty || deezerTrack.artist.name.localizedCaseInsensitiveContains(artist))
        }), let url = URL(string: exactMatch.preview) {
            return url
        }

        if let firstPreview = response.data.first(where: { $0.preview.isEmpty == false }),
           let url = URL(string: firstPreview.preview) {
            return url
        }

        throw SpotifyError.noPreviewAvailable
    }

    private func coverURL(from track: Track) -> URL? {
        let coverString = track.album?.coverXL ?? track.album?.coverBig ?? track.album?.coverMedium
        guard let coverString else { return nil }
        return URL(string: coverString)
    }

    private func makeSearchURL(query: String) throws -> URL {
        var components = URLComponents(string: "https://api.deezer.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "10")
        ]

        guard let url = components?.url else { throw SpotifyError.invalidEndpoint }
        return url
    }

    private func fetchSearchResponse(from url: URL) async throws -> SearchResponse {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw SpotifyError.requestFailed("Deezer HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }
}
