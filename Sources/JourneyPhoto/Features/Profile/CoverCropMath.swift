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
/// `profiles/<uid>/cover`（`ProfileService.uploadProfileImage`）に上げるだけ。Web も同じ画像を出すのでそろう。
/// 元の写真はサーバーにも端末にも残さないので、上げたあとに位置を変えるときは写真を選び直す
enum CoverCropMath {

    /// 拡大の上限（帯を覆う大きさに対して）
    static let maxZoom: Double = 3
    /// 切り抜く元を読むときの長い辺の上限（px）。**上げる大きさ（1920）より大きく読む**——拡大して切り抜いても
    /// 画素が足りるように。これより大きい原本（24〜48MP）は丸ごと読まない（メモリ）
    static let sourceMaxPixelSize = 4096
    /// 上げる長い辺の上限（px）。**いままでのカバーと同じ決まり**（`ImagePreparer.maxPixelSize`・Web の 1920）
    static var outputLongSide: Int { ImagePreparer.maxPixelSize }

    /// 帯の枠の大きさ（pt）。横は画面の幅、高さはマイページの帯（`ProfileCover.height`）——**定数を写さない**
    static func frame(width: Double) -> CGSize {
        CGSize(width: width, height: ProfileCover.height)
    }

    /// 切り抜いた範囲（画素）を、上げる大きさにする。長い辺を `longSide` に縮める（**元より大きくはしない**）
    static func outputSize(crop: CGSize, longSide: Int = outputLongSide) -> CGSize {
        let long = max(crop.width, crop.height)
        guard long > 0 else { return CGSize(width: 1, height: 1) }
        let k = min(1, Double(longSide) / long)
        return CGSize(width: max(1, (crop.width * k).rounded()), height: max(1, (crop.height * k).rounded()))
    }

    /// 選んだ写真を、切り抜きの元として読む。向きを画素に焼き、HDR は SDR に直す
    /// （上げる経路と同じ読み方・`ImagePreparer.downsampledImage`）。重いので画面の処理の外で呼ぶ
    static func source(from data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = ImagePreparer.downsampledImage(source: source, maxPixelSize: sourceMaxPixelSize) else {
            throw ImagePreparer.PrepareError.unreadable
        }
        return UIImage(cgImage: image)
    }

    /// 切り抜いて、上げられる JPEG にする。**元の写真の画素で切る**（画面に出ている大きさではなく）。
    /// 焼くのは `ImagePreparer.encodeStripped`——品質（0.85）も、EXIF / GPS が残っていないことの確かめも、いままでと同じ関所
    static func render(_ image: UIImage, frame: CGSize, zoom: Double, offset: CGSize) throws -> Data {
        let rect = FrameCropMath.cropRect(image: image.size, frame: frame, zoom: zoom, offset: offset, maxZoom: maxZoom)
        guard rect.width > 0, rect.height > 0 else { throw ImagePreparer.PrepareError.encodeFailed }
        let out = outputSize(crop: rect.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: out, format: format)
        let drawn = renderer.image { _ in
            let k = out.width / rect.width
            image.draw(in: CGRect(x: -rect.minX * k, y: -rect.minY * k,
                                  width: image.size.width * k, height: image.size.height * k))
        }
        guard let cgImage = drawn.cgImage else { throw ImagePreparer.PrepareError.encodeFailed }
        return try ImagePreparer.encodeStripped(cgImage)
    }
}
