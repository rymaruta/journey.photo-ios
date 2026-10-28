import Foundation
import UIKit

/// 曲の札の形を描く（2026-10-28・`SongStickerStyle`）。
///
/// 🔴 **焼き込み（`TextOverlayRenderer`）と作る画面（`SongStickerView`）が同じこれで描く。**
/// 寸法は `SongStickerLayout`、書体と測り方はここ。作る画面は同じ絵を画像にして写真の上に置くので、
/// 投稿した写真の札と作る画面の札の位置・大きさがずれない。動く物（棒・レコードの回り）だけ作る画面が
/// 上に重ねて動かす（焼き込みは止まった絵）。
///
/// ジャケットは曲の `artwork`（BGM の行と同じ画像・`SongArtwork`）。**読めないときは ♪ の四角**。
enum SongStickerPainter {

    /// 札に描く曲（曲とジャケットの絵）。ジャケットが無い・読めないときは nil
    struct Art {
        let song: Photo.Song
        let artwork: UIImage?
        /// ジャケットの見分け（画像の控えの鍵）。曲の `artwork` の URL か、読めていなければ空
        var artworkKey: String { artwork == nil ? "" : (song.artwork ?? "") }
    }

    // MARK: - 書体と測り方

    /// 字の書体。曲名＝システムの semibold・歌手＝システムの regular・題字＝明朝（同梱。読めなければ太字）
    static func font(_ role: SongStickerLayout.FontRole, size: Double) -> UIFont {
        switch role {
        case .title: return UIFont.systemFont(ofSize: size, weight: .semibold)
        case .artist: return UIFont.systemFont(ofSize: size, weight: .regular)
        case .mincho:
            return TextOverlay.Face.mincho.fontName.flatMap { UIFont(name: $0, size: size) }
                ?? UIFont.systemFont(ofSize: size, weight: .bold)
        }
    }

    /// 1行の大きさ（折り返さない）。**描くときと同じ書体で測る**
    static func measure(_ text: String, _ role: SongStickerLayout.FontRole, _ size: Double) -> CGSize {
        let measured = (text as NSString).size(withAttributes: [.font: font(role, size: size)])
        return CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
    }

    /// 札の寸法。形のある付けた曲の札でなければ nil（文字の札として描く）
    static func layout(for overlay: TextOverlay, art: Art?, unit: Double) -> SongStickerLayout? {
        guard let art, let style = SongSticker.shape(of: overlay, song: art.song),
              let parts = SongSticker.parts(for: art.song) else { return nil }
        return SongStickerLayout.make(style: style, title: parts.title, artist: parts.artist,
                                      unit: unit, measure: measure)
    }

    // MARK: - 描く

    /// 札を `origin`（札の左上）に描く。`moving` が false なら棒とレコードの盤（作る画面が上に重ねて
    /// 動かす物）を描かない——レコードの影だけは描く（盤を重ねると隠れる）
    static func draw(_ layout: SongStickerLayout, artwork: UIImage?, in cg: CGContext,
                     origin: CGPoint, moving: Bool = true) {
        let ox = Double(origin.x), oy = Double(origin.y)
        func at(_ r: CGRect) -> CGRect { r.offsetBy(dx: ox, dy: oy) }

        // 地（A・B・C）
        if let plate = layout.plate {
            let path = UIBezierPath(roundedRect: at(plate.rect), cornerRadius: plate.radius)
            cg.saveGState()
            if let shadow = plate.shadow { setShadow(shadow, cg) }
            switch plate.kind {
            case .glass: UIColor.black.withAlphaComponent(0.55).setFill()
            case .white: UIColor.white.withAlphaComponent(0.94).setFill()
            }
            path.fill()
            cg.restoreGState()
            if plate.border > 0 {
                let inset = at(plate.rect).insetBy(dx: plate.border / 2, dy: plate.border / 2)
                let edge = UIBezierPath(roundedRect: inset, cornerRadius: max(0, plate.radius - plate.border / 2))
                edge.lineWidth = plate.border
                UIColor.white.withAlphaComponent(plate.borderOpacity).setStroke()
                edge.stroke()
            }
        }

        // レコード（E）。影は盤の形で描く（動かす回も、影は止めたまま下に敷く）
        if let disc = layout.disc {
            if let shadow = layout.discShadow {
                cg.saveGState()
                setShadow(shadow, cg)
                color(0x141414).setFill()
                UIBezierPath(ovalIn: at(disc)).fill()
                cg.restoreGState()
            }
            if moving {
                drawDisc(layout, artwork: artwork, cg: cg, origin: CGPoint(x: ox, y: oy))
            }
        } else if let art = layout.artwork {
            // ジャケット（A・B・D）
            if let shadow = layout.artworkShadow {
                cg.saveGState()
                setShadow(shadow, cg)
                UIColor.black.setFill()
                UIBezierPath(roundedRect: at(art), cornerRadius: layout.artworkRadius).fill()
                cg.restoreGState()
            }
            drawArtwork(artwork, in: at(art), radius: layout.artworkRadius, circle: false,
                        unit: layout.unit, cg: cg)
        }

        // 字
        cg.saveGState()
        if let shadow = layout.textShadow { setShadow(shadow, cg) }
        for run in layout.texts {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font(run.role, size: run.pointSize),
                .foregroundColor: color(run.color).withAlphaComponent(run.opacity),
            ]
            (run.text as NSString).draw(at: at(run.frame).origin, withAttributes: attributes)
        }
        cg.restoreGState()

        // 棒（止まった高さ）
        if moving {
            color(layout.barColor).setFill()
            for bar in layout.bars {
                UIBezierPath(roundedRect: at(bar), cornerRadius: bar.width / 2.5).fill()
            }
        }
    }

    /// レコードの盤（溝・中央の紙・穴）。`origin` は札の左上
    static func drawDisc(_ layout: SongStickerLayout, artwork: UIImage?, cg: CGContext, origin: CGPoint) {
        guard let disc = layout.disc else { return }
        let d = disc.offsetBy(dx: origin.x, dy: origin.y)
        color(0x141414).setFill()
        UIBezierPath(ovalIn: d).fill()
        color(0x1D1D1D).setStroke()
        for r in layout.grooves {
            let ring = UIBezierPath(ovalIn: CGRect(x: d.midX - r, y: d.midY - r, width: r * 2, height: r * 2))
            ring.lineWidth = SongStickerLayout.U.grooveLine * layout.unit
            ring.stroke()
        }
        if let label = layout.artwork {
            drawArtwork(artwork, in: label.offsetBy(dx: origin.x, dy: origin.y), radius: 0, circle: true,
                        unit: layout.unit, cg: cg)
        }
        if let hole = layout.hole {
            UIColor.black.setFill()
            UIBezierPath(ovalIn: hole.offsetBy(dx: origin.x, dy: origin.y)).fill()
        }
    }

    /// ジャケット。読めないときは ♪ の四角（暗い灰の地に白 55% の ♪）
    private static func drawArtwork(_ image: UIImage?, in rect: CGRect, radius: Double, circle: Bool,
                                    unit: Double, cg: CGContext) {
        let shape = circle ? UIBezierPath(ovalIn: rect) : UIBezierPath(roundedRect: rect, cornerRadius: radius)
        cg.saveGState()
        shape.addClip()
        if let image, image.size.width > 0, image.size.height > 0 {
            // 縦横比のまま埋める（ジャケットはふつう正方形。違っても歪めない）
            let scale = max(rect.width / image.size.width, rect.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        } else {
            color(0x2A2A2C).setFill()
            shape.fill()
            let note = "♪" as NSString
            let size = Double(rect.height) * 0.5
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55),
            ]
            let measured = note.size(withAttributes: attributes)
            note.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2),
                      withAttributes: attributes)
        }
        cg.restoreGState()
    }

    private static func setShadow(_ shadow: SongStickerLayout.Shadow, _ cg: CGContext) {
        cg.setShadow(offset: CGSize(width: 0, height: shadow.dy), blur: shadow.blur,
                     color: UIColor.black.withAlphaComponent(shadow.opacity).cgColor)
    }

    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1)
    }

    // MARK: - 作る画面に置く絵（控えつき）

    final class Box {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
    }

    /// 作った絵の控え（札を動かすたびに描き直さない）。数は少ないので上限は小さく
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 24
        return cache
    }()

    private static func key(_ layout: SongStickerLayout, art: Art, part: String) -> NSString {
        let texts = layout.texts.map(\.text).joined(separator: "\u{1F}")
        return "\(part)|\(layout.style.rawValue)|\(Int((layout.unit * 10).rounded()))|\(texts)|\(art.artworkKey)" as NSString
    }

    /// 札の絵（影の余白 `bleed` を四方に足した大きさ）。`moving` が false なら棒とレコードの盤を抜く
    static func image(_ layout: SongStickerLayout, art: Art, moving: Bool) -> UIImage {
        let k = key(layout, art: art, part: moving ? "all" : "base")
        if let hit = cache.object(forKey: k) { return hit.image }
        let b = layout.bleed
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: layout.size.width + b * 2, height: layout.size.height + b * 2), format: format)
        let made = renderer.image { context in
            draw(layout, artwork: art.artwork, in: context.cgContext, origin: CGPoint(x: b, y: b), moving: moving)
        }
        cache.setObject(Box(made), forKey: k)
        return made
    }

    /// レコードの盤だけの絵（盤の大きさ。作る画面が回す）
    static func discImage(_ layout: SongStickerLayout, art: Art) -> UIImage? {
        guard let disc = layout.disc else { return nil }
        let k = key(layout, art: art, part: "disc")
        if let hit = cache.object(forKey: k) { return hit.image }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: disc.size, format: format)
        let made = renderer.image { context in
            drawDisc(layout, artwork: art.artwork, cg: context.cgContext,
                     origin: CGPoint(x: -disc.minX, y: -disc.minY))
        }
        cache.setObject(Box(made), forKey: k)
        return made
    }
}
