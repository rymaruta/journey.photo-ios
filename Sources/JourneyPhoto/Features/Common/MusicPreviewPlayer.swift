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
    /// いま鳴っている曲。**画面をまたいで操作するために要る**
    /// （`MiniPlayerBar` が題と絵を出す）。URL だけでは何の曲か分からない
    @Published private(set) var playingSong: Photo.Song?

    private var player: AVPlayer?
    /// 鳴り終わりの見張り。**外さないと積み上がる**
    private var endObserver: NSObjectProtocol?

    private init() {}

    deinit { removeEndObserver() }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    func isPlaying(_ url: URL?) -> Bool {
        guard let url else { return false }
        return playingURL == url
    }

    func toggle(_ url: URL?, song: Photo.Song? = nil) {
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
        playingSong = song
        // **30秒で鳴り終わったら自分で止める。**
        //
        // 見張らないと (1) ボタンが「一時停止」のまま固まる
        // (2) `.playback` で奪った場を返さないので、**他のアプリの音楽が
        // 二度と戻らない**——止めるつもりで押した人しか回復できない
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        player.play()
    }

    func stop() {
        removeEndObserver()
        player?.pause()
        player = nil
        playingURL = nil
        playingSong = nil
        // **止めたら場を返す。** 返さないと、止めたあとも他のアプリの
        // 音楽が戻らない（`.playback` で奪ったまま）。
        //
        // **少し待ってから返す。** 止めた直後は `isBusy` で断られることが
        // あり、`try?` で握り潰すと場を占めたままになる
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
