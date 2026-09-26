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

    /// 一時停止中か。**止めた（stop）とは別。** 一時停止の間も `playingURL` は
    /// 残るので、これを見ないと他の画面の ▶ が「再生中」のままになる
    @Published private(set) var isPaused = false
    /// 鳴らし始めるたびに増える番号。**「自分が鳴らした曲か」を URL ではなく
    /// これで見分ける**——同じ曲を別の画面が鳴らし直したとき、前の画面の後始末が
    /// 新しい方を止めないように
    private(set) var session = 0

    private var player: AVPlayer?
    /// 場を返す予約。**鳴らし直したら取り消す**——止めた直後（200ms 以内）に
    /// 次の曲を鳴らすと、遅れて届いた `setActive(false)` が新しい曲を止めていた
    private var deactivateTask: Task<Void, Never>?
    /// 場（`.playback`）を持ったまま返していないか。`stop(releaseSession: false)`
    /// のあと、あとで `releaseSessionIfIdle()` で返すために覚えておく
    private var sessionHeld = false
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
        return playingURL == url && !isPaused
    }

    func toggle(_ url: URL?, song: Photo.Song? = nil) {
        guard let url else { return }
        // **鳴っているときだけ止める。** 一時停止中の同じ曲は ▶ を出しているので、
        // 押したら鳴らす（止めると、▶ を押したのに何も起きない）
        if isPlaying(url) {
            stop()
            return
        }
        start(url, song: song)
    }

    /// 頭から鳴らす（鳴っていても頭出しし直す）。ストーリーの曲に使う——
    /// **同じ曲のストーリーが2本続いても、2本目は頭から**（Web の `itemChanged` と同じ）。
    /// `loops` なら鳴り終わっても止めずに頭から繰り返す（Web の `onEnded`）。
    /// 戻り値は `session`（後始末で「自分の曲か」を見分ける）
    @discardableResult
    func play(_ url: URL?, song: Photo.Song? = nil, loops: Bool = false) -> Int {
        guard let url else { return session }
        start(url, song: song, loops: loops)
        return session
    }

    /// 止めずに一時停止する（場は返さない。すぐ `resume()` するため）
    func pause() {
        guard player != nil else { return }
        player?.pause()
        isPaused = true
    }

    /// `pause()` の続きから鳴らす。鳴らしていなければ何もしない
    func resume() {
        guard player != nil else { return }
        player?.play()
        isPaused = false
    }

    /// 消音。**止めない**——消音を解いたとき、映像と同じ位置で鳴っていてほしい
    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    private func start(_ url: URL, song: Photo.Song?, loops: Bool = false) {
        deactivateTask?.cancel()
        deactivateTask = nil
        session += 1
        isPaused = false
        sessionHeld = true
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
        ) { [weak self, weak player] _ in
            if loops, let player {
                player.seek(to: .zero)
                player.play()
            } else {
                self?.stop()
            }
        }
        player.play()
    }

    /// 止める。`releaseSession` が false なら場は返さない——ストーリーの中で
    /// 曲の無い1本に移るとき、場を返すと**その1本の動画の音まで切れる**
    func stop(releaseSession: Bool = true) {
        removeEndObserver()
        player?.pause()
        player = nil
        playingURL = nil
        playingSong = nil
        isPaused = false
        guard releaseSession else {
            // 返す予約が残っていれば取り消す（この後に鳴る動画の音を切らない）
            deactivateTask?.cancel()
            deactivateTask = nil
            return
        }
        scheduleRelease()
    }

    /// 何も鳴らしていないのに場を持ったままなら返す。**ストーリーを閉じたとき用**
    /// ——曲の無い1本へ移ったときは返さずに止めるので、閉じるまで他のアプリの
    /// 音楽が戻らなかった
    func releaseSessionIfIdle() {
        guard player == nil, sessionHeld else { return }
        scheduleRelease()
    }

    private func scheduleRelease() {
        // **止めたら場を返す。** 返さないと、止めたあとも他のアプリの
        // 音楽が戻らない（`.playback` で奪ったまま）。
        //
        // **少し待ってから返す。** 止めた直後は `isBusy` で断られることが
        // あり、`try?` で握り潰すと場を占めたままになる
        deactivateTask?.cancel()
        deactivateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            // 待つ間に鳴らし直していたら返さない
            guard !Task.isCancelled, self?.player == nil else { return }
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
            self?.sessionHeld = false
        }
    }
}
