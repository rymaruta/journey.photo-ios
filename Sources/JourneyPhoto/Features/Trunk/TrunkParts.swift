import SwiftUI

/// 旅のトランクの画面の値（モック Main・Pocket・Reroll・Models・LabelArrived の CSS の値・2026-10-17）。
///
/// 札と格子の地はモックの `#121212`（白 7%・`WebTheme.surface`）、区切り線と副ボタンは `#1A1A1A`。
/// 真鍮は**黒い地の上だけ**（眉ラベル・選んでいる縁・チェック・PRO の札・リンク）。写真の上には置かない。
@MainActor
enum TrunkStyle {
    /// 札・格子の地（#121212）
    static let cell = Color(trunk: TrunkRGBA(0x121212))
    /// 区切り線・副ボタンの地・棒の溝（#1A1A1A）
    static let line = Color(trunk: TrunkRGBA(0x1A1A1A))
    /// 届いた画面の札の地（#201B11・真鍮の字）
    static let chip = Color(trunk: TrunkRGBA(0x201B11))
    /// モックの #999（`text-3`）
    static let faint = WebTheme.text3
    /// モックの #B8B8B8（`text-2`）
    static let muted = WebTheme.text2

    /// 届いた画面・作り直しの地（`radial-gradient(120% 70% at 50% 32%, #17181B 0%, #050505 48%, #000 70%)`）
    static func stageBackground(centerY: Double) -> some View {
        GeometryReader { geo in
            let w = Double(geo.size.width), h = Double(geo.size.height)
            ZStack {
                Color.black
                EllipticalGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0x17181B)), location: 0),
                                           Gradient.Stop(color: Color(trunk: TrunkRGBA(0x050505)), location: 0.48),
                                           Gradient.Stop(color: Color.black, location: 0.70),
                                           Gradient.Stop(color: Color.black, location: 1)],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: w * 1.2 * 2, height: h * 0.7 * 2)
                    .position(x: w / 2, y: h * centerY)
            }
        }
        .ignoresSafeArea()
    }

    /// ラベルの後ろの真鍮の淡い光（`radial-gradient(closest-side, rgba(201,166,107,0.22), …0.05 60%, transparent)`）
    static func glow(width: Double, height: Double) -> some View {
        EllipticalGradient(stops: [Gradient.Stop(color: WebTheme.accent.opacity(0.22), location: 0),
                                   Gradient.Stop(color: WebTheme.accent.opacity(0.05), location: 0.6),
                                   Gradient.Stop(color: Color.clear, location: 1)],
                           center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// PRO の札。**アプリの既存の Pro の札と同じ形**（`OfflineTripCard`・`OfficialSpotView`: 眉ラベルの字・真鍮・
/// 真鍮 60% の細い縁）で、トランクの中でも高さは1通り（2026-10-17 の読み直し・2026-10-16 の Pro の印の件と同じ理由——
/// 画面ごと・大きさごとに印の形を割らない）。モックの 18pt・22pt の2つの札はこれに寄せた
struct TrunkProTag: View {
    var body: some View {
        Text("PRO")
            .jpEyebrow()
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: JPRadius.s)
                .strokeBorder(WebTheme.accent.opacity(0.6), lineWidth: JPStroke.hairline))
            .accessibilityLabel("Pro")
    }
}

/// 手持ちの棒（溝 #1A1A1A・真鍮の伸び・角 3）
struct TrunkPocketBar: View {
    let count: Int
    let limit: Int

    var body: some View {
        let fraction = TrunkText.pocketFraction(count: count, limit: limit)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                TrunkStyle.line
                WebTheme.accent.frame(width: Double(geo.size.width) * fraction)
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}

/// 札の行（モック Main の「手持ちのラベル 28 / 30 ›」: 高さ 52・左右 16・15pt）
struct TrunkMenuRow: View {
    let title: String
    var value: String?
    var chevron = true

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(WebTheme.text)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(JPFont.mono(15, relativeTo: .subheadline))
                    .foregroundStyle(TrunkStyle.muted)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(TrunkStyle.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// 写真の無い画面の主ボタン（真鍮の塗り #B8955A＋墨の字・角 14・高さ 52）と、副ボタン（#1A1A1A・白の字）
struct TrunkButtonFace: View {
    enum Kind { case main, secondary, danger }

    let title: String
    var kind: Kind = .main
    var height: Double = 52
    /// 字の大きさ（既定の文字サイズのとき）。いちばん近い文字の種類（15 → subheadline・17 → body）で出し、
    /// 文字の大きさの設定に付いてくる（2026-10-21 判断: `JPFont.numberStyle` の選び方を使い回す）
    var size: Double = 17

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(title)
            .font(Font.system(JPFont.numberStyle(size: size, relativeTo: .body), weight: .semibold))
            .foregroundStyle(kind == .main ? WebTheme.accentText : (kind == .danger ? WebTheme.danger : WebTheme.text))
            // アクセシビリティの大きさでは折り返す（1行のままでは「はがして手持ちに戻す」が切れる）
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, typeSize.isAccessibilitySize ? 8 : 0)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(kind == .main ? WebTheme.accentFill : TrunkStyle.line, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// ラベルを決まった枠の中に、形の縦横の比を保って描く（格子の札・最近貼ったラベル）
struct TrunkLabelThumb: View {
    let label: TrunkLabel
    let maxWidth: Double
    let maxHeight: Double
    var rot: Double?

    var body: some View {
        let size = TrunkLabelDesign.spec(for: label).shape.fitted(maxWidth: maxWidth, maxHeight: maxHeight)
        TrunkLabelView(label: label, w: size.w, h: size.h, rot: rot)
            .frame(width: maxWidth, height: maxHeight)
    }
}
