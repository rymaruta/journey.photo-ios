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
/// 9:16 の地に、写真をぼかして暗くしたもの（黒 45%）を敷き、真ん中より少し上に**写真の札**を −2° 傾けて置く。
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
    /// 地の暗さ（模型の brightness .55 ≒ 黒 45%）
    static let backdropShade: Double = 0.45

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
            // 地: 小さく縮めた写真を引き伸ばす（にじんでぼける・重いぼかしを掛けない）。そのうえを暗く
            let tiny = image.preparingThumbnail(of: CGSize(width: 24, height: 24 * image.size.height / max(image.size.width, 1)))
                ?? image
            tiny.draw(in: fillRect(imageSize: image.size, in: full.insetBy(dx: -80, dy: -80)))
            UIColor.black.withAlphaComponent(backdropShade).setFill()
            context.fill(full)

            let card = cardRect(imageSize: image.size)
            let photoBox = photoRect(imageSize: image.size)
            let cg = context.cgContext
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
