import Foundation

struct AlarmSoundStore {
    func storeSound(from remoteURL: URL, for alarm: Item) async throws -> String {
        let soundName = "spotify-alarm-\(alarm.notificationID).mp3"
        let destinationURL = try soundsDirectory().appending(path: soundName)

        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)

        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw SpotifyError.requestFailed("Preview download HTTP \(httpResponse.statusCode)")
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return soundName
    }

    func removeSound(named soundName: String) {
        guard soundName.isEmpty == false,
              let destinationURL = try? soundsDirectory().appending(path: soundName) else {
            return
        }

        try? FileManager.default.removeItem(at: destinationURL)
    }

    private func soundsDirectory() throws -> URL {
        let libraryURL = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let soundsURL = libraryURL.appending(path: "Sounds", directoryHint: .isDirectory)

        if FileManager.default.fileExists(atPath: soundsURL.path) == false {
            try FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        }

        return soundsURL
    }
}
