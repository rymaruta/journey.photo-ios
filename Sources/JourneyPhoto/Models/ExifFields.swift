import Foundation

/// 送信する撮影情報。
///
/// `api-user/src/sanitize.ts` の `sanitizeExif` が通すキーだけを持つ。
/// **これ以外は送らない**（サーバーも捨てるが、送る理由が無い）。
///
/// **画像の読み書き（ImageIO）から切り離してある。** `UploadService` が
/// 参照する型なので、ここが ImageIO に依存していると、Foundation だけの層を
/// Linux 上で型検査できなくなる。
struct ExifFields: Encodable, Equatable {
    var camera: String?
    var lens: String?
    var aperture: String?
    var exposure: String?
    var iso: Int?
    var focalLength: String?
    var dateTimeOriginal: String?

    var isEmpty: Bool {
        camera == nil && lens == nil && aperture == nil && exposure == nil
            && iso == nil && focalLength == nil && dateTimeOriginal == nil
    }
}
