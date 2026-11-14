import Foundation

/// SNS 共有カードの安全域（字・ロゴを置いてよい所）と、写真の上の字の明暗の比。
///
/// 2026-11-14 判断（owner「SNS に載せる、はちゃんとデザイン壊れてないか厳しく確認して。文字などがギリギリの端すぎて SNS で見にくい、みたいなことないように」）:
/// - **どの比でも、字・ロゴ・印・地図は画像の端から短い辺の 6% 以上離す**（1080 幅で 64.8px）。
///   出典: Meta の Stories 広告の目安を写した解説（例 adsuploader.com「Meta ads safe zones」）に、
///   1440×2560 の左右 86px（約 6%）を空ける形がある。フィードの 4:5 も Instagram のプロフィールの格子では
///   3:4 に切られ左右 3.1%（33.75px）が隠れ、X や Threads は角を丸めて見せるので、その外に余りを取る
/// - **9:16 は、上 14%・下 20% の帯に字・ロゴを置かない**（Instagram・Facebook のストーリーの上の進み具合と名前、下の返信欄。
///   TikTok・リールの下の説明文）。上 14%（1920 で 250px 前後）は Meta の Stories 広告の目安として多くの解説が挙げる数。
///   下は 20% と 35%（広告のボタンの分）の両方の数が出回っており、Meta の公式の頁は確かめられていない。
///   普通の投稿のストーリーには広告のボタンが無いので 20% を取る（**目安**）
/// - 帯の型・展示札の型の真鍮の額縁（端から 12・3px）は飾りの線なので、安全域の外に置いてよい
/// - 写真の上の字は、字と背景の明暗の比 4.5:1 以上（WCAG の式・大きい字も 4.5 で見る）。地図の線（部品）は 3:1 以上
///
/// 描く処理（CoreGraphics）から切り離し、Linux でも全部の比で確かめられるようにした（`ShareCardSafeAreaTests`）。
enum ShareCardSafeArea {
    /// 端から空ける割合（短い辺に対して）
    static let edgeFraction: CGFloat = 0.06
    /// 9:16 の上の帯（ストーリーの進み具合・名前）
    static let storyTopFraction: CGFloat = 0.14
    /// 9:16 の下の帯（返信欄・説明文）。目安
    static let storyBottomFraction: CGFloat = 0.20
    /// 写真の上の字の明暗の比の下限
    static let minimumTextContrast: Double = 4.5
    /// 地図の線などの部品の明暗の比の下限
    static let minimumGraphicContrast: Double = 3

    /// 字・ロゴを置いてよい枠（画像の画素の座標・左上が原点）
    static func rect(width: CGFloat, height: CGFloat, isStory: Bool) -> CGRect {
        let edge = min(width, height) * edgeFraction
        let top = max(edge, isStory ? height * storyTopFraction : 0)
        let bottom = max(edge, isStory ? height * storyBottomFraction : 0)
        return CGRect(x: edge, y: top, width: width - edge * 2, height: height - top - bottom)
    }

    static func rect(ratio: SignatureShareCardRenderer.Ratio, width: CGFloat = 1080) -> CGRect {
        rect(width: width, height: width / CGFloat(ratio.rawValue), isStory: ratio == .story)
    }

    /// 枠の外にはみ出した量（どれも 0 なら収まっている）
    struct Overflow: Equatable {
        var left: CGFloat = 0, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0
        var isInside: Bool { max(left, top, right, bottom) <= 0 }
    }

    static func overflow(of box: CGRect, in safe: CGRect) -> Overflow {
        Overflow(left: max(0, safe.minX - box.minX), top: max(0, safe.minY - box.minY),
                 right: max(0, box.maxX - safe.maxX), bottom: max(0, box.maxY - safe.maxY))
    }

    /// 端からの距離（短い辺に対する割合）。左・上・右・下
    static func edgeDistances(of box: CGRect, width: CGFloat, height: CGFloat) -> [CGFloat] {
        let short = min(width, height)
        return [box.minX / short, box.minY / short, (width - box.maxX) / short, (height - box.maxY) / short]
    }

    // MARK: - 明暗の比（WCAG 2.x）

    /// sRGB の 0〜255 の値の相対輝度
    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func channel(_ value: Double) -> Double {
            let c = value / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
