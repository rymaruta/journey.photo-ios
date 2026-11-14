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

    /// SNS のフィードで縦長の画像が切られる比（縦 ÷ 横の逆・幅 ÷ 高さ）。
    ///
    /// 2026-11-14 判断（owner「投稿もレイアウトギリギリすぎて、別の SNS に投稿しようとしたら変になる、みたいなことないよね？」）:
    /// 「投稿」の切り替えでも 9:16 を選べるので、9:16 のカードがフィードに載ると、真ん中で 4:5 に切られる
    /// （Meta の広告の決まり「Instagram フィード 最小の縦横比 400×500」「Facebook フィード 4:5」・
    /// Threads も縦長は 4:5 で見せる目安。Instagram は 2025-05-29 から 3:4 も受けるが、4:5 の方が多く切る）。
    /// run 1296（ea4015e81）で測ると、帯・フェード・表紙・展示札の 9:16 の見出し（ロゴと一文）の上端は 274〜279px で、
    /// 4:5 の切り取り（上下 285px ずつ）で 6〜11px 切れていた。
    /// そこで、4:5 より縦長の比では、字・ロゴを **4:5 の切り取りの内側に、その端から短い辺の 6%** 離して置く。
    /// 9:16 はストーリーの帯（上 14%）より、この線（上 285 + 64.8 = 349.8px）の方が内側になる。下は返信欄の 20%（384px）の方が内側のまま
    static let feedCropAspect: CGFloat = 0.8

    /// フィードの真ん中の切り取りで上下から落ちる高さ（4:5 より縦長でなければ 0）
    static func feedCropInset(width: CGFloat, height: CGFloat) -> CGFloat {
        max(0, (height - width / feedCropAspect) / 2)
    }

    /// 字・ロゴを置いてよい枠（画像の画素の座標・左上が原点）
    static func rect(width: CGFloat, height: CGFloat, isStory: Bool) -> CGRect {
        let edge = min(width, height) * edgeFraction
        let crop = feedCropInset(width: width, height: height)
        let cropEdge = crop > 0 ? crop + edge : 0
        let top = max(edge, isStory ? height * storyTopFraction : 0, cropEdge)
        let bottom = max(edge, isStory ? height * storyBottomFraction : 0, cropEdge)
        return CGRect(x: edge, y: top, width: width - edge * 2, height: height - top - bottom)
    }

    // MARK: - SNS ごとの切り取り（2026-11-14）

    /// SNS が画像を真ん中で切って見せる形（`ShareCardAuditTests` が書き出した画像に当てて測る）。
    /// 出典と確かめた日は各ケースの注記。公式の頁で確かめられないものは「目安」
    enum PlatformCrop: String, CaseIterable {
        /// Instagram・Facebook・Threads のフィード。4:5 より縦長は真ん中で 4:5 に切る
        /// （公式: Meta の広告の決まり Instagram フィード「Minimum Aspect Ratio: 400 x 500」・Facebook フィード「4:5」、2026-11-14 に確かめた。
        /// Threads は目安）
        case feed4x5
        /// Instagram（2025-05-29 から 3:4 を受ける・Mosseri の Threads の投稿を 9to5mac が引用）と、X の縦長の真ん中の切り取り（目安）
        case feed3x4
        /// Instagram のプロフィールの格子（3:4 の小さな見本・真ん中。目安・Buffer などの解説）。
        /// 4:5 と 1:1 は左右を切る。開けば全体が見えるので、字の欠けは「見本だけ」として数を出すだけにする
        case grid3x4

        /// 幅 ÷ 高さ
        var aspect: CGFloat {
            switch self {
            case .feed4x5: return 0.8
            case .feed3x4, .grid3x4: return 0.75
            }
        }

        /// 字が欠けてはいけない切り取りか（フィードは投稿そのもの。格子は小さな見本）
        var mustKeepText: Bool { self != .grid3x4 }

        /// 画像に当てた切り取りの枠。フィードは縦長だけを切り（横長・正方形はそのまま見せる）、格子は横も切る
        func rect(width: CGFloat, height: CGFloat) -> CGRect? {
            let current = width / height
            if current < aspect - 0.0001 {
                let h = width / aspect
                return CGRect(x: 0, y: (height - h) / 2, width: width, height: h)
            }
            guard self == .grid3x4, current > aspect + 0.0001 else { return nil }
            let w = height * aspect
            return CGRect(x: (width - w) / 2, y: 0, width: w, height: height)
        }
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
