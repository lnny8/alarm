import SwiftUI

struct AlarmRow: View {
    @Bindable var alarm: Item

    let isResolvingTrack: Bool
    let onSelectSong: () -> Void
    let onPlayNow: () -> Void
    let onScheduleChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack() {
                DatePicker(
                    "Uhrzeit",
                    selection: $alarm.timestamp,
                    displayedComponents: [.hourAndMinute]
                )
                .onChange(of: alarm.timestamp) { _, _ in onScheduleChanged() }

                Toggle("Aktiv", isOn: $alarm.isEnabled)
                    .labelsHidden()
                    .onChange(of: alarm.isEnabled) { _, _ in onScheduleChanged() }
            }

            

    
            Button(action: onSelectSong) {

            HStack(spacing: 12) {
                CoverImage(urlString: alarm.selectedCoverURL)

                VStack(alignment: .leading, spacing: 8) {
                    Text(alarm.selectedTrackName.isEmpty ? "Select song" : alarm.selectedTrackName)
                        .foregroundStyle(Color(.black))
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct CoverImage: View {
    let urlString: String

    var body: some View {
        Group {
            if let url = URL(string: urlString), urlString.isEmpty == false {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 56, height: 56)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 56, height: 56)
    }
}

struct SongPickerView: View {
    @Bindable var alarm: Item

    let playlists: [SpotifyPlaylist]
    let topTracks: [SpotifyTrack]
    let playlistTracks: [SpotifyTrack]
    let selectedPlaylist: SpotifyPlaylist?
    let isLoading: Bool
    let playlistLoadMessage: String
    let topTracksLoadMessage: String
    let onRefresh: () -> Void
    let onSelectPlaylist: (SpotifyPlaylist) -> Void
    let onSelectTrack: (SpotifyTrack) -> Void
    let onClearSelection: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Auswahl") {
                    if alarm.selectedTrackName.isEmpty {
                        Label("Zufälliger Song", systemImage: "shuffle")
                    } else {
                        Label(alarm.selectedTrackName, systemImage: "music.note")
                    }

                    Button("Auswahl zurücksetzen", role: .destructive, action: onClearSelection)
                        .disabled(alarm.selectedTrackName.isEmpty)
                }

                Section("Meist gehört") {
                    if topTracksLoadMessage.isEmpty == false {
                        Text(topTracksLoadMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isLoading && topTracks.isEmpty {
                        ProgressView("Songs laden")
                    } else if topTracks.isEmpty {
                        Text("Keine Top Songs gefunden")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topTracks) { track in
                            Button {
                                onSelectTrack(track)
                            } label: {
                                TrackRow(track: track)
                            }
                        }
                    }
                }

                Section("Playlists") {
                    if playlistLoadMessage.isEmpty == false {
                        Text(playlistLoadMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isLoading && playlists.isEmpty {
                        ProgressView("Playlists laden")
                    } else if playlists.isEmpty {
                        Text("Keine Playlists gefunden")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                onSelectPlaylist(playlist)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name)
                                            .font(.body)
                                        Text(playlist.detailText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: selectedPlaylist?.id == playlist.id ? "checkmark.circle.fill" : "chevron.right")
                                        .foregroundStyle(selectedPlaylist?.id == playlist.id ? .green : .secondary)
                                }
                            }
                        }
                    }
                }

                if let selectedPlaylist {
                    Section(selectedPlaylist.name) {
                        if isLoading && playlistTracks.isEmpty {
                            ProgressView("Playlist laden")
                        } else if playlistTracks.isEmpty {
                            Text("Keine Songs in dieser Playlist gefunden")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(playlistTracks) { track in
                                Button {
                                    onSelectTrack(track)
                                } label: {
                                    TrackRow(track: track)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Song auswählen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onRefresh) {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
    }
}

struct TrackRow: View {
    let track: SpotifyTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track.name)
                .font(.body)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                if track.artistNames.isEmpty == false {
                    Text(track.artistNames.joined(separator: ", "))
                }

                Label("Deezer", systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
