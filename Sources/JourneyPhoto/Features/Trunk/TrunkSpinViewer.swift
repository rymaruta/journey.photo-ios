import SwiftUI
import UIKit

/// 旅のトランクを手に取って回す（全画面・メダルとサポーター証と同じ仕組み `MedalCoinView`・2026-10-17）。
///
/// 箱の表＝胴の絵（貼ったラベルごと・`TrunkBoxView` を1枚の絵にしたもの）。裏・左右・上・底は
/// 板「旅のトランク」の TrunkFaces（2026-10-18）どおり、正面と同じ素材・古び方・付けた部品で描いた面
/// （`TrunkFaceView`）。上に持ち手の立体。指で払うと回り（縦にも傾く）、離すと惰性で少し回って止まる。
/// 下の4つのボタン（正面・側面・上と背面・底）で、その向きへ回せる（板 TrunkSpin）。
/// 「視差効果を減らす」の人には勝手に回さない。読み上げでは「裏返す」で表と裏を替えられる。
struct TrunkSpinViewer: View {
    let model: TrunkModel
    let posts: Int
    let stuck: [TrunkLabel]
    var ownerName: String?
    /// 付けている部品（2026-10-17 次の版）
    var parts: TrunkEquipped = .none
    /// 動かしてよれたラベル（トランクの画面と同じ見た目に）
    var wrinkles: [String: Double] = [:]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textures: MedalTextures.Faces?
    @State private var boxFaces: SpinBoxFaces?
    @State private var flips = 0
    @State private var aim: SpinAim?

    var body: some View {
        GeometryReader { geo in
            let stage = MedalTextureLayout.coinSide(screenWidth: Double(geo.size.width))
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                MedalCoinView(textures: textures, fallbackImage: "", reduceMotion: reduceMotion, flips: flips,
                              shape: TrunkTextures.shape(model: model, posts: posts, parts: parts), box: boxFaces, aim: aim)
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
                    Text(L("指で回すと、側面・上・底・背面が見えます",
                           "Turn it with your finger to see the sides, top, bottom and back"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                viewButtons
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .background { TrunkStyle.stageBackground(centerY: 0.42) }
        .statusBarHidden(true)
        .task {
            guard textures == nil else { return }
            textures = TrunkTextures.make(model: model, posts: posts, stuck: stuck, ownerName: ownerName, parts: parts,
                                          wrinkles: wrinkles)
            boxFaces = TrunkTextures.box(model: model, posts: posts, parts: parts)
        }
    }

    /// 向きのボタン（板 TrunkSpin: 4つ並び・高さ 44・#1A1A1A・13pt）
    private var viewButtons: some View {
        HStack(spacing: 8) {
            ForEach(Array(TrunkFaces.views.enumerated()), id: \.offset) { i, view in
                Button {
                    aim = SpinAim(id: (aim?.id ?? 0) + 1, yaw: view.yaw, pitch: view.pitch)
                } label: {
                    Text(view.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .background(TrunkStyle.line, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(view.label)
                .accessibilityIdentifier("trunk.spin.view.\(view.id)")
            }
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
                     parts: TrunkEquipped = .none, wrinkles: [String: Double] = [:]) -> MedalTextures.Faces {
        let front = render(TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, bodyOnly: true,
                                        parts: parts, wrinkles: wrinkles))
        // 裏はラベルの無い胴に型押し（板 TrunkFaces の背面。ベルト・桟が回り込み、尾錠と錠前は正面だけ）
        let back = render(TrunkFaceView(model: model, posts: posts, side: .back, parts: parts))
        let side = TrunkLooks.sideColor(TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts)))
        let edge = render(Color(trunk: side).frame(width: 8, height: 8))
        return MedalTextures.Faces(front: front, back: back, edge: edge, edgeRepeat: 1)
    }

    /// 左右・上・底と持ち手の絵（板 TrunkFaces・正面と同じ古び方と付けた部品）
    static func box(model: TrunkModel, posts: Int, parts: TrunkEquipped = .none) -> SpinBoxFaces {
        let look = TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts))
        let fittings = TrunkFittings(parts)
        return SpinBoxFaces(left: render(TrunkFaceView(model: model, posts: posts, side: .left, parts: parts)),
                            right: render(TrunkFaceView(model: model, posts: posts, side: .right, parts: parts)),
                            top: render(TrunkFaceView(model: model, posts: posts, side: .top, parts: parts)),
                            bottom: render(TrunkFaceView(model: model, posts: posts, side: .bottom, parts: parts)),
                            handle: render(TrunkHandleSkin(look: look, fittings: fittings)),
                            clip: render(TrunkHardwareFace(look: look, fittings: fittings, w: 20, h: 14).frame(width: 20, height: 14)))
    }

    private static func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// 立体の持ち手の面に貼る絵（正面の持ち手と同じ塗り・縫い目。形は SceneKit の U の字が受け持つ）
struct TrunkHandleSkin: View {
    let look: TrunkLook
    let fittings: TrunkFittings

    var body: some View {
        ZStack {
            if let part = fittings.handlePaint {
                TrunkPartPaintView(paint: part.paint)
            } else {
                Color(trunk: look.handle)
            }
            if TrunkFaces.handleStitched(look.model) {
                // 縫い目（正面の持ち手の内側の破線と同じ色・刻み）
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(trunk: TrunkRGBA(r: 255, g: 235, b: 200, a: 0.3)),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .padding(4)
            }
            // 上の細い光（正面の持ち手の `inset 0 2px 0 rgba(255,255,255,0.12)`）
            VStack(spacing: 0) {
                Color.white.opacity(0.12).frame(height: 2)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 100, height: 36)
    }
}
