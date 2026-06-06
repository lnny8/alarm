import ActivityKit
import Foundation
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
#endif

struct SpotifyAlarmMetadata {
    let title: String
    let previewURL: String
}

#if canImport(AlarmKit)
nonisolated extension SpotifyAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {}
#else
nonisolated extension SpotifyAlarmMetadata: Codable, Hashable, Sendable {}
#endif

@MainActor
struct AlarmKitScheduler {
    func requestAuthorization() async -> String {
        guard #available(iOS 26.0, *) else {
            return "AlarmKit braucht iOS 26 oder neuer."
        }

        guard hasUsageDescription else {
            return "Info.plist fehlt: NSAlarmKitUsageDescription."
        }

        #if canImport(AlarmKit)
        do {
            let state = try await AlarmManager.shared.requestAuthorization()

            switch state {
            case .authorized:
                return ""
            case .denied:
                return "AlarmKit ist deaktiviert. Aktiviere Alarme in den Systemeinstellungen."
            case .notDetermined:
                return "AlarmKit-Berechtigung ist noch offen."
            @unknown default:
                return "Unbekannter AlarmKit-Berechtigungsstatus."
            }
        } catch {
            return formatAlarmKitError(error)
        }
        #else
        return "AlarmKit ist in diesem SDK nicht verfügbar."
        #endif
    }

    func schedule(_ alarm: Item) async -> String {
        guard #available(iOS 26.0, *) else {
            return "AlarmKit braucht iOS 26 oder neuer."
        }

        #if canImport(AlarmKit)
        guard alarm.isEnabled else {
            cancel(alarm)
            return ""
        }

        do {
            try? AlarmManager.shared.cancel(id: alarmKitID(for: alarm))
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else {
                return "AlarmKit ist nicht autorisiert."
            }

            let metadata = SpotifyAlarmMetadata(
                title: alarm.selectedTrackName.isEmpty ? alarm.title : alarm.selectedTrackName,
                previewURL: alarm.selectedPreviewURL
            )

            let attributes = AlarmAttributes(
                presentation: presentation(for: alarm),
                metadata: metadata,
                tintColor: .green
            )

            let configuration = AlarmManager.AlarmConfiguration<SpotifyAlarmMetadata>.alarm(
                schedule: schedule(for: alarm),
                attributes: attributes,
                sound: sound(for: alarm)
            )

            _ = try await AlarmManager.shared.schedule(id: alarmKitID(for: alarm), configuration: configuration)
            return ""
        } catch {
            return formatAlarmKitError(error)
        }
        #else
        return "AlarmKit ist in diesem SDK nicht verfügbar."
        #endif
    }

    func cancel(_ alarm: Item) {
        guard #available(iOS 26.0, *) else { return }

        #if canImport(AlarmKit)
        try? AlarmManager.shared.cancel(id: alarmKitID(for: alarm))
        #endif
    }

    private var hasUsageDescription: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") as? String else {
            return false
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func formatAlarmKitError(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["AlarmKit Fehler", "Domain: \(nsError.domain)", "Code: \(nsError.code)"]

        if nsError.localizedDescription.isEmpty == false {
            parts.append(nsError.localizedDescription)
        }

        if let reason = nsError.localizedFailureReason, reason.isEmpty == false {
            parts.append(reason)
        }

        if let recovery = nsError.localizedRecoverySuggestion, recovery.isEmpty == false {
            parts.append(recovery)
        }

        return parts.joined(separator: " - ")
    }

    private func alarmKitID(for alarm: Item) -> UUID {
        UUID(uuidString: alarm.notificationID) ?? UUID()
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func sound(for alarm: Item) -> AlertConfiguration.AlertSound {
        if alarm.selectedAlarmSoundName.isEmpty == false {
            return .named(alarm.selectedAlarmSoundName)
        }

        return .default
    }

    @available(iOS 26.0, *)
    private func schedule(for alarm: Item) -> Alarm.Schedule {
        if alarm.repeatsDaily {
            let components = Calendar.current.dateComponents([.hour, .minute], from: alarm.timestamp)
            let time = Alarm.Schedule.Relative.Time(hour: components.hour ?? 7, minute: components.minute ?? 0)
            return .relative(.init(time: time, repeats: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])))
        }

        return .fixed(alarm.timestamp)
    }

    @available(iOS 26.0, *)
    private func presentation(for alarm: Item) -> AlarmPresentation {
        let title = LocalizedStringResource(stringLiteral: alarm.title)
        let alert = AlarmPresentation.Alert(title: title)
        return AlarmPresentation(alert: alert)
    }
    #endif
}
