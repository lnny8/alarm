//
//  ContentView.swift
//  alarm
//
//  Created by Lenny Muffler on 06.06.26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp) private var alarms: [Item]

    @State private var viewModel = AlarmViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List(selection: $viewModel.selectedAlarm) {
                spotifySection(viewModel: viewModel)

                Section {
                    if alarms.isEmpty {
                        Text("Kein wecker")
                    } else {
                        ForEach(alarms) { alarm in
                            AlarmRow(
                                alarm: alarm,
                                isResolvingTrack: viewModel.isResolvingTrack,
                                onSelectSong: { viewModel.openSongPicker(for: alarm) },
                                onPlayNow: { Task { await viewModel.trigger(alarm) } },
                                onScheduleChanged: { Task { await viewModel.scheduleAlarm(for: alarm) } }
                            )
                        }
                        .onDelete { offsets in
                            viewModel.deleteAlarms(offsets: offsets, alarms: alarms, modelContext: modelContext)
                        }
                    }
                }
            }
            .navigationTitle("Wecker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.addAlarm(modelContext: modelContext)
                    } label: {
                        Label("Wecker hinzufügen", systemImage: "plus")
                    }
                }
            }
            .task {
                await viewModel.start(alarms: alarms)
            }
            .alert(viewModel.activeAlarmTitle, isPresented: $viewModel.isShowingAlarm) {
                Button("Stoppen", role: .cancel) {
                    viewModel.stopAlarmPlayback()
                }
            } message: {
                Text("Spielt Preview: \(viewModel.activeSourceName)")
            }
            .sheet(item: $viewModel.songPickerAlarm) { alarm in
                SongPickerView(
                    alarm: alarm,
                    playlists: viewModel.spotifyPlaylists,
                    topTracks: viewModel.topTracks,
                    playlistTracks: viewModel.playlistTracks,
                    selectedPlaylist: viewModel.selectedPickerPlaylist,
                    isLoading: viewModel.isLoadingSpotifyLibrary,
                    playlistLoadMessage: viewModel.playlistLoadMessage,
                    topTracksLoadMessage: viewModel.topTracksLoadMessage,
                    onRefresh: { Task { await viewModel.loadSpotifyLibrary() } },
                    onSelectPlaylist: { playlist in Task { await viewModel.selectPlaylist(playlist) } },
                    onSelectTrack: { track in Task { await viewModel.selectTrack(track, for: alarm) } },
                    onClearSelection: { viewModel.clearSelectedTrack(for: alarm) }
                )
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.permissionMessage.isEmpty == false {
                    Text(viewModel.permissionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                }
            }
        }
    }

    private func spotifySection(viewModel: AlarmViewModel) -> some View {
        Section("Spotify") {
            HStack(spacing: 12) {
                Image(systemName: viewModel.spotifyClient.isLoggedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(viewModel.spotifyClient.isLoggedIn ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.spotifyClient.statusText)
                        .font(.headline)
                }

                Spacer()

                if viewModel.spotifyClient.isLoggedIn {
                    Button("Trennen") {
                        viewModel.spotifyClient.logout()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Verbinden") {
                        Task { await viewModel.loginToSpotify() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
