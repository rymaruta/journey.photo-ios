import SwiftUI
import UIKit

/// 旅のトランクを手に取って回す（全画面・メダルとサポーター証と同じ仕組み `MedalCoinView`・2026-10-17）。
///
/// 箱の表＝胴の絵（貼ったラベルごと・`TrunkBoxView` を1枚の絵にしたもの）、裏＝ラベルの無い胴、
/// 側面＝縁の色、上に持ち手。指で横に払うと回り、離すと惰性で少し回って止まる。
/// 「視差効果を減らす」の人には勝手に回さない。読み上げでは「裏返す」で表と裏を替えられる。
struct TrunkSpinViewer: View {
    let model: TrunkModel
    let posts: Int
    let stuck: [TrunkLabel]
    var ownerName: String?
    /// 付けている部品（2026-10-17 次の版）
    var parts: TrunkEquipped = .none

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textures: MedalTextures.Faces?
    @State private var flips = 0

    var body: some View {
        GeometryReader { geo in
            let stage = MedalTextureLayout.coinSide(screenWidth: Double(geo.size.width))
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                MedalCoinView(textures: textures, fallbackImage: "", reduceMotion: reduceMotion, flips: flips,
                              shape: TrunkTextures.shape(model: model, posts: posts, parts: parts))
                    .frame(width: stage, height: stage)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(TrunkText.accessibilityLabel(model: model,
                                                                     labels: TrunkPlacement.layout(stuck, stage: 0).count,
                                                                     tags: TrunkAging.tagCount(posts: posts), equipped: parts))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityAction(named: L("裏返す", "Turn over")) { flips += 1 }
                    .accessibilityIdentifier("trunk.spin.box")
                VStack(spacing: 8) {
                    Text(L("手に取って回す", "Turn it over"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(TrunkText.info(model).name)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                    Text(L("ラベル \(stuck.count) 枚 · 投稿 \(posts)", "\(stuck.count) labels · \(posts) posts"))
                        .font(JPFont.mono(12))
                        .foregroundStyle(WebTheme.muted2)
                    Text(L("指で横に払うと回ります。裏はまだ何も貼っていない面です。",
                           "Swipe sideways to turn it. The back has no labels yet."))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .background { TrunkStyle.stageBackground(centerY: 0.42) }
        .statusBarHidden(true)
        .task {
            guard textures == nil else { return }
            textures = TrunkTextures.make(model: model, posts: posts, stuck: stuck, ownerName: ownerName, parts: parts)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .jpGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .accessibilityLabel(Labels.Common.close)
        .accessibilityIdentifier("trunk.spin.close")
    }
}

/// 回すトランクの絵（表・裏・側面）。画面の部品をそのまま1枚の絵にする（2D と同じ描き方を2度書かない）
@MainActor
enum TrunkTextures {

    /// 箱の形（胴の縦横・厚み・角の丸み・持ち手の色）
    static func shape(model: TrunkModel, posts: Int, parts: TrunkEquipped = .none) -> SpinShape {
        let look = TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts))
        // 付けた持ち手は、その面のいちばん下の色で（3D の持ち手は1色）
        let handle = TrunkFittings(parts).handlePaint?.paint.baseColor ?? look.handle
        return .box(aspect: TrunkLooks.bodyWidth / TrunkLooks.bodyHeight,
                    // 2026-10-17 判断（run 466 の見比べ）: 厚みは横の 0.24（0.34 では箱が細く暗く、正面の絵が見えにくい）
                    depth: 0.24, corner: 16 / TrunkLooks.bodyWidth,
                    handle: SpinRGB(r: handle.r / 255, g: handle.g / 255, b: handle.b / 255))
    }

    static func make(model: TrunkModel, posts: Int, stuck: [TrunkLabel], ownerName: String?,
                     parts: TrunkEquipped = .none) -> MedalTextures.Faces {
        let front = render(TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, bodyOnly: true,
                                        parts: parts))
        let back = render(TrunkBoxView(model: model, posts: posts, stuck: [], ownerName: nil, bodyOnly: true))
        let side = TrunkLooks.sideColor(TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts)))
        let edge = render(Color(trunk: side).frame(width: 8, height: 8))
        return MedalTextures.Faces(front: front, back: back, edge: edge, edgeRepeat: 1)
    }

    private static func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}
