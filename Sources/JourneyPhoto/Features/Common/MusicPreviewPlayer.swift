import Foundation
import AVFoundation

/// 曲の試聴（30秒）。
///
/// **1つだけ鳴らす。** 画面を送るたびに増えると重なって鳴る。
/// アプリ全体で1つのプレイヤーを使い回す。
@MainActor
final class MusicPreviewPlayer: ObservableObject {

    static let shared = MusicPreviewPlayer()

    @Published private(set) var playingURL: URL?

    private var player: AVPlayer?

    private init() {}

    func isPlaying(_ url: URL?) -> Bool {
        guard let url else { return false }
        return playingURL == url
    }

    func toggle(_ url: URL?) {
        guard let url else { return }
        if playingURL == url {
            stop()
            return
        }
        // **他のアプリの音を止めない。** 試聴は添え物なので、
        // `.ambient` にして音楽アプリの再生を奪わない
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        self.player = player
        playingURL = url
        player.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playingURL = nil
    }
}
