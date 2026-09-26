import Foundation
import UIKit

/// 写真に文字を**焼き込む**。
///
/// **サーバーは位置を持てない。** ストーリーの `caption` は 200字の
/// 文字列1本で（`api-user/src/stories.ts`）、座標も色も入らない。
/// 保存できる形にするには API の変更が要るので、ここでは
/// **投稿する画像そのものに描き込む**——Web 側は何も変えなくても
/// そのまま見える。
///
/// 代わりに**後から文字だけ直すことはできない**（直すなら投稿し直し）。
/// Instagram なども同じ割り切り。
///
/// **EXIF は増やさない。** 元の JPEG は `ImagePreparer` が
/// 「撮影情報も GPS も落ちたことを確かめた」ものなので、ここで描き直した
/// 結果も同じく持たない（`UIGraphicsImageRenderer` は元の付帯情報を
/// 引き継がない）。
enum TextOverlayRenderer {

    /// 焼き込んだ JPEG。文字が無ければ**元のデータをそのまま返す**
    /// （読み書きの往復で画質を落とさない）。
    static func burn(_ overlays: [TextOverlay], into data: Data,
                     quality: Double = ImagePreparer.jpegQuality) -> Data {
        let visible = overlays.filter { !$0.isEmpty }
        guard !visible.isEmpty, let image = UIImage(data: data) else { return data }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return data }

        // 🔴 **倍率は 1 に固定する。** 既定の書式は端末の画面の倍率（3x）を
        // 継ぐので、`size`（＝元の画像の画素数）の3倍の画素で書き出していた。
        // 送る画像が縦横3倍・画素数9倍になり、`ImagePreparer` が抑えた
        // 大きさを台無しにしていた（2026-09-26 のバグ探し）
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: quality) { context in
            image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            for overlay in visible {
                draw(overlay, on: size, context: context.cgContext)
            }
        }
    }

    private static func draw(_ overlay: TextOverlay, on size: CGSize, context: CGContext) {
        // **短い辺に対する割合で大きさを決める。** 長辺で決めると、
        // 横長と縦長で同じ指定が別の見え方になる。編集画面と同じ関数を通す
        let fontSize = TextOverlay.fontSize(overlay.size, in: size)
        let attributes = attributes(for: overlay, fontSize: fontSize)
        // 場所と曲は印（📍 ♪）を頭に付けて焼く
        let text = overlay.displayText as NSString
        let bounds = text.size(withAttributes: attributes)
        // 位置は中心で持っている（0...1 の相対値）。**回しは中心の周りで**
        // （編集画面の `rotationEffect` も中心の周り）
        let center = overlay.center(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: overlay.rotation)
        let origin = CGPoint(x: -bounds.width / 2, y: -bounds.height / 2)

        if overlay.style == .banner {
            // 帯は文字より少し広く取る（角まで文字が届くと読みにくい）
            let padding = fontSize * 0.35
            UIColor.black.withAlphaComponent(0.65).setFill()
            UIRectFill(CGRect(x: origin.x - padding, y: origin.y - padding * 0.5,
                              width: bounds.width + padding * 2,
                              height: bounds.height + padding))
        }
        text.draw(at: origin, withAttributes: attributes)
    }

    private static func attributes(for overlay: TextOverlay,
                                   fontSize: Double) -> [NSAttributedString.Key: Any] {
        // 同梱の書体（明朝・手書き風）。読めなければゴシック（端末の字）
        let font = overlay.face.fontName.flatMap { UIFont(name: $0, size: fontSize) }
            ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let color = uiColor(overlay.ink)
        switch overlay.style {
        case .light, .banner:
            return [.font: font, .foregroundColor: color]
        case .dark:
            // **黒の見た目には白い縁を付ける。** 暗い写真の上では縁が無いと消える。
            // `strokeWidth` は負で「塗り＋縁」（正だと中抜きになる）
            return [.font: font, .foregroundColor: color,
                    .strokeColor: UIColor.white, .strokeWidth: -3.0]
        }
    }

    private static func uiColor(_ ink: TextOverlay.Ink) -> UIColor {
        let hex = ink.hex
        return UIColor(red: Double((hex >> 16) & 0xFF) / 255,
                       green: Double((hex >> 8) & 0xFF) / 255,
                       blue: Double(hex & 0xFF) / 255, alpha: 1)
    }
}
