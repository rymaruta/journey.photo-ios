import SwiftUI

/// いま描いている1本（指を置いてから離すまで）。**作る画面（`StoryComposerView`）は読まない**——
/// 指が動くたびに公開すると、画面全体が毎回描き直される。読むのは線の層（`StoryDrawingLayer`）だけ。
/// 作る画面は `@State` で**持つだけ**（`@StateObject` にしない・持ち主は購読しない）。
/// `@MainActor` は付けない（`@State` の初期値で作れなくなる・`MusicPreviewPlayer` と同じ）
final class StoryLiveStroke: ObservableObject {
    @Published var stroke: StoryStroke?
}

/// 線の層（写真と文字・札の**間**に敷く・指を受けない）。描いた線と、いま描いている1本を同じ経路で描く
/// （消しゴムの線は、同じ層の中の線だけを消す＝写真は消えない）。
/// 色・太さ・位置は `StoryDrawingGeometry`（焼き込みと同じ決め方）
struct StoryDrawingLayer: View {

    let strokes: [StoryStroke]
    @ObservedObject var live: StoryLiveStroke
    /// 写真の本当の大きさ（文字の札と同じ基準で置く。nil なら枠いっぱいを写真とみなす）
    let imageSize: CGSize?

    var body: some View {
        // 描いている1本は最後に足す（消しゴムなら、その場で描いた線が消えて見える）
        let all = live.stroke.map { strokes + [$0] } ?? strokes
        return Canvas { context, size in
            #if !os(Linux)
            let photo = TextOverlay.filledRect(image: imageSize ?? size, in: size)
            StoryDrawingPaint.draw(all, photo: photo, in: &context)
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if !os(Linux)
/// 線を `Canvas` に描く。**焼き込み（`StoryDrawingPainter`）と同じ命令・同じ太さ・同じ不透明度**
enum StoryDrawingPaint {
    static func draw(_ strokes: [StoryStroke], photo: CGRect, in context: inout GraphicsContext) {
        guard !strokes.isEmpty, photo.width > 0, photo.height > 0 else { return }
        // 消しゴムが写真まで消さないよう、線だけを1枚の層にまとめて描く
        context.drawLayer { layer in
            for stroke in strokes where !stroke.points.isEmpty {
                let width = StoryDrawingGeometry.lineWidth(stroke.width, in: photo.size)
                let points = stroke.points.map { StoryDrawingGeometry.point($0, in: photo) }
                layer.blendMode = stroke.tool == .eraser ? .clear : .normal
                let color = Color(red: Double((stroke.hex >> 16) & 0xFF) / 255,
                                  green: Double((stroke.hex >> 8) & 0xFF) / 255,
                                  blue: Double(stroke.hex & 0xFF) / 255)
                    .opacity(stroke.tool.opacity)
                let shading = GraphicsContext.Shading.color(color)
                if stroke.isDot {
                    // 点を1つだけ打った線は丸い点（長さ 0 の線は端の丸みが出ないことがある）
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: points[0].x - width / 2, y: points[0].y - width / 2,
                                              width: width, height: width))
                    layer.fill(dot, with: shading)
                } else {
                    var path = Path()
                    for op in StoryDrawingGeometry.ops(for: points) {
                        switch op {
                        case .move(let point): path.move(to: point)
                        case .line(let point): path.addLine(to: point)
                        case .quad(let end, let control): path.addQuadCurve(to: end, control: control)
                        }
                    }
                    layer.stroke(path, with: shading,
                                 style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
#endif

/// 描く面（写真の上に全面で重ねる・指を受ける）。**描いている間は、下の文字・札・写真の操作が
/// 一切効かない**——この面が指を全部受けるので、札を誤って掴まない（`StoryPlaceMoveTests` の教訓）。
///
/// 指の動きは `StoryDrawingGeometry` で写真に対する割合の点にし、**1本分を `live` に溜める**。
/// 離したら（打ち切られても）`onCommit` で作る画面へ渡す。上限（`StoryDrawing`）に来たら止めて `onLimit`。
/// 描き方は指だけ。**読み上げでは描けない**ので、説明と「完了」で描かずに進める道を伝える
struct StoryDrawingSurface: View {

    let pen: StoryPen
    /// 写真の本当の大きさ（`StoryDrawingLayer` と同じ基準）
    let imageSize: CGSize?
    /// 上限の判断に使う、いま持っている線
    let drawing: StoryDrawing
    /// 描いている1本の置き場（持ち主が線の層と共有する）
    let live: StoryLiveStroke
    let onCommit: (StoryStroke) -> Void
    let onLimit: () -> Void

    /// 前の点（描く先の座標）。**離したら nil**
    @State private var lastPoint: CGPoint?
    /// 上限の知らせを、この1本で一度だけ出す
    @State private var limitReported = false
    /// 指が触れている間だけ立つ印。**打ち切られても倒れる**——倒れたら描いた分を渡して片付ける
    @GestureState private var touching = false

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($touching) { _, state, _ in state = true }
                        .onChanged { value in extend(to: value.location, in: geometry.size) }
                        .onEnded { value in
                            extend(to: value.location, in: geometry.size)
                            finish()
                        }
                )
                .onChange(of: touching) { _, active in
                    if !active { finish() }
                }
                .accessibilityElement()
                .accessibilityLabel(L("描画エリア", "Drawing area"))
                .accessibilityHint(L("写真に絵や文字を描きます。指でなぞって描くので、読み上げでは描けません。描かずに進むには「完了」を押します",
                                     "Draw on the photo by dragging a finger. This can't be done with VoiceOver. To continue without drawing, choose Done"))
                .accessibilityIdentifier("story.drawSurface")
        }
    }

    /// 指の位置を足す。判断は `StoryStrokeInput.step`（前の点から 1.5pt 以上動いたときだけ足す・上限に来たら止める）
    private func extend(to location: CGPoint, in size: CGSize) {
        let photo = TextOverlay.filledRect(image: imageSize ?? size, in: size)
        switch StoryStrokeInput.step(live: live.stroke, last: lastPoint, location: location, photo: photo,
                                     drawing: drawing) {
        case .begin(let point):
            limitReported = false
            live.stroke = pen.beginStroke(at: point)
            lastPoint = location
        case .append(let point):
            guard var stroke = live.stroke else { return }
            stroke.points.append(point)
            live.stroke = stroke
            lastPoint = location
        case .limit:
            reportLimit()
        case .ignore:
            break
        }
    }

    private func reportLimit() {
        guard !limitReported else { return }
        limitReported = true
        onLimit()
    }

    /// 1本を渡して片付ける（何度呼ばれても1本は1回だけ渡る）
    private func finish() {
        guard let stroke = live.stroke else { return }
        lastPoint = nil
        onCommit(stroke)
        live.stroke = nil
    }
}
