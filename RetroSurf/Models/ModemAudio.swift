import AVFoundation

final class ModemHandshakeAudio: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    var duration: TimeInterval {
        guard let url = Bundle.main.url(forResource: "modem-connect", withExtension: "mp3"),
              let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    func play() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "modem-connect", withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.prepareToPlay()
        player.play()
        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === self.player {
            self.player = nil
        }
    }
}