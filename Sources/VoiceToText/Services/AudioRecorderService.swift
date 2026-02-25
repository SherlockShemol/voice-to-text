import AVFoundation

final class AudioRecorderService {

    private let lock = NSLock()
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    var isRecording: Bool {
        lock.withLock { recorder?.isRecording ?? false }
    }

    func startRecording() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            guard rec.record() else {
                print("[AudioRecorder] record() returned false")
                return nil
            }
            lock.withLock {
                recorder = rec
                currentURL = url
            }
            return url
        } catch {
            print("[AudioRecorder] Failed to start: \(error)")
            return nil
        }
    }

    func stopRecording() -> URL? {
        lock.withLock {
            guard let rec = recorder, rec.isRecording else { return nil }
            rec.stop()
            recorder = nil
            let url = currentURL
            currentURL = nil
            return url
        }
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
