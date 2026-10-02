import Foundation
import CoreImage
import ImageIO

/// 編集レシピを写真に当てて描く（Core Image）。並びと数値は `PhotoRecipePlan`（純関数）が決め、
/// ここはそれを `CIFilter` に組んで描くだけ。**元の画素は変えない**（非破壊。毎回元から描く）。
///
/// - プレビュー: `loadPreview` で**画面の大きさに縮めて**読み、`preview` で描く
/// - 書き出し: `export` が最大辺 1920 に縮めて読み、描いて、`ImagePreparer.encodeStripped`
///   （原本と同じ関所）で JPEG 0.85 に焼く。EXIF / GPS が残っていたら投げる
///
/// **高解像度の対策。** 元の画像をそのまま `CIImage` にしない。4800 万画素の写真を
/// そのまま Core Image に渡すと、フィルターの途中の画像が数百 MB になり、古い端末では
/// メモリで落とされる。読むときに `kCGImageSourceThumbnailMaxPixelSize` で必要な大きさまで
/// 縮めてから `CIImage` にする（向きもここで画素に焼く）。
///
/// **色空間（2026-10-02 判断）**
/// - 作業は Core Image の既定（拡張リニア sRGB）のまま。P3 の色も 0…1 の外の値として
///   失わずに運べるので、作業色空間を変える理由が無い
/// - 書き出しは、**元の画像が Display P3 なら Display P3、それ以外は sRGB**。
///   iPhone の写真（HEIC）は P3 で撮られているので、sRGB に潰すと赤や緑の鮮やかさが
///   落ちる。逆に sRGB の写真を P3 で書いても得は無い。どちらも ICC を画像に付ける
///   （`CGImageDestination` が画像の色空間を埋め込む）——付けないと Web 側の表示で色がずれる
/// - プレビューも同じ色空間で描く（画面で見た色と書き出しの色をそろえる）
///
/// **`CIContext` は1つを使い回す。** 作るたびに GPU の準備とキャッシュが捨てられ、
/// つまみを動かすたびに描き直すプレビューが重くなる（Apple の推奨も使い回し）
final class PhotoRenderer {

    static let shared = PhotoRenderer()

    let context = CIContext()

    /// 読んだ写真。描く元の画像と、書き出す色空間
    struct Loaded {
        let image: CIImage
        let colorSpace: CGColorSpace
    }

    // MARK: - 読む

    /// 最大辺 `maxPixelSize` に縮めて読む（向きは画素に焼く）。読めなければ nil。
    /// プレビューには「画面の幅（点）× 画面の倍率」を渡す
    static func load(data: Data, maxPixelSize: Int) -> Loaded? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        guard let space = outputColorSpace(for: cgImage.colorSpace) else { return nil }
        return Loaded(image: CIImage(cgImage: cgImage), colorSpace: space)
    }

    /// 書き出す色空間: 元が Display P3 の系統なら Display P3、それ以外は sRGB
    static func outputColorSpace(for original: CGColorSpace?) -> CGColorSpace? {
        let name = original?.name.map { $0 as String } ?? ""
        if isDisplayP3(name: name), let p3 = CGColorSpace(name: CGColorSpace.displayP3) {
            return p3
        }
        return CGColorSpace(name: CGColorSpace.sRGB)
    }

    /// 色空間の名前が Display P3 の系統か（`kCGColorSpaceDisplayP3`、拡張・HDR の変種も含む。
    /// HDR の変種も書き出しは 8bit の Display P3 にする）
    static func isDisplayP3(name: String) -> Bool {
        name.contains("DisplayP3")
    }

    // MARK: - 当てる

    /// レシピのフィルターを順に当てる。無編集なら元の画像のまま。
    /// 作れないフィルター・引数があっても**落とさず**、その段を飛ばす（写真は出す）
    func apply(_ recipe: PhotoRecipe, to image: CIImage) -> CIImage {
        var output = image
        for step in PhotoRecipePlan.steps(for: recipe) {
            guard let filter = CIFilter(name: step.filter) else { continue }
            filter.setValue(output, forKey: kCIInputImageKey)
            for (key, value) in step.parameters {
                switch value {
                case .number(let number):
                    filter.setValue(number, forKey: key)
                case .vector(let values):
                    // 使っている引数（中立点・曲線の点）はどれも2つの値
                    guard values.count == 2 else { continue }
                    filter.setValue(CIVector(x: CGFloat(values[0]), y: CGFloat(values[1])), forKey: key)
                }
            }
            if let next = filter.outputImage {
                output = next
            }
        }
        // 縁のにじみで画像の枠が広がっても、元の枠で切る
        return output.cropped(to: image.extent)
    }

    // MARK: - プレビュー

    /// 画面に出す画像。`loaded` は `load(data:maxPixelSize:)` で**画面の大きさに縮めたもの**
    func preview(_ recipe: PhotoRecipe, loaded: Loaded) -> CGImage? {
        let output = apply(recipe, to: loaded.image)
        return context.createCGImage(output, from: loaded.image.extent,
                                     format: .RGBA8, colorSpace: loaded.colorSpace)
    }

    // MARK: - 書き出し

    /// 上げる JPEG を作る。最大辺 1920・品質 0.85（`ImagePreparer` と同じ）、
    /// EXIF / GPS なし（関所で読み直して確かめる）、ICC 付き。
    ///
    /// 撮影情報（EXIF の項目・丸めた座標・撮影日）は**原本から** `ImagePreparer.prepare` で
    /// 取る。ここが返すのは画素だけ
    func export(data: Data, recipe: PhotoRecipe) throws -> Data {
        guard let loaded = Self.load(data: data, maxPixelSize: ImagePreparer.maxPixelSize) else {
            throw ImagePreparer.PrepareError.unreadable
        }
        let output = apply(recipe, to: loaded.image)
        guard let cgImage = context.createCGImage(output, from: loaded.image.extent,
                                                  format: .RGBA8, colorSpace: loaded.colorSpace),
              max(cgImage.width, cgImage.height) <= ImagePreparer.maxPixelSize else {
            throw ImagePreparer.PrepareError.encodeFailed
        }
        return try ImagePreparer.encodeStripped(cgImage)
    }
}
