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
    /// 手荷物タグの枠ごとの選び（2026-11-08）。無ければ全部おまかせ
    var tagPicks: [TrunkTagPick] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var textures: MedalTextures.Faces?
    @State private var boxFaces: SpinBoxFaces?
    @State private var flips = 0
    @State private var aim: SpinAim?
    /// 面を描き終えた印と描いた時間（画面写真の試験が待ち、時間を記録する。見本の起動のときだけ読み上げの値に出す）
    @State private var renderMarker = ""

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
                                                                     tags: TrunkLooks.tags(stuck: stuck, posts: posts, picks: tagPicks).count,
                                                                     equipped: parts))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityAction(named: L("裏返す", "Turn over")) { flips += 1 }
                    .accessibilityValue(PreviewSession.userId != nil ? renderMarker : "")
                    .accessibilityIdentifier("trunk.spin.box")
                VStack(spacing: 8) {
                    Text(L("手に取って回す", "Turn it over"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(TrunkText.info(model).name)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                    Text(L("ラベル \(stuck.count) 枚 · 投稿 \(posts)", "\(Plural.count(stuck.count, "label")) · \(Plural.count(posts, "post"))"))
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
        // 測る起動（`-JPPreviewTrunkPerf YES`・Debug のみ）のときだけ: 数の見えない要素（全画面の上でも読めるようここにも置く）
        .overlay(alignment: .bottomLeading) {
            if TrunkPerfMeter.shared.enabled { TrunkPerfProbe() }
        }
        .statusBarHidden(true)
        .task {
            guard textures == nil else { return }
            // 測る起動のときだけ: 回す画面を開いた後の停止の積みを撮れるよう、溜まった見本を空にする（2026-11-11）
            if TrunkPerfMeter.shared.enabled { PerfRecorder.shared.clearSamples() }
            // 描く順を分ける（2026-10-18 見直し）: 正面（ラベルごと）を先に描いて出し、画面の処理を一度返してから
            // 背面・左右・上・底・持ち手を描く。8枚を1度に描くと開いた直後の一瞬が止まる
            let clock = ContinuousClock()
            let started = clock.now
            // 2026-11-11 判断: 同じトランクを 2 回目に開いたら、前に塗った絵を使い回す（`TrunkTextures.cache`）
            let key = TrunkSpinKey(model: model, posts: posts, stuck: stuck, ownerName: ownerName, parts: parts,
                                   wrinkles: wrinkles, tagPicks: tagPicks)
            if let kept = TrunkTextures.kept(key) {
                textures = kept.faces
                boxFaces = kept.box
                renderMarker = TrunkTextures.renderMarker(front: started.duration(to: clock.now), all: started.duration(to: clock.now))
                TrunkPerfMeter.shared.hit("SpinReuse")
                TrunkPerfMeter.shared.mark("SpinReady")
                return
            }
            // まだ塗っていなければ、今までどおりその場で描いて渡す（塗り切るのを待つと、その間は箱の面が空になる。
            // 2026-11-11 run 1003: 主スレッドの外で正面を塗り切るのに 2.6 秒かかり、面が出るのが遅れた）。
            // 塗り切った絵は、トランクの画面を開いたときに先に作っておく（`TrunkTextures.prewarm`）
            textures = TrunkTextures.make(model: model, posts: posts, stuck: stuck, ownerName: ownerName, parts: parts,
                                          wrinkles: wrinkles, tagPicks: tagPicks)
            let frontTook = started.duration(to: clock.now)
            // 1コマ待って正面を画面に出してから残りを描く（`Task.yield` では同じコマのうちに戻りうる）。
            // 待つ間に閉じられたら描かずに抜ける
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            guard !Task.isCancelled else { return }
            boxFaces = TrunkTextures.box(model: model, posts: posts, parts: parts, stuck: stuck, tagPicks: tagPicks)
            // SceneKit が読んで塗った後の絵は、次に開いたときに使い回す
            if let textures, let boxFaces { TrunkTextures.keep(key, faces: textures, box: boxFaces) }
            renderMarker = TrunkTextures.renderMarker(front: frontTook, all: started.duration(to: clock.now))
            TrunkPerfMeter.shared.mark("SpinReady")
        }
        .onDisappear {
            TrunkPerfMeter.shared.mark("SpinGone")
            TrunkPerfMeter.shared.markLater("SpinGoneLater", after: 3)
        }
    }

    /// 向きのボタン（板 TrunkSpin: 4つ並び・高さ 44・#1A1A1A・13pt）
    /// アクセシビリティの大きさでは 2 列 2 段（4 つ並びでは向きの名前が切れる・2026-10-21）
    private var viewButtons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4),
                  spacing: 8) {
            ForEach(Array(TrunkFaces.views.enumerated()), id: \.offset) { i, view in
                Button {
                    aim = SpinAim(id: (aim?.id ?? 0) + 1, yaw: view.yaw, pitch: view.pitch)
                } label: {
                    Text(view.name)
                        .font(JPFont.footnote.weight(.semibold))
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
                    handle: SpinRGB(r: handle.r / 255, g: handle.g / 255, b: handle.b / 255),
                    stitched: TrunkFaces.handleStitched(model))
    }

    /// 最後に開いたトランクの、塗り切った絵（1 つだけ・2026-11-11 判断）。同じトランクを 2 回目に開いたら使い回す。
    /// 約 10.5MB（run 992 の `SpinScene tex_mb`）。メモリが足りないと知らされたら手放す
    private static var cache: (key: TrunkSpinKey, faces: MedalTextures.Faces, box: SpinBoxFaces)?
    private static var watchingMemory = false

    static func kept(_ key: TrunkSpinKey) -> (faces: MedalTextures.Faces, box: SpinBoxFaces)? {
        // 測定専用（`-JPPreviewTrunkDiag spinlazy`・Debug のみ）: 前の作り（使い回さない）
        guard !PreviewSession.trunkDiag.contains("spinlazy"), let cache, cache.key == key else { return nil }
        return (cache.faces, cache.box)
    }

    static func keep(_ key: TrunkSpinKey, faces: MedalTextures.Faces, box: SpinBoxFaces) {
        guard !PreviewSession.trunkDiag.contains("spinlazy") else { return }
        cache = (key, faces, box)
        if !watchingMemory {
            watchingMemory = true
            NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                                   queue: .main) { _ in
                MainActor.assumeIsolated { cache = nil }
            }
        }
    }

    /// 先に作っている途中の合図（同じトランクを 2 度作らない）
    private static var warming: TrunkSpinKey?

    /// 回す画面の絵を、トランクの画面を開いたときに先に作っておく（2026-11-11 判断・run 997 / 1003）。
    /// `ImageRenderer` の絵は後で塗る絵で、回す画面を開いて SceneKit が読んだときに主スレッドで塗られ、開く間に 2.7〜5.2 秒
    /// 止まっていた（積み: `MedalCoinCoordinator.apply` の中の `RB::ImageProvider::wait_phase`）。ここでは主スレッドで組むのは
    /// 1 枚ずつ（間に 1 コマ返す）、塗るのは主スレッドの外（`TrunkStill.settle`）。色・画素は同じ
    static func prewarm(_ key: TrunkSpinKey) async {
        // 測定専用（`-JPPreviewTrunkDiag noprewarm`・Debug のみ・2026-11-11）: 先に作らない（メモリの比べ）
        guard !PreviewSession.trunkDiag.contains("spinlazy"), !PreviewSession.trunkDiag.contains("noprewarm"),
              kept(key) == nil, warming != key else { return }
        warming = key
        defer { if warming == key { warming = nil } }
        // 測る起動のときだけ: 段ごとのメモリ（phys_footprint と user_tag 別・2026-11-11 メモリの増えの内訳）
        TrunkPerfMeter.shared.mark("Warm0Start")
        let faces = Self.make(model: key.model, posts: key.posts, stuck: key.stuck, ownerName: key.ownerName, parts: key.parts,
                         wrinkles: key.wrinkles, tagPicks: key.tagPicks)
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        let sides = Self.box(model: key.model, posts: key.posts, parts: key.parts, stuck: key.stuck, tagPicks: key.tagPicks)
        TrunkPerfMeter.shared.mark("Warm1Built")
        let painted = await TrunkStill.settle([faces.front, faces.back, faces.edge, sides.back, sides.left, sides.right, sides.top,
                                               sides.bottom, sides.handle, sides.clip])
        TrunkPerfMeter.shared.mark("Warm2Painted")
        #if os(iOS)
        if TrunkPerfMeter.shared.enabled {
            // 塗った絵の 1 画素の大きさと合計（貼り絵の大きさの見込み 10.5MB は 4 バイト/画素で数えたもの）
            let images: [CGImage] = painted.compactMap { image -> CGImage? in image?.cgImage }
            let rows = images.map { "\($0.width)x\($0.height)/\($0.bitsPerPixel)bpp" }
            let bytes = images.reduce(0) { total, cg in total + cg.bytesPerRow * cg.height }
            TrunkPerfMeter.shared.note("WarmPx", String(format: "total_mb=%.2f ", Double(bytes) / 1_048_576) + rows.joined(separator: ","))
        }
        #endif
        guard !Task.isCancelled, warming == key, kept(key) == nil else { return }
        keep(key, faces: MedalTextures.Faces(front: painted[0], back: painted[1], edge: painted[2], edgeRepeat: faces.edgeRepeat,
                                             metal: faces.metal),
             box: SpinBoxFaces(back: painted[3], left: painted[4], right: painted[5], top: painted[6], bottom: painted[7],
                               handle: painted[8], clip: painted[9]))
        TrunkPerfMeter.shared.hit("SpinPrewarmed")
        TrunkPerfMeter.shared.mark("Warm3Kept")
        TrunkPerfMeter.shared.markLater("Warm4Later", after: 3)
    }

    /// 使い回す絵を手放す（トランクの画面から戻ったとき）
    static func forget() {
        cache = nil
        warming = nil
    }

    /// 描き終えた印（「faces-ready front=12ms all=85ms」）
    nonisolated static func renderMarker(front: Duration, all: Duration) -> String {
        func ms(_ d: Duration) -> Int {
            let c = d.components
            return Int(c.seconds * 1000 + c.attoseconds / 1_000_000_000_000_000)
        }
        return "faces-ready front=\(ms(front))ms all=\(ms(all))ms"
    }

    /// 表（ラベルごとの胴）と芯の色。**背面は後から**（`box`）。表を先に出す
    static func make(model: TrunkModel, posts: Int, stuck: [TrunkLabel], ownerName: String?,
                     parts: TrunkEquipped = .none, wrinkles: [String: Double] = [:],
                     tagPicks: [TrunkTagPick] = []) -> MedalTextures.Faces {
        // 吊るす物（タグ・チャーム・鍵）も正面に下げる（回しても消さない・#305）。上の面の紐は `box` が描く
        let front = render(TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, bodyOnly: true,
                                        hangsOnFront: true, parts: parts, wrinkles: wrinkles, tagPicks: tagPicks))
        let side = TrunkLooks.sideColor(TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts)))
        let edge = render(Color(trunk: side).frame(width: 8, height: 8))
        // 背面は描き終えるまで縁の色で（白い面を見せない）
        return MedalTextures.Faces(front: front, back: edge, edge: edge, edgeRepeat: 1)
    }

    /// 左右・上・底と持ち手の絵（板 TrunkFaces・正面と同じ古び方と付けた部品）。`stuck` は吊るすタグの紐を上の面に渡すため
    static func box(model: TrunkModel, posts: Int, parts: TrunkEquipped = .none, stuck: [TrunkLabel] = [],
                    tagPicks: [TrunkTagPick] = []) -> SpinBoxFaces {
        let look = TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts))
        let fittings = TrunkFittings(parts)
        // 裏はラベルの無い胴に型押し（板 TrunkFaces の背面。ベルト・桟が回り込み、尾錠と錠前は正面だけ）
        let back = render(TrunkFaceView(model: model, posts: posts, side: .back, parts: parts))
        return SpinBoxFaces(back: back,
                            left: render(TrunkFaceView(model: model, posts: posts, side: .left, parts: parts)),
                            right: render(TrunkFaceView(model: model, posts: posts, side: .right, parts: parts)),
                            top: render(TrunkFaceView(model: model, posts: posts, side: .top, parts: parts,
                                                      hangTags: TrunkLooks.tags(stuck: stuck, posts: posts, picks: tagPicks))),
                            bottom: render(TrunkFaceView(model: model, posts: posts, side: .bottom, parts: parts)),
                            handle: render(TrunkHandleSkin(look: look, fittings: fittings)),
                            clip: render(TrunkHardwareFace(look: look, fittings: fittings, w: 20, h: 14).frame(width: 20, height: 14)))
    }

    private static func render<V: View>(_ view: V, line: Int = #line) -> UIImage? {
        // 測る起動のときだけ、1 枚ずつ描いた時間と画素を数える（`TrunkPerfMeter`・名前は呼んだ行 `TexL<行>`・2026-11-11・測るだけ）
        let name = "TexL\(line)"
        return TrunkPerfMeter.measure(name) { () -> UIImage? in
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = renderer.uiImage
            if TrunkPerfMeter.shared.enabled, let cg = image?.cgImage {
                TrunkPerfMeter.shared.note("Px" + name, "\(cg.width)x\(cg.height) mb=\(String(format: "%.2f", Double(cg.width * cg.height * 4) / 1_048_576))")
            }
            return image
        }
    }
}

/// 立体の持ち手の面に貼る絵（正面の持ち手と同じ塗り・縫い目。形は SceneKit の U の字が受け持つ）。
///
/// **上下どちらに貼られても同じに見える絵にする**（2026-10-18 見直し）。`SCNShape` の前後の面の絵の割り付けは
/// 道（UIKit の y）の向きと逆になりうるが、Linux では確かめられない。縫い目は上下に対称な角丸の線、上の細い光は
/// 絵に入れず SceneKit の光（キーライト）に任せる。塗りの柄（組紐の斜めの縞など）だけは上下で斜めの向きが替わる
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
        }
        .frame(width: 100, height: 36)
    }
}

/// 回す画面の絵を使い回してよいかの合図（絵に効くものだけ・2026-11-11）
struct TrunkSpinKey: Equatable {
    let model: TrunkModel
    let posts: Int
    let stuck: [TrunkLabel]
    let ownerName: String?
    let parts: TrunkEquipped
    let wrinkles: [String: Double]
    let tagPicks: [TrunkTagPick]
}
