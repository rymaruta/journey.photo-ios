import SwiftUI
import AVFoundation
import UIKit

/// ストーリーの中身。**写真とは限らない。**
///
/// Web 版は写真と動画の両方を受ける（`api-user/src/stories.ts` の
/// `mediaType === "video"`・`StoriesBar` の `accept="image/*,video/mp4,…"`）。
/// アプリは `isVideo` を復号していながらどこでも見ておらず、
/// **誰かが Web から動画を上げると、アプリでは真っ黒のまま**だった
/// （`RemoteImage` が mp4 を画像として読もうとして失敗する）。
struct StoryMedia: View {

    let story: Story
    /// 動画の音を消す（写真には効かない——鳴らしている音が無い）
    var isMuted = false
    /// 止める。長押し・メニュー・シートの間、動画も止まる
    var isPaused = false
    /// 動画が鳴り終わった（写真には来ない。写真は閲覧画面の時計が送る）
    var onEnded: (() -> Void)? = nil
    /// 写真の読み込みが片付いた（出た＝true・出せない＝false）。
    /// 動画には出どころが無いので呼ばない
    var onSettled: ((Bool) -> Void)? = nil
    /// 写真が敷かれた大きさ（縦横比を知る口・`RemoteImage.onLayout`）。動画には来ない
    var onImageLayout: ((CGSize) -> Void)? = nil
    /// 頭から見直す合図（左を押した）。変わったら動画を 0 へ戻す。写真には効かない
    var restartToken = 0
    /// 動画の位置の知らせ（秒・長さ・再生中か）。**写真には来ない**。進行バーを伸ばすのに使う
    var onVideoProgress: ((Double, Double, Bool) -> Void)? = nil

    var body: some View {
        if story.isVideo, let url = story.imageURL {
            StoryVideo(url: url, isMuted: isMuted, isPaused: isPaused, restartToken: restartToken,
                       onEnded: onEnded, onProgress: onVideoProgress)
        } else {
            // **画面いっぱいに敷く**（板は `object-fit: cover`）。はみ出しは
            // 閲覧画面が切る
            RemoteImage(url: story.imageURL, contentMode: .fill, onSettled: onSettled, onLayout: onImageLayout)
                // **URL が読めない1本は「出せない」と知らせる。** `RemoteImage` は URL が
                // 無いと目印を出すだけで `onSettled` を呼ばないので、閲覧画面は絵を待った
                // まま時計を止め、その1本で永久に固まっていた
                .onAppear { if story.imageURL == nil { onSettled?(false) } }
        }
    }
}

/// 動画のストーリー。
///
/// **`AVPlayer` は `onAppear` で作る。** `@State` の初期値として作ると、
/// 画面が作り直されるたびに新しい再生器ができて、前のものが音を出したまま
/// 残ることがある（SwiftUI は body の評価と表示が1対1ではない）。
private struct StoryVideo: View {

    let url: URL
    var isMuted = false
    var isPaused = false
    var restartToken = 0
    var onEnded: (() -> Void)? = nil
    /// 位置の知らせ（秒・長さ・再生中か）。0.5 秒ごとと、止める・再開するとき
    var onProgress: ((Double, Double, Bool) -> Void)? = nil

    @State private var player: AVPlayer?
    /// 位置の見張り（`addPeriodicTimeObserver`）。外さないと画面を閉じたあとも知らせが飛ぶ
    @State private var timeObserver: Any?
    /// 再生の状態（止める・待つ・鳴る）が替わった瞬間の見張り
    @State private var statusObserver: NSKeyValueObservation?
    /// 鳴り終わりの見張り。外さないと画面を閉じたあとも `onEnded` が飛ぶ
    @State private var endObserver: NSObjectProtocol?
    /// 途中で途切れた知らせの見張り（`endObserver` と同じく出るたびに付け直す）
    @State private var failObserver: NSObjectProtocol?
    /// 読み込みの失敗（`status == .failed`）を見る。**失敗は知らせが来ない**ので覗く
    @State private var failWatch: Task<Void, Never>?

    var body: some View {
        // 2026-10-16 判断: **`VideoPlayer` をやめ、層（`AVPlayerLayer`）を `.resizeAspectFill` で敷く**
        // （`StoryVideoSurface`）。`VideoPlayer` は縦横比のまま収める（`.resizeAspect`）ので、
        // 縦長でない動画の上下・左右に黒い帯が出て、写真のように画面いっぱいにならなかった
        // （板 StoryViewer は `object-fit: cover`）。再生の操作盤も出ない（送る・止めるは閲覧画面の指で）
        StoryVideoSurface(player: player)
            // **既にあるなら作り直さない。** 「見た人」のシートを閉じて
            // 戻るたびに `onAppear` は呼ばれるので、毎回作ると 0:00 に戻る
            .onAppear {
                if player == nil {
                    // 閲覧画面が先読みしておいた再生器があれば使う（`StoryVideoPreloader`）
                    let made = StoryVideoPreloader.shared.take(url) ?? AVPlayer(url: url)
                    made.isMuted = isMuted
                    player = made
                }
                // 鳴り終わりで次へ（`MusicPreviewPlayer` と同じ形）。
                // 見張らないと動画のストーリーだけ永久に止まったままになる。
                // 🔴 **見張りは出るたびに付け直す**（プレイヤーを作るときだけではない）。
                // `onDisappear` で外すので、作るときだけだと、画面を離れて戻った後は
                // 最後まで再生しても次へ進まなかった
                // 通知の閉包は main actor の外なので、先に手元へ写してから
                // メインへ戻して呼ぶ
                if endObserver == nil, let item = player?.currentItem {
                    let ended = onEnded
                    endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { _ in
                        Task { @MainActor in ended?() }
                    }
                }
                // 🔴 **読めない動画（圏外・消された）でも次へ進む。** 鳴り終わりしか
                // 見ていなかったので、黒い画面のまま進行バーが止まり、自動で次へ進まなかった
                if failObserver == nil, let item = player?.currentItem {
                    let ended = onEnded
                    failObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemFailedToPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { _ in
                        Task { @MainActor in ended?() }
                    }
                }
                if failWatch == nil, let item = player?.currentItem {
                    let ended = onEnded
                    failWatch = Task { @MainActor in
                        // 読み込みの失敗は知らせが来ないので、しばらく覗く
                        for _ in 0..<20 {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            if Task.isCancelled { return }
                            if item.status == .failed { ended?(); return }
                            if item.status == .readyToPlay { return }
                        }
                    }
                }
                // 進行バーのための位置の知らせ。**出るたびに付け直す**（鳴り終わりの見張りと同じ理由）
                if timeObserver == nil, let player {
                    let report = onProgress
                    timeObserver = player.addPeriodicTimeObserver(
                        forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
                    ) { [weak player] time in
                        let length = player?.currentItem?.duration.seconds ?? 0
                        let seconds = time.seconds
                        // 再生中かは**再生器の状態**（`timeControlStatus`）で見る。見張りを付けた時点の
                        // `isPaused` を写すと、止めた・再開したあとも古いまま。速さ（`rate`）は
                        // 読み込みで詰まって待っている間も 1 のままなので、バーが先へ伸びて戻っていた
                        let playing = player?.timeControlStatus == .playing
                        Task { @MainActor in report?(seconds, length, playing) }
                    }
                }
                // **状態が替わった瞬間にも知らせる。** 周期の見張りだけだと、読み込みで詰まった
                // 瞬間を取りこぼすことがあり（呼ばれた時点でまだ `.playing`・詰まると時刻が
                // 進まず次の知らせが来ない）、再開してからも最大 0.5 秒バーが止まっていた
                if statusObserver == nil, let player {
                    let report = onProgress
                    statusObserver = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
                        let seconds = player.currentTime().seconds
                        let length = player.currentItem?.duration.seconds ?? 0
                        let playing = player.timeControlStatus == .playing
                        Task { @MainActor in report?(seconds, length, playing) }
                    }
                }
                if !isPaused { player?.play() }
            }
            .onDisappear {
                statusObserver?.invalidate()
                statusObserver = nil
                player?.pause()
                if let timeObserver {
                    player?.removeTimeObserver(timeObserver)
                    self.timeObserver = nil
                }
                if let endObserver {
                    NotificationCenter.default.removeObserver(endObserver)
                    self.endObserver = nil
                }
                if let failObserver {
                    NotificationCenter.default.removeObserver(failObserver)
                    self.failObserver = nil
                }
                failWatch?.cancel()
                failWatch = nil
            }
            // 止める・再開するのは外の都合（長押し・メニュー・シート）。
            // ここで `play()` を呼び直すので、`onAppear` 側と二重にならないよう
            // 変化したときだけ
            .onChange(of: isPaused) { _, paused in
                if paused { player?.pause() } else { player?.play() }
                // 止めた・再開した瞬間にバーも止める・動かす（0.5 秒の知らせを待たない）
                if let player {
                    // 再開は**実際に鳴り出してから**伸ばす（まだ読み込み中なら次の知らせで動く）
                    onProgress?(player.currentTime().seconds, player.currentItem?.duration.seconds ?? 0,
                                !paused && player.timeControlStatus == .playing)
                }
            }
            .onChange(of: isMuted) { _, muted in
                player?.isMuted = muted
            }
            // **左を押して頭から見直すときは、動画も 0 へ戻す。** 時計だけ戻して
            // 動画は続きから鳴っていた
            // **読めなかった動画は終わりを知らせ直す。** 見直しで閲覧画面は控えていた終わりを
            // 捨てる。読めない動画は二度と終わりを知らせないので、そのままだと進まなかった
            .onChange(of: restartToken) { _, _ in
                switch StoryPlayback.restartAction(mediaFailed: player?.currentItem?.status == .failed) {
                case .reportEnd:
                    onEnded?()
                case .seekToStart:
                    player?.seek(to: .zero)
                    if !isPaused { player?.play() }
                }
            }
            .accessibilityLabel(L("動画のストーリー", "Video story"))
    }
}

/// 動画を**枠いっぱいに敷く**面（`AVPlayerLayer` を層にした UIView・`.resizeAspectFill`）。
///
/// はみ出しは閲覧画面が切る（写真の `RemoteImage(contentMode: .fill)` と同じ）。
/// **指を受けない**——受けると左右の送る的・長押しまで届かない（`CameraPreview` と同じ理由）
struct StoryVideoSurface: UIViewRepresentable {

    let player: AVPlayer?

    /// 敷き方。**切って埋める**（板の `object-fit: cover`）
    static let gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = Self.gravity
        view.playerLayer.player = player
        return view
    }

    /// 再生器は `onAppear` で作るので、最初は nil で来て後から入る
    func updateUIView(_ uiView: SurfaceView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class SurfaceView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        // swiftlint:disable:next force_cast
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// 次の動画の**先読み**（2026-10-16）。閲覧画面が次の動画の再生器を1つだけ作っておき、
/// その動画を出すとき `StoryVideo` が受け取る——押してから読み始めると、動画の1本目の数秒が黒いまま待った。
///
/// **重くしすぎない。** 持つのは1つだけ（次を頼むと前のは捨てる）・先に読む長さは
/// `bufferSeconds` 秒まで・鳴らさない（作るだけで `play()` しない）。閉じたら捨てる（`clear`）
///
/// **`@MainActor` を付けない**（`MusicPreviewPlayer` と同じ）。触るのは画面（`onAppear`・`.task`）からだけで、
/// 常にメインスレッドで動く
final class StoryVideoPreloader {

    static let shared = StoryVideoPreloader()

    /// 先に読んでおく長さ（秒）。受け取ったら 0（再生器に任せる）へ戻す
    static let bufferSeconds: TimeInterval = 3

    private(set) var url: URL?
    private var player: AVPlayer?

    /// `url` の再生器を作っておく。**同じ URL なら作り直さない**
    func preload(_ url: URL) {
        guard url != self.url else { return }
        clear()
        let made = AVPlayer(url: url)
        made.currentItem?.preferredForwardBufferDuration = Self.bufferSeconds
        self.url = url
        player = made
    }

    /// 先読みしてあった再生器を受け取る（**1回だけ**・別の URL なら nil）
    func take(_ url: URL) -> AVPlayer? {
        guard url == self.url, let player else { return nil }
        self.url = nil
        self.player = nil
        player.currentItem?.preferredForwardBufferDuration = 0
        return player
    }

    func clear() {
        player?.pause()
        player = nil
        url = nil
    }
}

/// ストーリーの輪（一覧の丸いサムネ）。
///
/// **動画は1コマ目を出さない。** 出すには本体を落としてくる必要があり
/// （`AVAssetImageGenerator`）、輪が並ぶ画面で全部の動画を落とすのは重い。
/// 代わりに「動画」と分かる記号を置く——**空の丸を出さない**のが目的。
struct StoryThumb: View {

    let story: Story
    /// 丸の直径（輪の内側に置くときは 52）
    var size: CGFloat = 64

    var body: some View {
        if story.isVideo {
            Image(systemName: "play.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(WebTheme.surface, in: Circle())
                .accessibilityLabel(L("動画のストーリー", "Video story"))
        } else {
            // 🔴 **輪の大きさまで縮めて読む**（2026-10-31 判断・札 #429 アプリ 2）。写真は原寸（長い辺 1920px・
            // 展開すると1枚 約 11MB）で、輪が並ぶと枚数ぶん原寸の画素を持っていた。縦横比を持たないので、
            // 3:1 までの横長・縦長でも輪の写真（54pt）を覆える大きさで読む（`StoryThumbnailSize`）。
            // 読み込み中の輪・失敗の記号・自動の1回の読み直し・0.15 秒の淡い出は `RemoteImage` と同じ
            DownsampledRemoteImage(url: story.imageURL, contentMode: .fill,
                                   assumedRatioLimit: StoryThumbnailSize.assumedRatioLimit,
                                   appearAnimation: .easeOut(duration: 0.15))
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }
}

/// ストーリーの四角いサムネ（反応の画面の 72×112 など）。**枠いっぱいに敷く。**
///
/// 動画は `StoryThumb` と同じく1コマ目を出さず、記号を置く。
/// 大きさと角丸は呼ぶ側が決める
struct StoryPoster: View {

    let story: Story
    /// 枠の大きさまで縮めて読むか（既定は縮める）。false なら元の画像のまま展開する（`RemoteImage`）。
    /// 全画面の枠（リールの面）では縮まらないので、どちらが軽いかを測って呼ぶ側が決める（`StoryReelFace`）
    var downsamples = true

    var body: some View {
        if story.isVideo {
            ZStack {
                WebTheme.surface
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(WebTheme.faint)
            }
            .accessibilityLabel(L("動画のストーリー", "Video story"))
        } else if !downsamples {
            // `.fill` の絵は枠より大きい寸法を申告するので、透明な枠に重ねる（2026-10-31 までの形）
            Color.clear.overlay { RemoteImage(url: story.imageURL) }
                .clipped()
        } else {
            // `.fill` の絵は枠より大きい寸法を申告するので、透明な枠に重ねる。
            // 枠の大きさまで縮めて読む（`StoryThumb` と同じ理由・2026-10-31 札 #429）
            Color.clear.overlay {
                DownsampledRemoteImage(url: story.imageURL, contentMode: .fill,
                                       assumedRatioLimit: StoryThumbnailSize.assumedRatioLimit,
                                       appearAnimation: .easeOut(duration: 0.15))
            }
                .clipped()
        }
    }
}

/// ストーリーの輪・四角いサムネを縮めて読むときの見込み（2026-10-31 判断・札 #429 アプリ 2）。
///
/// ストーリーは縦横比を持たない（`Story` に寸法が無い）ので、**長い辺 ÷ 短い辺がこの比までの写真なら、
/// 横長でも縦長でも枠を覆える**大きさで読む（`DownsampledImageSize.pixels(filling:assumedRatioLimit:)`）。
/// 3 は 3:1 のパノラマまで（縦長の 9:16 は 1.78）。輪の写真（54pt・`StoryRingMetrics.photo`・3倍の画面）なら
/// 長い辺 512px で、原寸（1920px）の約 1/14 の画素になる
enum StoryThumbnailSize {
    static let assumedRatioLimit: CGFloat = 3
}
