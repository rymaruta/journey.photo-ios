import SwiftUI
import UIKit

// Linux では URLSession が別モジュールに居る（`TripBookCardRenderer` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 作る画面の写真の上の曲の札（2026-10-28・`SongStickerStyle`）。
///
/// 🔴 **焼き込みと同じ絵を置く**（`SongStickerPainter.image`）。SwiftUI で組み直すと字の幅や影の付き方が
/// 少しずつ違い、投稿した写真と作る画面で札の位置・大きさがずれる。動く物だけ上に重ねる:
/// 棒の伸び縮みとレコードの回り（モック）。**「動きを減らす」がオンなら動かさない**（止まった絵＝焼き込みと同じ）。
///
/// 大きさは札の寸法（`layout.size`）。影の余白は外へはみ出させ、押せる範囲に入れない。
struct SongStickerView: View {
    let layout: SongStickerLayout
    let art: SongStickerPainter.Art
    /// 動かすか（作る画面で、動きを減らす設定がオフのとき）
    var animated = true

    var body: some View {
        let b = CGFloat(layout.bleed)
        let full = CGSize(width: layout.size.width + b * 2, height: layout.size.height + b * 2)
        ZStack(alignment: .topLeading) {
            Image(uiImage: SongStickerPainter.image(layout, art: art, moving: !animated))
                .resizable()
                .frame(width: full.width, height: full.height)
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    ZStack(alignment: .topLeading) {
                        if let disc = layout.disc, let image = SongStickerPainter.discImage(layout, art: art) {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: disc.width, height: disc.height)
                                .rotationEffect(.radians(SongStickerLayout.discAngle(time: time)))
                                .position(x: disc.midX + b, y: disc.midY + b)
                        }
                        ForEach(Array(layout.bars.enumerated()), id: \.offset) { i, bar in
                            let height = bar.height * CGFloat(SongStickerLayout.barScale(index: i, time: time))
                            RoundedRectangle(cornerRadius: bar.width / 2.5)
                                .fill(StoryCanvas.color(hex: layout.barColor))
                                .frame(width: bar.width, height: height)
                                // 下を揃えて伸び縮み（モックの transform-origin: bottom）
                                .position(x: bar.midX + b, y: bar.maxY + b - height / 2)
                        }
                    }
                    .frame(width: full.width, height: full.height, alignment: .topLeading)
                }
            }
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
        // 影の余白は外へ（押せる範囲と並びは札の大きさ）
        .padding(-b)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 曲のジャケットを読む（2026-10-28・曲の札に描く）。**新しい通信先を足さない**——曲の `artwork`
/// （サーバーが曲と一緒に返す画像・BGM の行と同じ `ProfileSongLine.artworkURL`・https だけ）を読むだけ。
/// 読めないときは nil（札は ♪ の四角）。読んだ絵は覚えておく（投稿の焼き込みでも同じ絵を使う）
enum SongArtwork {

    final class Box {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 8
        return cache
    }()

    static func cached(_ song: Photo.Song?) -> UIImage? {
        guard let song, let url = ProfileSongLine.artworkURL(song) else { return nil }
        return cache.object(forKey: url.absoluteString as NSString)?.image
    }

    static func load(_ song: Photo.Song?) async -> UIImage? {
        guard let song, let url = ProfileSongLine.artworkURL(song) else { return nil }
        if let hit = cache.object(forKey: url.absoluteString as NSString) { return hit.image }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        cache.setObject(Box(image), forKey: url.absoluteString as NSString)
        return image
    }
}
