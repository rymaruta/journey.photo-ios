import SwiftUI

/// 旅のトランクの画面の値（モック Main・Pocket・Reroll・Models・LabelArrived の CSS の値・2026-10-17）。
///
/// **v2 にそろえた（2026-11-12 判断・1.1.83 の案「トランクと旅の画面のデザイン」00 共通の直し）**: トランクの頁だけ
/// v1 の値（札 #121212・線と副ボタン #1A1A1A・届いた画面の札 #201B11）が残り、ほかの頁と並べると札が浮いて見えた。
/// 札は surface-1（`WebTheme.card`・#0E0E0F）に白 8% の縁（`trunkCard`）、区切り線と棒の溝は hairline（白 8%）、
/// 届いた画面の札は accent-soft（#1C170E・真鍮の字 7.77）。
/// 真鍮は**黒い地の上だけ**（眉ラベル・選んでいる縁・チェック・PRO の札・リンク）。写真の上には置かない。
@MainActor
enum TrunkStyle {
    /// 札・格子の地（v2 の surface-1 #0E0E0F）。縁は `trunkCard` で白 8% を足す
    static let cell = WebTheme.card
    /// 区切り線・棒の溝（v2 の hairline 白 8%）。副ボタンの地には使わない（副ボタンは白 14% の線・`TrunkButtonFace`）
    static let line = WebTheme.hairline
    /// 届いた画面の札の地（v2 の accent-soft #1C170E・真鍮の字）
    static let chip = WebTheme.accentSoft
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

    static let glowStrongCenter = 0.34
    static let glowStrongEdge = 0.09

    /// ラベルの後ろの真鍮の淡い光（`radial-gradient(closest-side, rgba(201,166,107,0.22), …0.05 60%, transparent)`）
    ///
    /// `strong` は節目と箔押しのとき（2026-11-08・案 A）。中心 0.22 → 0.34、すそ 0.05 → 0.09 の一段だけ強くする
    static func glow(width: Double, height: Double, strong: Bool = false) -> some View {
        EllipticalGradient(stops: [Gradient.Stop(color: WebTheme.accent.opacity(strong ? glowStrongCenter : 0.22), location: 0),
                                   Gradient.Stop(color: WebTheme.accent.opacity(strong ? glowStrongEdge : 0.05), location: 0.6),
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

/// トランクの頁のボタン。**v2 の板の2つの高さだけ**（2026-11-12 判断・案の 00 共通の直し）:
/// 主ボタンは 50 の丸（写真の無い画面は真鍮の塗り＋墨、写真のある画面は白 94%＋墨・`JPPillStyle.main(onPhoto:)`）、
/// 副ボタンは 44 の丸で白 14% の線。前は自前の形（高さ 52・角 14・副は #1A1A1A の塗り・48）だった。
/// 面は `jpCapsuleFace`（丸いボタンの値はそこ1つを通る）
struct TrunkButtonFace: View {
    let title: String
    var kind: Kind = .main
    /// 高さを上げたいときだけ（手荷物タグのシートは Mac の実測で 44 が 42.4 に出たので 48・`TrunkTagSheet`）。
    /// 板の高さより低くはしない
    var height: Double?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let main = kind == .main || kind == .mainOnPhoto
        Text(title)
            // アクセシビリティの大きさでは折り返す（1行のままでは「はがして手持ちに戻す」が切れる）
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, typeSize.isAccessibilitySize ? 8 : 0)
            .jpCapsuleFace(font: main ? .callout.weight(.semibold) : JPOutlineSize.regular.font,
                           text: main ? WebTheme.accentText : (kind == .danger ? WebTheme.danger : WebTheme.foreground),
                           fill: kind == .main ? JPPillStyle.accent.fill : (kind == .mainOnPhoto ? JPPillStyle.primary.fill : Color.clear),
                           border: kind == .danger ? JPOutlineTone.danger.border : (main ? Color.clear : WebTheme.line),
                           fullWidth: true, minHeight: max(Self.height(kind), height ?? 0), textInset: nil)
            .contentShape(Capsule())
    }
}

extension TrunkButtonFace {
    enum Kind {
        /// 写真の無い画面の主ボタン（真鍮の塗り＋墨）
        case main
        /// 写真のある画面の主ボタン（白 94%＋墨・ラベルが届いた画面など）
        case mainOnPhoto
        /// 副ボタン（白 14% の線・白の字）
        case secondary
        /// 危険の副ボタン（`WebTheme.danger` の字と線）
        case danger
    }

    /// 高さ（主 50・副 44）
    nonisolated static func height(_ kind: Kind) -> Double {
        switch kind {
        case .main, .mainOnPhoto: return Double(JPHeight.primaryButton)
        case .secondary, .danger: return Double(JPHeight.secondaryButton)
        }
    }
}

extension View {
    /// トランクの札（v2 の surface-1 に白 8% の縁・2026-11-12 判断）。前は #121212 の塗りだけで縁が無かった
    func trunkCard(radius: CGFloat = 14) -> some View {
        self
            .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
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
