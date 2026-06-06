import Foundation
import Observation
import SwiftData

#if canImport(AlarmKit)
import AlarmKit
#endif

@MainActor
@Observable
final class AlarmViewModel {
    let spotifyClient = SpotifyClient()

    var selectedAlarm: Item?
    var permissionMessage = ""
    var activeSourceName = ""
    var activeAlarmTitle = ""
    var isShowingAlarm = false
    var isResolvingTrack = false
    var songPickerAlarm: Item?
    var spotifyPlaylists: [SpotifyPlaylist] = []
    var topTracks: [SpotifyTrack] = []
    var playlistTracks: [SpotifyTrack] = []
    var selectedPickerPlaylist: SpotifyPlaylist?
    var isLoadingSpotifyLibrary = false
    var playlistLoadMessage = ""
    var topTracksLoadMessage = ""

    private var activeSourceURL: URL?
    private let previewAudioPlayer = PreviewAudioPlayer()
    private let deezerPreviewClient = DeezerPreviewClient()
    private let alarmSoundStore = AlarmSoundStore()
    private let alarmKitScheduler = AlarmKitScheduler()
    private var isMonitoringAlarmKit = false

    var isRunningPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    func start(alarms: [Item]) async {
        guard isRunningPreview == false else { return }

        let alarmKitMessage = await alarmKitScheduler.requestAuthorization()
        if alarmKitMessage.isEmpty == false {
            permissionMessage = alarmKitMessage
        }

        startMonitoringAlarmKit(alarms: alarms)
        await scheduleEnabledAlarms(alarms)
    }

    func loginToSpotify() async {
        guard isRunningPreview == false else {
            permissionMessage = "Spotify Login funktioniert nicht in der SwiftUI Preview. Starte die App im Simulator oder auf dem iPhone."
            return
        }

        do {
            try await spotifyClient.login()
            permissionMessage = ""
        } catch {
            permissionMessage = error.localizedDescription
        }
    }

    func openSongPicker(for alarm: Item) {
        guard spotifyClient.isLoggedIn else {
            permissionMessage = "Bitte zuerst mit Spotify verbinden."
            return
        }

        songPickerAlarm = alarm
        Task { await loadSpotifyLibrary() }
    }

    func loadSpotifyLibrary() async {
        guard isLoadingSpotifyLibrary == false else { return }

        isLoadingSpotifyLibrary = true
        playlistLoadMessage = ""
        topTracksLoadMessage = ""
        defer { isLoadingSpotifyLibrary = false }

        do {
            spotifyPlaylists = try await spotifyClient.userPlaylists()
            playlistLoadMessage = spotifyPlaylists.isEmpty ? "Spotify hat keine Playlists zurückgegeben." : "\(spotifyPlaylists.count) Playlists geladen."
        } catch {
            spotifyPlaylists = []
            playlistLoadMessage = error.localizedDescription
        }

        do {
            topTracks = try await spotifyClient.topTracks()
            topTracksLoadMessage = topTracks.isEmpty ? "Spotify hat keine Top Songs zurückgegeben." : "\(topTracks.count) Top Songs geladen. Deezer-Preview wird beim Auswählen gesucht."
        } catch {
            topTracks = []
            topTracksLoadMessage = error.localizedDescription
        }

        permissionMessage = [playlistLoadMessage, topTracksLoadMessage]
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    func selectPlaylist(_ playlist: SpotifyPlaylist) async {
        selectedPickerPlaylist = playlist
        isLoadingSpotifyLibrary = true
        defer { isLoadingSpotifyLibrary = false }

        do {
            playlistTracks = try await spotifyClient.tracks(from: playlist)
            permissionMessage = playlistTracks.isEmpty ? "Diese Playlist enthält keine Songs." : "Deezer-Preview wird beim Auswählen gesucht."
        } catch {
            playlistTracks = []
            permissionMessage = error.localizedDescription
        }
    }

    func selectTrack(_ track: SpotifyTrack, for alarm: Item) async {
        isLoadingSpotifyLibrary = true
        permissionMessage = "Suche Deezer-Preview für \(track.displayName)..."
        defer { isLoadingSpotifyLibrary = false }

        do {
            let deezerPreview = try await deezerPreviewClient.preview(for: track)
            alarmSoundStore.removeSound(named: alarm.selectedAlarmSoundName)
            let soundName = try await alarmSoundStore.storeSound(from: deezerPreview.previewURL, for: alarm)
            alarm.selectedTrackName = track.displayName
            alarm.selectedTrackURL = track.spotifyURL.absoluteString
            alarm.selectedPreviewURL = deezerPreview.previewURL.absoluteString
            alarm.selectedAlarmSoundName = soundName
            alarm.selectedCoverURL = deezerPreview.coverURL?.absoluteString ?? ""
            alarm.lastPlayedSong = track.displayName
            permissionMessage = "Deezer-Preview als AlarmKit-Sound gespeichert."
            await scheduleAlarm(for: alarm)
            songPickerAlarm = nil
        } catch {
            permissionMessage = "Keine Deezer-Preview gefunden: \(error.localizedDescription)"
        }
    }

    func clearSelectedTrack(for alarm: Item) {
        alarmSoundStore.removeSound(named: alarm.selectedAlarmSoundName)
        alarm.selectedTrackName = ""
        alarm.selectedTrackURL = ""
        alarm.selectedPreviewURL = ""
        alarm.selectedAlarmSoundName = ""
        alarm.selectedCoverURL = ""
        Task { await scheduleAlarm(for: alarm) }
        songPickerAlarm = nil
    }

    func addAlarm(modelContext: ModelContext) {
        let nextMorning = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        let alarm = Item(timestamp: nextMorning)

        modelContext.insert(alarm)
        selectedAlarm = alarm
        Task { await scheduleAlarm(for: alarm) }
    }

    func deleteAlarms(offsets: IndexSet, alarms: [Item], modelContext: ModelContext) {
        for index in offsets {
            let alarm = alarms[index]
            removeAlarm(for: alarm)
            alarmSoundStore.removeSound(named: alarm.selectedAlarmSoundName)
            modelContext.delete(alarm)
        }
    }

    func scheduleAlarm(for alarm: Item) async {
        let message = await alarmKitScheduler.schedule(alarm)

        if message.isEmpty == false {
            permissionMessage = message
        }
    }

    func trigger(_ alarm: Item) async {
        guard isResolvingTrack == false else { return }

        isResolvingTrack = true
        defer { isResolvingTrack = false }

        alarm.lastTriggeredAt = Date()

        do {
            let playableTrack: (title: String, previewURL: URL)?

            if alarm.selectedTrackName.isEmpty == false,
               let selectedPreviewURL = URL(string: alarm.selectedPreviewURL) {
                playableTrack = (alarm.selectedTrackName, selectedPreviewURL)
            } else if let track = try await spotifyClient.randomTrack(from: alarm.spotifySources) {
                let previewURL = try await deezerPreviewClient.previewURL(for: track)
                playableTrack = (track.displayName, previewURL)
            } else {
                playableTrack = nil
            }

            guard let playableTrack else {
                throw SpotifyError.noPreviewAvailable
            }

            alarm.lastPlayedSong = playableTrack.title
            activeAlarmTitle = alarm.title
            activeSourceName = playableTrack.title
            activeSourceURL = playableTrack.previewURL

            if alarm.repeatsDaily == false {
                alarm.isEnabled = false
            }

            previewAudioPlayer.play(url: playableTrack.previewURL, title: playableTrack.title)
            isShowingAlarm = true
        } catch {
            permissionMessage = error.localizedDescription
            activeAlarmTitle = alarm.title
            activeSourceName = error.localizedDescription
            activeSourceURL = nil
            isShowingAlarm = true
        }
    }

    func stopAlarmPlayback() {
        previewAudioPlayer.stop()
    }

    private func scheduleEnabledAlarms(_ alarms: [Item]) async {
        for alarm in alarms where alarm.isEnabled {
            await scheduleAlarm(for: alarm)
        }
    }

    private func removeAlarm(for alarm: Item) {
        alarmKitScheduler.cancel(alarm)
    }

    private func startMonitoringAlarmKit(alarms: [Item]) {
        guard isMonitoringAlarmKit == false else { return }
        isMonitoringAlarmKit = true

        Task { [weak self] in
            await self?.monitorAlarmKitUpdates(alarms: alarms)
        }
    }

    private func monitorAlarmKitUpdates(alarms: [Item]) async {
        guard #available(iOS 26.0, *) else { return }

        #if canImport(AlarmKit)
        for await alarmKitAlarms in AlarmManager.shared.alarmUpdates {
            let alertingIDs = Set(alarmKitAlarms.filter { $0.state == .alerting }.map(\.id))
            let now = Date()

            for alarm in alarms where alertingIDs.contains(alarmKitID(for: alarm)) && shouldTrigger(alarm, at: now) {
                await trigger(alarm)
            }
        }
        #endif
    }

    private func alarmKitID(for alarm: Item) -> UUID {
        UUID(uuidString: alarm.notificationID) ?? UUID()
    }

    private func shouldTrigger(_ alarm: Item, at date: Date) -> Bool {
        guard alarm.isEnabled else { return false }

        if let lastTriggeredAt = alarm.lastTriggeredAt,
           Calendar.current.isDate(lastTriggeredAt, inSameDayAs: date) {
            return false
        }

        if alarm.repeatsDaily {
            let alarmComponents = Calendar.current.dateComponents([.hour, .minute], from: alarm.timestamp)
            let nowComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
            return alarmComponents.hour == nowComponents.hour && alarmComponents.minute == nowComponents.minute
        }

        return alarm.timestamp <= date
    }
}
