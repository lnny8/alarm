//
//  Item.swift
//  alarm
//
//  Created by Lenny Muffler on 06.06.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var notificationID: String = UUID().uuidString
    var title: String
    var timestamp: Date
    var isEnabled: Bool
    var repeatsDaily: Bool
    var sourceText: String
    var selectedTrackName: String
    var selectedTrackURL: String
    var selectedPreviewURL: String
    var selectedAlarmSoundName: String
    var selectedCoverURL: String
    var lastPlayedSong: String
    var lastTriggeredAt: Date?

    init(
        notificationID: String = UUID().uuidString,
        title: String = "Morgenwecker",
        timestamp: Date = Date(),
        isEnabled: Bool = true,
        repeatsDaily: Bool = true,
        sourceText: String = "",
        selectedTrackName: String = "",
        selectedTrackURL: String = "",
        selectedPreviewURL: String = "",
        selectedAlarmSoundName: String = "",
        selectedCoverURL: String = "",
        lastPlayedSong: String = "",
        lastTriggeredAt: Date? = nil
    ) {
        self.notificationID = notificationID
        self.title = title
        self.timestamp = timestamp
        self.isEnabled = isEnabled
        self.repeatsDaily = repeatsDaily
        self.sourceText = sourceText
        self.selectedTrackName = selectedTrackName
        self.selectedTrackURL = selectedTrackURL
        self.selectedPreviewURL = selectedPreviewURL
        self.selectedAlarmSoundName = selectedAlarmSoundName
        self.selectedCoverURL = selectedCoverURL
        self.lastPlayedSong = lastPlayedSong
        self.lastTriggeredAt = lastTriggeredAt
    }

    var spotifySources: [SpotifySource] {
        sourceText
            .split(whereSeparator: \ .isNewline)
            .compactMap { SpotifySource(rawValue: String($0)) }
    }
}

struct SpotifySource: Identifiable, Hashable {
    let id = UUID()
    let rawValue: String
    let url: URL?
    let name: String
    let kind: SourceKind
    let spotifyID: String?

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        self.rawValue = trimmed
        self.url = URL(string: trimmed)

        if trimmed.contains("/album/") || trimmed.lowercased().contains("album") {
            kind = .album
        } else {
            kind = .playlist
        }

        spotifyID = SpotifySource.spotifyID(from: trimmed, kind: kind)
        name = SpotifySource.displayName(from: trimmed, kind: kind)
    }

    static func playlist(id: String, name: String, url: URL?) -> SpotifySource {
        SpotifySource(
            rawValue: url?.absoluteString ?? "spotify:playlist:\(id)",
            url: url,
            name: name,
            kind: .playlist,
            spotifyID: id
        )
    }

    private init(rawValue: String, url: URL?, name: String, kind: SourceKind, spotifyID: String?) {
        self.rawValue = rawValue
        self.url = url
        self.name = name
        self.kind = kind
        self.spotifyID = spotifyID
    }

    enum SourceKind: String {
        case playlist = "Playlist"
        case album = "Album"
    }

    private static func displayName(from value: String, kind: SourceKind) -> String {
        if let spotifyID = spotifyID(from: value, kind: kind) {
            return "\(kind.rawValue) \(spotifyID.prefix(8))"
        }

        guard let url = URL(string: value) else { return value }
        return url.host ?? value
    }

    private static func spotifyID(from value: String, kind: SourceKind) -> String? {
        if value.hasPrefix("spotify:\(kind.rawValue.lowercased()):") {
            return value
                .replacingOccurrences(of: "spotify:\(kind.rawValue.lowercased()):", with: "")
                .split(separator: "?")
                .first
                .map(String.init)
        }

        guard let url = URL(string: value) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }

        guard let markerIndex = components.firstIndex(of: kind.rawValue.lowercased()),
              components.indices.contains(markerIndex + 1) else {
            return nil
        }

        return components[markerIndex + 1]
            .split(separator: "?")
            .first
            .map(String.init)
    }
}
