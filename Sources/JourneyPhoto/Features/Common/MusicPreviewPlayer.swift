import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine
import AVFoundation

/// 曲の試聴（30秒）。
///
/// **1つだけ鳴らす。** 画面を送るたびに増えると重なって鳴る。
/// アプリ全体で1つのプレイヤーを使い回す。
///
/// **`@MainActor` を付けない。** 付けると `shared` も MainActor に縛られ、
/// `@ObservedObject private var player = MusicPreviewPlayer.shared` という
/// View のプロパティ初期化子（isolation を持たない）から触れなくなる。
/// 触るのは画面からだけなので、実際には常にメインスレッドで動く。
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
        // **`.ambient` にしない。** あれは消音スイッチに従うので、
        // 本人が ▶ を押したのに**マナーモードだと何も鳴らない**
        // ——「壊れている」としか読めない。押したのは本人の意思なので
        // `.playback` にする（他のアプリの音は止まるが、それが普通の作法）
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
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
        // **止めたら場を返す。** 返さないと、止めたあとも他のアプリの
        // 音楽が戻らない（`.playback` で奪ったまま）
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
