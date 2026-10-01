import AVFoundation

/// Captures the engine's final mix (after reverb and delay) to a 24-bit WAV file.
/// The tap block runs on an AVFoundation thread, hence the lock around the file.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?

    func start(on node: AVAudioNode, writingTo url: URL) throws {
        let format = node.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let f = try AVAudioFile(forWriting: url, settings: settings,
                                commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        lock.withLock { file = f }
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.write(buffer)
        }
    }

    /// Stops capturing and returns the finished file's location.
    func stop(on node: AVAudioNode) -> URL? {
        node.removeTap(onBus: 0)
        return lock.withLock {
            let url = file?.url
            file?.close()
            file = nil
            return url
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            do { try file?.write(from: buffer) } catch { NSLog("Nocturne: recording write failed: \(error)") }
        }
    }
}
