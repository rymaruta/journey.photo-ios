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
    /// どの画面で鳴らしたか。**曲選びで鳴らした曲は全体のバーに出さない**
    /// （`SongPickerText.showsBar`）。止めたら nil
    @Published private(set) var origin: PlaybackOrigin?

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
    /// 場（`.playback`）を持ったまま返していないか。閲覧画面が開いている間に
    /// 止めた曲の場を、閉じたとき（`endStoryViewing`）に返すために覚えておく
    private var sessionHeld = false
    /// 鳴り終わり・途中で途切れたときの見張り。**外さないと積み上がる**
    private var endObservers: [NSObjectProtocol] = []
    /// 開始位置の頭出しの見張り（`startSeeker`）と、それを付けたプレイヤー
    private var startSeeker: (player: AVPlayer, token: Any)?

    /// 音の中断（電話・Siri）の見張り。アプリ全体で1つなので外さない
    private var interruptionObserver: NSObjectProtocol?

    private init() {
        // 🔴 **中断されたら「一時停止」に揃える。** OS はプレイヤーを止めるが、
        // こちらの状態は「再生中」のまま残り、無音なのにミニプレイヤーと ▶ が
        // 再生中の表示のまま・▶ を2回押さないと鳴らなかった
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?["AVAudioSessionInterruptionTypeKey"] as? UInt
            // 1 = 始まり（`AVAudioSession.InterruptionType.began`）
            guard type == 1 else { return }
            self?.markInterrupted()
        }
    }

    /// 中断された（`interruptionNotification` の始まり）。鳴っていれば一時停止の扱いにする
    func markInterrupted() {
        guard playingURL != nil, !isPaused else { return }
        player?.pause()
        isPaused = true
    }

    deinit { removeEndObserver() }

    private func removeEndObserver() {
        for observer in endObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        endObservers = []
        removeStartSeeker()
    }

    private func removeStartSeeker() {
        if let seeker = startSeeker { seeker.player.removeTimeObserver(seeker.token) }
        startSeeker = nil
    }

    func isPlaying(_ url: URL?) -> Bool {
        guard let url else { return false }
        return playingURL == url && !isPaused
    }

    func toggle(_ url: URL?, song: Photo.Song? = nil, origin: PlaybackOrigin = .app) {
        guard let url else { return }
        // **鳴っているときだけ止める。** 一時停止中の同じ曲は ▶ を出しているので、
        // 押したら鳴らす（止めると、▶ を押したのに何も起きない）
        if isPlaying(url) {
            stop()
            return
        }
        start(url, song: song, origin: origin)
    }

    /// 頭から鳴らす（鳴っていても頭出しし直す）。ストーリーの曲に使う——
    /// **同じ曲のストーリーが2本続いても、2本目は頭から**（Web の `itemChanged` と同じ）。
    /// `loops` なら鳴り終わっても止めずに頭から繰り返す（Web の `onEnded`）。
    /// 戻り値は `session`（後始末で「自分の曲か」を見分ける）
    /// `from` は鳴らし始める位置（秒）。繰り返すときもそこへ戻る（Web と同じ）
    @discardableResult
    func play(_ url: URL?, song: Photo.Song? = nil, loops: Bool = false, from startSeconds: Double = 0) -> Int {
        guard let url else { return session }
        start(url, song: song, loops: loops, from: startSeconds)
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

    private func start(_ url: URL, song: Photo.Song?, loops: Bool = false,
                       origin: PlaybackOrigin = .app, from startSeconds: Double = 0) {
        let startTime = CMTime(seconds: max(0, startSeconds), preferredTimescale: 600)
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
        self.origin = origin
        // **30秒で鳴り終わったら自分で止める。**
        //
        // 見張らないと (1) ボタンが「一時停止」のまま固まる
        // (2) `.playback` で奪った場を返さないので、**他のアプリの音楽が
        // 二度と戻らない**——止めるつもりで押した人しか回復できない
        removeEndObserver()
        endObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self, weak player] _ in
            if loops, let player {
                player.seek(to: startTime)
                player.play()
            } else {
                self?.stop()
            }
        })
        // **途中で再生に失敗したときも止める。** そのときは
        // 鳴り終わりの知らせは来ないので、ボタンが「一時停止」のまま固まり、
        // 奪った場（`.playback`）も返さない＝他のアプリの音楽が戻らない。
        // ループ中でも鳴らし直さない（同じ理由でまた落ちるだけ）。
        // ⚠️ 回線が細って止まる（stalled）・読み込みの時点で失敗する（status .failed）
        // はこの知らせを出さないので、ここでは拾えない（実機で未確認）
        endObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        })
        if startSeconds > 0 {
            // 🔴 **読み込む前の頭出しは捨てられることがある**（Web の `seekWhenReady` と同じ心配）。
            // すぐ頭出ししたうえで、鳴り始めたときにまだ頭の近くなら頭出しし直す
            player.seek(to: startTime)
            let token = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
            ) { [weak self, weak player] time in
                guard let player, time.seconds > 0 else { return }
                if time.seconds < startSeconds - 1 { player.seek(to: startTime) }
                DispatchQueue.main.async { self?.removeStartSeeker() }
            }
            startSeeker = (player, token)
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
        origin = nil
        isPaused = false
        guard releaseSession else { return }
        scheduleRelease()
    }

    /// 開いているストーリーの閲覧画面（画面ごとの札）。**1つでも開いている間は
    /// 場を返さない**——閲覧画面の動画も同じ場で鳴っているので、返すとその音が切れる。
    /// 返すのは最後の1つが閉じたとき（`endStoryViewing`）。
    ///
    /// **数ではなく札の集合で持つ。** onAppear が2回来ても同じ札なので増えず、
    /// 対の無い onDisappear は何も抜かない——数だと一度ずれたら永久に場を返さない
    /// （他のアプリの音楽が戻らない）。作り直しで新旧が前後しても札が別なので崩れない
    private var storyViewers: Set<UUID> = []
    var activeStoryViewers: Int { storyViewers.count }

    /// 鳴らしている項目（テスト用に読める。途切れた知らせを送る相手）
    var currentItem: AVPlayerItem? { player?.currentItem }

    /// 返す予約が残っているか（テスト用に読める）
    var hasPendingRelease: Bool { deactivateTask != nil }

    func beginStoryViewing(_ token: UUID) {
        storyViewers.insert(token)
        // 直前に止めた曲の予約が、この画面の動画の音を切らないように
        deactivateTask?.cancel()
        deactivateTask = nil
    }

    /// **`sessionHeld` を見ない。** 閲覧画面の動画（`StoryMedia`）はこの再生器を
    /// 通らずに場を有効にするので、曲を鳴らしていなくても返す（有効でない場を
    /// 返しても害は無い）
    func endStoryViewing(_ token: UUID) {
        storyViewers.remove(token)
        guard storyViewers.isEmpty, player == nil else { return }
        scheduleRelease()
    }

    private func scheduleRelease() {
        // **止めたら場を返す。** 返さないと、止めたあとも他のアプリの
        // 音楽が戻らない（`.playback` で奪ったまま）。
        //
        // **少し待ってから返す。** 止めた直後は `isBusy` で断られることが
        // あり、`try?` で握り潰すと場を占めたままになる
        // 閲覧画面が開いている間は返さない（閉じたときに返す）
        guard activeStoryViewers == 0 else { return }
        deactivateTask?.cancel()
        deactivateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.deactivateTask = nil
            // 待つ間に鳴らし直した・閲覧画面が開いたなら返さない
            guard let self, self.player == nil, self.activeStoryViewers == 0 else { return }
            // 返せなかった（isBusy など）ときは覚えたまま残す（次に止めたとき・
            // 閲覧画面を閉じたときに返し直す）
            do {
                try AVAudioSession.sharedInstance()
                    .setActive(false, options: .notifyOthersOnDeactivation)
                self.sessionHeld = false
            } catch {}
        }
    }
}
