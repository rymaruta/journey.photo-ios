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

    var body: some View {
        if story.isVideo, let url = story.imageURL {
            StoryVideo(url: url)
        } else {
            RemoteImage(url: story.imageURL, contentMode: .fit)
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

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            // **既にあるなら作り直さない。** 「見た人」のシートを閉じて
            // 戻るたびに `onAppear` は呼ばれるので、毎回作ると 0:00 に戻る
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                player?.play()
            }
            .onDisappear { player?.pause() }
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

    var body: some View {
        if story.isVideo {
            Image(systemName: "play.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(Color(.secondarySystemBackground), in: Circle())
                .accessibilityLabel(L("動画のストーリー", "Video story"))
        } else {
            RemoteImage(url: story.imageURL)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
        }
    }
}
