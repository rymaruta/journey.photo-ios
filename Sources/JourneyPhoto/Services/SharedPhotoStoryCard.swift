import Foundation
import UIKit

/// 写真を紹介するストーリーの元（札 #541 の ①）。作る画面に渡す
struct StoryShareSeed: Identifiable, Equatable {
    let id = UUID()
    /// 紹介する写真の id（送るときに `sharedPhotoId` として添える）
    let photoId: String
    /// 札を描いた 1080×1920 の JPEG（`SharedPhotoStoryCard.render`）
    let cardData: Data
}

/// **写真を紹介するストーリーの絵**（2026-11-11・札 #541 の ①「写真をストーリーで紹介」・案の模型 1-D / 1-E）。
///
/// 9:16 の地に、写真をぼかして暗くしたもの（`SharedPhotoStoryBackdrop`・2026-11-14 に作り直した）を敷き、真ん中より少し上に**写真の札**を −2° 傾けて置く。
/// 札は写真の下に白（primary #F0F0F0）の帯を持ち、持ち主の顔（24 → 64px）・@ユーザー名（墨・太字）・題（墨 #3a3d3f）を出す。
/// 写真の上に置く字は無い（帯の上だけ・CLAUDE.md の「写真の上は白だけ」に当たらない）。
///
/// 2026-11-11 判断: **札は絵に焼き込む**（作る画面で動かせる札にはしない）。動かせる札にすると、
/// 写真の札を他の札（文字・曲）と同じ重ね順・焼き込みの仕組みに足すことになり、作る画面の作り（3000 行）に
/// 深く入る。見る人の「写真を見る」の位置（`buttonCenterY`）を絵の札に合わせられるのも焼き込みの利点。
/// 文字・曲・スタンプは今までどおり上に足せる。
///
/// 寸法の決め方（`cardRect`）は画面を持たないので Linux の試験で見る。描くのは Mac / 実機だけ。
enum SharedPhotoStoryCard {

    /// 書き出す大きさ（ストーリーの 9:16）
    static let canvas = CGSize(width: 1080, height: 1920)
    /// 札の幅（模型の 240 / 390）
    static let cardWidth: Double = 660
    /// 写真の縦横の幅（横長は 4:3 まで、縦長は 4:5 まで。それより細長い写真は札の中で切る）
    static let minPhotoAspect: Double = 4.0 / 5.0
    static let maxPhotoAspect: Double = 4.0 / 3.0
    /// 札の下の白い帯の高さ（模型の 48 / 240 × 660）
    static let footerHeight: Double = 132
    /// 札の角（模型の 14 / 240 × 660）
    static let cornerRadius: Double = 38
    /// 札の傾き（模型の −2°）
    static let tiltDegrees: Double = -2
    /// 札の中心の高さ（地の上から）。真ん中より少し上——下に「写真を見る」と返信欄が来る
    static let cardCenterY: Double = 0.42

    /// 札の写真の部分（傾ける前・地の座標）
    static func photoRect(imageSize: CGSize) -> CGRect {
        let aspect = imageSize.height > 0 ? Double(imageSize.width / imageSize.height) : 1
        let clamped = min(max(aspect, minPhotoAspect), maxPhotoAspect)
        let photoHeight = (cardWidth / clamped).rounded()
        let total = photoHeight + footerHeight
        let top = (Double(canvas.height) * cardCenterY - total / 2).rounded()
        return CGRect(x: (Double(canvas.width) - cardWidth) / 2, y: top, width: cardWidth, height: photoHeight)
    }

    /// 札全体（写真＋白い帯・傾ける前）
    static func cardRect(imageSize: CGSize) -> CGRect {
        let photo = photoRect(imageSize: imageSize)
        return CGRect(x: photo.minX, y: photo.minY, width: photo.width, height: photo.height + footerHeight)
    }

    /// 見る画面の「写真を見る」の中心の高さ（写真の枠の高さに対する割合）。**いちばん縦長の札の下より下**に置く
    /// （札の下端 0.42 + (825 + 132) / 2 / 1920 ≒ 0.67 → 余白を見て 0.75）
    static let buttonCenterY: Double = 0.75

    /// 写真を地いっぱいに敷く枠（はみ出たぶんは切れる）
    static func fillRect(imageSize: CGSize, in box: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = max(box.width / imageSize.width, box.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// 帯の1行目（「@ユーザー名」・無ければ表示名）
    static func handleLine(username: String?, displayName: String) -> String {
        if let username, !username.isEmpty { return "@" + username }
        return displayName
    }

    /// 帯の2行目（題・無ければ撮影地・どちらも無ければ空）
    static func titleLine(title: String?, location: String?) -> String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 札を描いて JPEG にする。写真が読めなければ nil（作る画面を開かない）。
    /// **EXIF・位置は持たない**（`UIGraphicsImageRenderer` は元の付帯情報を引き継がない）
    static func render(photo: Data, avatar: Data?, handle: String, title: String, quality: Double = 0.9) -> Data? {
        guard let image = UIImage(data: photo) else { return nil }
        let size = canvas
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let avatarImage = avatar.flatMap { UIImage(data: $0) }
        return renderer.jpegData(withCompressionQuality: quality) { context in
            let full = CGRect(origin: .zero, size: size)
            UIColor.black.setFill()
            context.fill(full)
            let card = cardRect(imageSize: image.size)
            let photoBox = photoRect(imageSize: image.size)
            let cg = context.cgContext
            drawBackdrop(image, card: card, in: full, context: cg)
            cg.saveGState()
            // 札の中心で回す
            cg.translateBy(x: card.midX, y: card.midY)
            cg.rotate(by: tiltDegrees * .pi / 180)
            cg.translateBy(x: -card.midX, y: -card.midY)
            // 影（模型の 0 18px 50px 黒 50%）
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 50), blur: 140,
                         color: UIColor.black.withAlphaComponent(0.5).cgColor)
            UIColor(red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: card, cornerRadius: cornerRadius).fill()
            cg.restoreGState()
            // 札の中（角で切る）
            cg.saveGState()
            UIBezierPath(roundedRect: card, cornerRadius: cornerRadius).addClip()
            let shown = image.preparingThumbnail(of: fillRect(imageSize: image.size, in: photoBox).size) ?? image
            shown.draw(in: fillRect(imageSize: image.size, in: photoBox))
            drawFooter(in: CGRect(x: card.minX, y: photoBox.maxY, width: card.width, height: footerHeight),
                       avatar: avatarImage, handle: handle, title: title, context: cg)
            cg.restoreGState()
            cg.restoreGState()
        }
    }

    /// 白い帯（顔 64・@名 36 の太字・題 32）。墨の字（白の上の字・`accentText`）
    private static func drawFooter(in rect: CGRect, avatar: UIImage?, handle: String, title: String, context: CGContext) {
        let pad: Double = 32
        let face: Double = 64
        let faceRect = CGRect(x: rect.minX + pad, y: rect.midY - face / 2, width: face, height: face)
        // 顔の丸で切るのはこの中だけ（切ったまま字を描くと字が消える）
        context.saveGState()
        drawCircle(avatar, in: faceRect)
        context.restoreGState()
        let ink = UIColor(red: 0x07 / 255, green: 0x09 / 255, blue: 0x0A / 255, alpha: 1)
        let soft = UIColor(red: 0x3A / 255, green: 0x3D / 255, blue: 0x3F / 255, alpha: 1)
        let textX = faceRect.maxX + 22
        let width = rect.maxX - pad - textX
        let hasTitle = !title.isEmpty
        let handleFont = UIFont.systemFont(ofSize: 34, weight: .semibold)
        let titleFont = UIFont.systemFont(ofSize: 30, weight: .regular)
        let handleY = hasTitle ? rect.midY - 42 : rect.midY - 22
        NSAttributedString(string: handle, attributes: [.font: handleFont, .foregroundColor: ink])
            .draw(with: CGRect(x: textX, y: handleY, width: width, height: 44),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        if hasTitle {
            NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: soft])
                .draw(with: CGRect(x: textX, y: rect.midY + 4, width: width, height: 40),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
    }
}

extension SharedPhotoStoryCard {
    /// 丸い顔を描く（読めなければ灰の丸）。**呼ぶ側が状態を保存・戻す**（丸で切るため）
    fileprivate static func drawCircle(_ image: UIImage?, in rect: CGRect) {
        let path = UIBezierPath(ovalIn: rect)
        if let image {
            path.addClip()
            image.draw(in: fillRect(imageSize: image.size, in: rect))
        } else {
            UIColor(red: 0x9A / 255, green: 0x9A / 255, blue: 0x9A / 255, alpha: 1).setFill()
            path.fill()
        }
    }
}

// MARK: - 地（2026-11-14）

/// **写真を紹介するストーリーの地**（2026-11-14 owner「投稿した後にストーリーに載せるの背景寂しいね」）。
///
/// 前は、24px に縮めた写真を引き伸ばして、黒 45% を一様に重ねていた。色が濁った暗い一枚の面になり、
/// 写真の札だけが浮いて見えた（Mac run 1268 の 120f: 写真の色も形も消えた灰色の一枚の面）。
///
/// 2026-11-14 判断: インスタの「投稿をストーリーに」と同じく**写真から色を引いた地**のまま、厚みを足す。
/// 1. 写真を本物のぼかし（高さの 3.5%）で敷き、彩度 1.35 で色を残す（形がうっすら見え、写真の続きに見える）
/// 2. 札の後ろに白い光（10% → 0）を敷く（展示の札に光を当てる。暗い写真でも地が真っ黒の板にならない）
/// 3. 黒を重ねる量は**帯ごとに、その帯のいちばん明るい所を測って**決める。上（見る画面の進み線と名前）と
///    下（「写真を見る」・ひとこと・返信欄）は白の字との比 4.5 以上、真ん中（札の周り）は 3 以上。
///    暗い写真には少しだけ（一様に 45% だと暗い写真ほど沈む）
/// 4. 四隅を黒 35% へ落とす（周辺減光）。目が札へ行く
///
/// 色の決まり: 地は写真から引いた色と白・黒だけ。真鍮は置かない（写真の上・CLAUDE.md）。
/// 量の計算（`shades`）は画面を持たないので Linux の試験で見る。描くのは Mac / 実機だけ。
enum SharedPhotoStoryBackdrop {
    /// ぼかしの半径（縮めた写真の高さに対する割合）
    static let blurRadiusFraction: Double = 0.035
    /// 縮める長い辺（ぼかしを軽くする・地は大きく引き伸ばすので足りる）
    static let blurLongEdge: CGFloat = 720
    /// 彩度（ぼかして暗くしても色が残るように）
    static let saturation: Double = 1.35
    /// 札の後ろの白い光の濃さと、半径（地の幅に対する割合）
    static let glowAlpha: Double = 0.10
    static let glowRadiusFraction: Double = 0.62
    /// 四隅の黒（周辺減光）の濃さ
    static let vignetteAlpha: Double = 0.35

    /// 明るさを測る升目（18 × 32 = 1 升 60px）。ぼかし（67px）とほぼ同じ大きさで、明るい所を取りこぼさない
    static let gridColumns = 18
    static let gridRows = 32
    /// 上の帯（0〜0.19・見る画面の進み線と名前）と下の帯（0.69〜1・「写真を見る」0.75 と返信欄）の升目の行
    static let topRows = 0..<6
    static let bottomRows = 22..<32
    /// 帯の上の明るさの上限（WCAG の相対輝度）。上下は白の字と 4.5:1、真ん中は 3:1
    static let edgeMaxLuminance: Double = 0.18
    static let middleMaxLuminance: Double = 0.30
    /// 黒を重ねる量の下限（暗い写真でも、上下は少し落として札を浮かせる）と上限
    static let minimumTop: Double = 0.30
    static let minimumMiddle: Double = 0.12
    static let minimumBottom: Double = 0.40
    static let maximumShade: Double = 0.88

    /// 帯ごとの黒の濃さ（0〜1）
    struct Shades: Equatable {
        let top: Double
        let middle: Double
        let bottom: Double
    }

    /// 1 つの色に、白の光（`lift`）を重ね、その上に黒（`shade`）を重ねた色（描く順と同じ）
    static func shaded(_ rgb: UInt32, lift: Double, shade: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let v = Double((rgb >> shift) & 0xFF) / 255
            let lifted = v + lift * (1 - v)
            return UInt32(max(0, min(255, (lifted * (1 - shade) * 255).rounded())))
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// その色を `maxLuminance` 以下にするのに要る黒の濃さ（`minimum` 〜 `maximumShade`）
    static func shadeNeeded(_ rgb: UInt32, lift: Double, maxLuminance: Double, minimum: Double) -> Double {
        if BrandPalette.luminance(shaded(rgb, lift: lift, shade: minimum)) <= maxLuminance { return minimum }
        var low = minimum
        var high = maximumShade
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if BrandPalette.luminance(shaded(rgb, lift: lift, shade: mid)) <= maxLuminance { high = mid } else { low = mid }
        }
        return high
    }

    /// 升目（左上から行ごと・`gridColumns × gridRows`）から帯ごとの黒の濃さを決める。
    /// 升目が足りなければ（測れなかった）白とみなす（明るい写真と同じに暗くして、字を読めなくしない）。
    /// 上と下は真ん中より薄くしない（帯の間のぼかしで、真ん中の明るい所が薄い側に入らないように）
    static func shades(grid: [UInt32]) -> Shades {
        let measured = grid.count == gridColumns * gridRows
        func brightest(_ rows: Range<Int>) -> UInt32 {
            guard measured else { return 0xFFFFFF }
            var best: UInt32 = 0
            var bestLuminance = -1.0
            for row in rows {
                for column in 0..<gridColumns {
                    let rgb = grid[row * gridColumns + column]
                    let luminance = BrandPalette.luminance(rgb)
                    if luminance > bestLuminance { bestLuminance = luminance; best = rgb }
                }
            }
            return best
        }
        // 光は札の後ろから広がる。帯の明るさの見積もりには、どの帯にも光が満ちたとして足す（明るい側に倒す）
        let middle = shadeNeeded(brightest(topRows.upperBound..<bottomRows.lowerBound), lift: glowAlpha,
                                 maxLuminance: middleMaxLuminance, minimum: minimumMiddle)
        let top = shadeNeeded(brightest(topRows), lift: glowAlpha, maxLuminance: edgeMaxLuminance, minimum: minimumTop)
        let bottom = shadeNeeded(brightest(bottomRows), lift: glowAlpha, maxLuminance: edgeMaxLuminance,
                                 minimum: minimumBottom)
        return Shades(top: max(top, middle), middle: middle, bottom: max(bottom, middle))
    }

    /// 縦の黒のグラデーションの段（位置 0〜1 と濃さ）。上の帯と下の帯は升目の境まで同じ濃さを保ち、
    /// 移り変わりは真ん中の帯の中で済ませる（真ん中は上下より薄くならない＝どの升目も要る濃さ以上）
    static func stops(_ shades: Shades) -> [(location: CGFloat, alpha: CGFloat)] {
        let rows = CGFloat(gridRows)
        return [
            (0, CGFloat(shades.top)),
            (CGFloat(topRows.upperBound) / rows, CGFloat(shades.top)),
            (CGFloat(topRows.upperBound + 4) / rows, CGFloat(shades.middle)),
            (CGFloat(bottomRows.lowerBound - 4) / rows, CGFloat(shades.middle)),
            (CGFloat(bottomRows.lowerBound) / rows, CGFloat(shades.bottom)),
            (1, CGFloat(shades.bottom)),
        ]
    }

    /// 位置 `y`（0〜1）での黒の濃さ（`stops` を線でつないだ値・試験で見る）
    static func alpha(at y: CGFloat, _ shades: Shades) -> CGFloat {
        let points = stops(shades)
        guard let first = points.first, let last = points.last else { return 0 }
        if y <= first.location { return first.alpha }
        for (a, b) in zip(points, points.dropFirst()) where y <= b.location {
            let span = b.location - a.location
            guard span > 0 else { return b.alpha }
            return a.alpha + (b.alpha - a.alpha) * (y - a.location) / span
        }
        return last.alpha
    }
}

extension SharedPhotoStoryCard {
    /// 地を描く（`SharedPhotoStoryBackdrop`）: ぼかした写真 → 札の後ろの光 → 帯ごとの黒 → 四隅の黒
    fileprivate static func drawBackdrop(_ image: UIImage, card: CGRect, in full: CGRect, context cg: CGContext) {
        typealias B = SharedPhotoStoryBackdrop
        let spread = full.insetBy(dx: -80, dy: -80)
        #if os(Linux)
        // Linux の SDK 模型には CoreGraphics のグラデーションが無い。描く絵は Mac / 実機で確かめる
        drawTinyBackdrop(image, in: spread)
        #else
        var grid: [UInt32] = []
        if let blurred = SignatureShareCardRenderer.blurredBackdrop(image, longEdge: B.blurLongEdge,
                                                                    radiusFraction: B.blurRadiusFraction,
                                                                    saturation: B.saturation) {
            blurred.draw(in: fillRect(imageSize: blurred.size, in: spread))
            grid = sampleGrid(blurred, spread: spread, canvas: full.size)
        } else {
            drawTinyBackdrop(image, in: spread)
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // 札の後ろの光（白 → 透明）
        let glowColors = [UIColor.white.withAlphaComponent(B.glowAlpha).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) {
            let center = CGPoint(x: card.midX, y: card.midY)
            cg.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center,
                                  endRadius: full.width * B.glowRadiusFraction, options: [])
        }
        // 帯ごとの黒
        let stops = B.stops(B.shades(grid: grid))
        let colors = stops.map { UIColor.black.withAlphaComponent($0.alpha).cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: stops.map { $0.location }) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: full.minY), end: CGPoint(x: 0, y: full.maxY),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // 四隅の黒（真ん中は透明・角で vignetteAlpha）
        let vignetteColors = [UIColor.black.withAlphaComponent(0).cgColor,
                              UIColor.black.withAlphaComponent(B.vignetteAlpha).cgColor] as CFArray
        if let vignette = CGGradient(colorsSpace: colorSpace, colors: vignetteColors, locations: [0.45, 1]) {
            let center = CGPoint(x: full.midX, y: full.midY)
            cg.drawRadialGradient(vignette, startCenter: center, startRadius: 0, endCenter: center,
                                  endRadius: hypot(full.width, full.height) / 2, options: [.drawsAfterEndLocation])
        }
        #endif
    }

    /// ぼかしが作れないときの地（前の作り: 小さく縮めた写真を引き伸ばす）
    fileprivate static func drawTinyBackdrop(_ image: UIImage, in spread: CGRect) {
        let tiny = image.preparingThumbnail(of: CGSize(width: 24, height: 24 * image.size.height / max(image.size.width, 1)))
            ?? image
        tiny.draw(in: fillRect(imageSize: image.size, in: spread))
    }

    #if !os(Linux)
    /// 地に敷いたぼかしの写真を、升目（`gridColumns × gridRows`）に縮めて色を読む。読めなければ空
    fileprivate static func sampleGrid(_ blurred: UIImage, spread: CGRect, canvas: CGSize) -> [UInt32] {
        typealias B = SharedPhotoStoryBackdrop
        let columns = B.gridColumns
        let rows = B.gridRows
        guard let cgImage = blurred.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let small = CGContext(data: base, width: columns, height: rows, bitsPerComponent: 8,
                                        bytesPerRow: columns * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            small.interpolationQuality = .medium
            // 地の座標（上が 0）を升目の座標（下が 0・CGContext の向き）へ
            let sx = CGFloat(columns) / canvas.width
            let sy = CGFloat(rows) / canvas.height
            let rect = fillRect(imageSize: blurred.size, in: spread)
            small.draw(cgImage, in: CGRect(x: rect.minX * sx, y: (canvas.height - rect.maxY) * sy,
                                           width: rect.width * sx, height: rect.height * sy))
            return true
        }
        guard drawn else { return [] }
        return (0..<(columns * rows)).map { i in
            (UInt32(bytes[i * 4]) << 16) | (UInt32(bytes[i * 4 + 1]) << 8) | UInt32(bytes[i * 4 + 2])
        }
    }
    #endif
}
