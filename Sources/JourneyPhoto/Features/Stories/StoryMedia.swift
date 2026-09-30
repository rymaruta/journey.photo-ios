import SwiftUI
import AVFoundation
import AVKit

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

    var body: some View {
        if story.isVideo, let url = story.imageURL {
            StoryVideo(url: url, isMuted: isMuted, isPaused: isPaused, onEnded: onEnded)
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
    var onEnded: (() -> Void)? = nil

    @State private var player: AVPlayer?
    /// 鳴り終わりの見張り。外さないと画面を閉じたあとも `onEnded` が飛ぶ
    @State private var endObserver: NSObjectProtocol?
    /// 途中で途切れた知らせの見張り（`endObserver` と同じく出るたびに付け直す）
    @State private var failObserver: NSObjectProtocol?
    /// 読み込みの失敗（`status == .failed`）を見る。**失敗は知らせが来ない**ので覗く
    @State private var failWatch: Task<Void, Never>?

    var body: some View {
        VideoPlayer(player: player)
            // **既にあるなら作り直さない。** 「見た人」のシートを閉じて
            // 戻るたびに `onAppear` は呼ばれるので、毎回作ると 0:00 に戻る
            .onAppear {
                if player == nil {
                    let made = AVPlayer(url: url)
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
                if !isPaused { player?.play() }
            }
            .onDisappear {
                player?.pause()
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
            }
            .onChange(of: isMuted) { _, muted in
                player?.isMuted = muted
            }
            .accessibilityLabel(L("動画のストーリー", "Video story"))
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
            RemoteImage(url: story.imageURL)
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

    var body: some View {
        if story.isVideo {
            ZStack {
                WebTheme.surface
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(WebTheme.faint)
            }
            .accessibilityLabel(L("動画のストーリー", "Video story"))
        } else {
            // `.fill` の絵は枠より大きい寸法を申告するので、透明な枠に重ねる
            Color.clear.overlay { RemoteImage(url: story.imageURL) }
                .clipped()
        }
    }
}
