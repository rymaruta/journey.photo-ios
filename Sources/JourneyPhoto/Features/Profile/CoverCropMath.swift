import Foundation
import ImageIO
import UIKit

/// 枠（縦横どちらの形でも）に写真を敷いて切り抜くときの計算（2026-10-28）。**画面と分けて試せるように計算だけ**。
///
/// アイコンの丸（`AvatarCropMath`・正方形の枠）とカバーの帯（`CoverCropMath`・横長の枠）で同じものを使う。
/// - 写真は**枠を必ず覆う大きさ**（`fillSize`）から始め、倍率は 1〜`maxZoom`
/// - 動かせるのは、枠の中に空きが出ない範囲だけ（`clamp`）
/// - 切り抜く範囲は**写真の画素の座標**で返す（`cropRect`）——画面の表示倍率には左右されない
enum FrameCropMath {

    /// 枠を埋める最小の倍率で写真を置いたときの、写真の表示の大きさ（画面の pt）
    static func fillSize(image: CGSize, frame: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return frame }
        let scale = max(frame.width / image.width, frame.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// 倍率を 1〜`maxZoom` に収める（1 より小さいと枠に空きが出る）
    static func clampZoom(_ zoom: Double, maxZoom: Double) -> Double {
        min(maxZoom, max(1, zoom))
    }

    /// 動かした量（写真の真ん中が枠の真ん中からずれる量・pt）を、枠の中に空きができない範囲に収める
    static func clamp(offset: CGSize, zoom: Double, image: CGSize, frame: CGSize) -> CGSize {
        let base = fillSize(image: image, frame: frame)
        let w = base.width * zoom, h = base.height * zoom
        let maxX = max(0, (w - frame.width) / 2), maxY = max(0, (h - frame.height) / 2)
        return CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }

    /// 枠に入っている写真の範囲（**写真の画素の座標**）。縦横比は枠と同じ
    static func cropRect(image: CGSize, frame: CGSize, zoom: Double, offset: CGSize, maxZoom: Double) -> CGRect {
        let base = fillSize(image: image, frame: frame)
        let z = clampZoom(zoom, maxZoom: maxZoom)
        let o = clamp(offset: offset, zoom: z, image: image, frame: frame)
        guard base.width > 0 else { return .zero }
        // 画面の 1pt が写真の何画素か（縦横で同じ倍率）
        let perPoint = image.width / (base.width * z)
        let width = frame.width * perPoint, height = frame.height * perPoint
        let centerX = image.width / 2 - o.width * perPoint
        let centerY = image.height / 2 - o.height * perPoint
        return CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }
}

/// マイページのカバー（帯）に映る範囲を、上げる前に端末で切り抜く（owner 2026-10-28「ユーザが任意で調整できたらいいよね」）。
///
/// 2026-10-28 判断: **サーバー・API・置き場所は変えない。** 切り抜いた JPEG を、いままでどおり
/// `profiles/<uid>/cover`（`ProfileService.uploadProfileImage`）に上げるだけ。
/// 枠の比は iPhone のマイページの帯（基準幅 390 × `ProfileCover.height`）なので、**iPhone ではそろう。
/// Web の帯（最大 1024×180 の横長）は、この絵の上下の中ほどだけ映る**（Web 側は変えていない）。
/// 元の写真はサーバーにも端末にも残さないので、上げたあとに位置を変えるときは写真を選び直す
enum CoverCropMath {

    /// 拡大の上限（帯を覆う大きさに対して）
    static let maxZoom: Double = 3
    /// 切り抜く元を読むときの長い辺の上限（px）。**上げる大きさ（1920）より大きく読む**——拡大して切り抜いても
    /// 画素が足りるように。これより大きい原本（24〜48MP）は丸ごと読まない（メモリ）。**読むのは「完了」のときだけ**
    static let sourceMaxPixelSize = 4096
    /// 画面に出す絵の長い辺（px）。合わせている間はこれだけを持つ（元の 4096px を持ち続けない・メモリ）
    static let displayMaxPixelSize = 1500
    /// 上げる長い辺の上限（px）。**いままでのカバーと同じ決まり**（`ImagePreparer.maxPixelSize`・Web の 1920）
    static var outputLongSide: Int { ImagePreparer.maxPixelSize }
    /// 枠の比を決める基準の画面幅（pt・iPhone の幅）。**画面の幅に依らず比は 390 : `ProfileCover.height`**
    /// ——iPad などで幅に合わせて比を変えると、iPhone の帯と映る範囲がずれる
    static let referenceWidth: Double = 390

    /// 枠の縦横比（横 / 縦）。高さはマイページの帯（`ProfileCover.height`）——**定数を写さない**
    static var aspect: Double { referenceWidth / ProfileCover.height }

    /// 決まった比の枠を、使える幅・高さに収まるいちばん大きい大きさで（pt）。iPhone では画面の幅いっぱい
    static func frame(fitting available: CGSize) -> CGSize {
        let width = max(1, min(available.width, available.height * aspect))
        return CGSize(width: width, height: width / aspect)
    }

    /// 切り抜いた範囲（画素）を、上げる大きさにする。長い辺を `longSide` に縮める（**元より大きくはしない**）
    static func outputSize(crop: CGSize, longSide: Int = outputLongSide) -> CGSize {
        let long = max(crop.width, crop.height)
        guard long > 0 else { return CGSize(width: 1, height: 1) }
        let k = min(1, Double(longSide) / long)
        return CGSize(width: max(1, (crop.width * k).rounded()), height: max(1, (crop.height * k).rounded()))
    }

    /// 出来上がり（`out`）の中に、元の写真をどこへ描くか。**縦と横を別の倍率で**合わせる——
    /// `outputSize` が画素を丸めるので、同じ倍率で描くと端の 1 行が埋まらず半透明になる（確かめ役 2026-10-28）
    static func drawRect(image: CGSize, crop: CGRect, out: CGSize) -> CGRect {
        guard crop.width > 0, crop.height > 0 else { return .zero }
        let kx = out.width / crop.width, ky = out.height / crop.height
        return CGRect(x: -crop.minX * kx, y: -crop.minY * ky, width: image.width * kx, height: image.height * ky)
    }

    /// 選んだ写真を読む。向きを画素に焼き、HDR は SDR に直す（上げる経路と同じ読み方・`ImagePreparer.downsampledImage`）。
    /// 重いので画面の処理の外で呼ぶ
    static func image(from data: Data, maxPixelSize: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = ImagePreparer.downsampledImage(source: source, maxPixelSize: maxPixelSize) else {
            throw ImagePreparer.PrepareError.unreadable
        }
        return UIImage(cgImage: image)
    }

    /// 合わせている間に画面に出す絵（長い辺 `displayMaxPixelSize`）
    static func display(from data: Data) throws -> UIImage {
        try image(from: data, maxPixelSize: displayMaxPixelSize)
    }

    /// 元の写真（`data`）を読み直して切り抜き、上げられる JPEG にする。**元の写真の画素で切る**（画面に出ている絵の
    /// 大きさではなく）。位置（`zoom`・`offset`）は画面の pt で、絵の解像度には左右されない（`FrameCropMath`）。
    /// 焼くのは `ImagePreparer.encodeStripped`——品質（0.85）も、EXIF / GPS が残っていないことの確かめも、いままでと同じ関所。
    /// 重いので画面の処理の外で呼ぶ
    static func render(_ data: Data, frame: CGSize, zoom: Double, offset: CGSize) throws -> Data {
        let image = try image(from: data, maxPixelSize: sourceMaxPixelSize)
        let rect = FrameCropMath.cropRect(image: image.size, frame: frame, zoom: zoom, offset: offset, maxZoom: maxZoom)
        guard rect.width > 0, rect.height > 0 else { throw ImagePreparer.PrepareError.encodeFailed }
        let out = outputSize(crop: rect.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // 透明を持たない・8bit の色（HDR の広い色で焼かない）
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: out, format: format)
        let drawn = renderer.image { _ in
            image.draw(in: drawRect(image: image.size, crop: rect, out: out))
        }
        guard let cgImage = drawn.cgImage else { throw ImagePreparer.PrepareError.encodeFailed }
        return try ImagePreparer.encodeStripped(cgImage)
    }
}
