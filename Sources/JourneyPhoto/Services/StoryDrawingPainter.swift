#if !os(Linux)
import UIKit

/// 描画の線を画像に焼き込む（Core Graphics・2026-11-09）。**Linux の模型には無い口を使うので、
/// 本物の UIKit がある環境だけ**（`SignatureShareCardRenderer` と同じ扱い）。呼ぶ側も `#if !os(Linux)` で囲む。
///
/// 命令・太さ・不透明度は画面の `Canvas`（`StoryDrawingPaint`）と同じもの（`StoryDrawingGeometry`・`StoryPenTool.opacity`）から。
/// **線だけを透明な層にまとめて描いてから写真へ重ねる**——消しゴム（`.clear`）は層の中の線だけを消し、写真は消さない。
/// 位置は `size`（描く先の画素）に対する割合なので、焼き込みの大きさでも動画の書き出しの縮小でも同じ所に出る
enum StoryDrawingPainter {

    /// `size` は描く先の画素数。目に見える線が無ければ何もしない
    static func draw(_ drawing: StoryDrawing, size: CGSize, in cg: CGContext) {
        guard drawing.hasInk, size.width > 0, size.height > 0 else { return }
        let rect = CGRect(origin: .zero, size: size)
        cg.saveGState()
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        for stroke in drawing.strokes where !stroke.points.isEmpty {
            let width = StoryDrawingGeometry.lineWidth(stroke.width, in: size)
            let points = stroke.points.map { StoryDrawingGeometry.point($0, in: rect) }
            cg.setBlendMode(stroke.tool == .eraser ? .clear : .normal)
            let color = UIColor(red: CGFloat((stroke.hex >> 16) & 0xFF) / 255,
                                green: CGFloat((stroke.hex >> 8) & 0xFF) / 255,
                                blue: CGFloat(stroke.hex & 0xFF) / 255,
                                alpha: CGFloat(stroke.tool.opacity)).cgColor
            cg.setStrokeColor(color)
            cg.setFillColor(color)
            cg.setLineWidth(width)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            if stroke.isDot {
                cg.fillEllipse(in: CGRect(x: points[0].x - width / 2, y: points[0].y - width / 2,
                                          width: width, height: width))
            } else {
                for op in StoryDrawingGeometry.ops(for: points) {
                    switch op {
                    case .move(let point): cg.move(to: point)
                    case .line(let point): cg.addLine(to: point)
                    case .quad(let end, let control): cg.addQuadCurve(to: end, control: control)
                    }
                }
                cg.strokePath()
            }
        }
        cg.endTransparencyLayer()
        cg.restoreGState()
    }
}
#endif
