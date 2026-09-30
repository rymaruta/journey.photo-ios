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

    /// 焼き込んだ JPEG。文字が無く写真も合わせていなければ**元のデータをそのまま返す**
    /// （読み書きの往復で画質を落とさない）。
    ///
    /// `framing` は写真の合わせ方（拡大・位置・回し・`PhotoFraming`）。**枠の大きさは元の
    /// 写真のまま**で、その中へ合わせたとおりに描き、届かない所は黒で埋める
    static func burn(_ overlays: [TextOverlay], framing: PhotoFraming = .identity, into data: Data,
                     quality: Double = ImagePreparer.jpegQuality) -> Data {
        let visible = overlays.filter { !$0.isEmpty }
        guard !visible.isEmpty || !framing.isIdentity, let image = UIImage(data: data) else { return data }
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
            if framing.isIdentity {
                image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            } else {
                // 写真の届かない所は黒（作る画面の地と同じ）
                UIColor.black.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
                let place = framing.placement(in: size)
                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: place.center.x, y: place.center.y)
                cg.rotate(by: framing.rotation)
                image.draw(in: CGRect(x: -place.drawSize.width / 2, y: -place.drawSize.height / 2,
                                      width: place.drawSize.width, height: place.drawSize.height))
                cg.restoreGState()
            }
            for overlay in visible {
                draw(overlay, on: size, context: context.cgContext)
            }
        }
    }

    private static func draw(_ overlay: TextOverlay, on size: CGSize, context: CGContext) {
        // **短い辺に対する割合で大きさを決める。** 長辺で決めると、
        // 横長と縦長で同じ指定が別の見え方になる。編集画面と同じ関数を通す
        let fontSize = TextOverlay.fontSize(overlay.size, in: size)
        let (attributes, edge) = attributes(for: overlay, fontSize: fontSize)
        // 場所と曲は印（📍 ♪）を頭に付けて焼く。最後の改行は落とす（`drawnText`）
        let text = overlay.drawnText as NSString
        // **改行した文字は段落として描く**（揃えは段落の揃え）。行の送りは字の組み方
        // （代わりに使われる字・絵文字の高さ）に任せる——編集画面の `Text` と同じ仕組み。
        // 1行は これまでどおり `draw(at:)`（見た目を変えない）
        let multiline = overlay.drawnText.contains("\n")
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = Self.textAlignment(overlay.align)
        func lines(_ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
            var merged = attrs
            merged[.paragraphStyle] = paragraph
            return NSAttributedString(string: overlay.drawnText, attributes: merged)
        }
        let bounds = Self.textBounds(overlay.drawnText, attributes: attributes)
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
        // **縁を先に、塗りを上に。** 負の `strokeWidth`（塗り＋縁を1回で）は縁が字の
        // 輪郭の内側にも食い込み、編集画面（縁を外側にだけ敷く）より字が細く焼ける。
        // 正の幅（縁だけ）で描いてから塗りを重ね、内側の半分を隠す
        if multiline {
            let box = CGRect(origin: origin, size: bounds)
            if let edge {
                lines(edge).draw(with: box, options: .usesLineFragmentOrigin, context: nil)
            }
            lines(attributes).draw(with: box, options: .usesLineFragmentOrigin, context: nil)
        } else {
            if let edge {
                text.draw(at: origin, withAttributes: edge)
            }
            text.draw(at: origin, withAttributes: attributes)
        }
    }

    /// 文字の大きさ（折り返さない）。**焼き込みと、写真の上で打つ画面（`StoryTextTypingView`）が
    /// 同じ測り方を通す**——打つ画面は、これが写真の幅を超えたら縮めて見せて断る
    static func naturalSize(_ overlay: TextOverlay, fontSize: Double) -> CGSize {
        textBounds(overlay.drawnText, attributes: attributes(for: overlay, fontSize: fontSize).fill)
    }

    private static func textBounds(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGSize {
        guard text.contains("\n") else { return (text as NSString).size(withAttributes: attributes) }
        // **測るのは揃えを付けずに**（行の幅は揃えに関係ない）。中央・右の段落を
        // 果てしなく広い枠で測ると、寄せる計算で桁が落ちるおそれがある（6e76bf5 のレビュー）。
        // 揃えは描くときだけ付ける
        // 枠は**有限の広さ**で測る（右から左の文字は揃えの既定が右寄せになり、果てしない枠だと
        // 同じ桁落ちが起きうる・ec4645b のレビュー）。写真の画素より十分広い
        let rect = NSAttributedString(string: text, attributes: attributes).boundingRect(
            with: CGSize(width: 100_000, height: 100_000),
            options: .usesLineFragmentOrigin, context: nil)
        return CGSize(width: rect.width.rounded(.up), height: rect.height.rounded(.up))
    }

    static func textAlignment(_ align: TextOverlay.Align) -> NSTextAlignment {
        switch align {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    /// 塗りの属性と、縁だけの属性（縁が無ければ nil）
    private static func attributes(for overlay: TextOverlay, fontSize: Double)
        -> (fill: [NSAttributedString.Key: Any], edge: [NSAttributedString.Key: Any]?) {
        // 書体（`TextOverlay.Face`・同梱か端末の字）。読めなければゴシック（端末の太字）
        let font = overlay.face.fontName.flatMap { UIFont(name: $0, size: fontSize) }
            ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let fill: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiColor(overlay.drawnHex)]
        guard let edge = edge(for: overlay.style) else { return (fill, nil) }
        // `strokeWidth` は正で「縁だけ」（字の大きさに対する百分率・輪郭の両側に半分ずつ）
        return (fill, [.font: font, .strokeColor: edge.color, .strokeWidth: edge.width])
    }

    /// 縁の色と幅。**黒の見た目には白い縁**（暗い写真の上では縁が無いと消える）。
    /// **縁取りは黒い縁**——幅は白い縁の倍で、どの写真の上でも色が縁で切り離されて読める。
    /// 幅は `Style.edgePercent`（編集画面の `TextOverlayEditor.edged` と同じ値）
    static func edge(for style: TextOverlay.Style) -> (color: UIColor, width: Double)? {
        guard let width = style.edgePercent else { return nil }
        return (style == .dark ? .white : .black, width)
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        return UIColor(red: Double((hex >> 16) & 0xFF) / 255,
                       green: Double((hex >> 8) & 0xFF) / 255,
                       blue: Double(hex & 0xFF) / 255, alpha: 1)
    }
}
