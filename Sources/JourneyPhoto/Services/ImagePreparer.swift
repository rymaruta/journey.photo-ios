import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 上げてよい形に整える。整えられなければ**投げる**。
///
/// **ここが GPS の関所。** このサービスは「EXIF を落とし、座標は約1kmに
/// 丸めて公開する」という前提で作られている。ところが Web 版では、
/// 再エンコードに失敗した経路が**原本をそのまま素通し**していて、
/// GPS 入りの HEIC が公開URLで配信されていた（`lib/utils/image.ts` の
/// `toUploadSafeFile` の経緯）。
///
/// その反省をそのまま持ち込む: **「消せたことを確認できたものだけ上げる」。**
/// 出力を読み直して EXIF / GPS が残っていないことを確かめ、
/// 残っていたら投げる（素通ししない）。
enum ImagePreparer {

    /// Web 版と同じ既定（`toUploadSafeFile(file, 1920, 0.85)`）。
    static let maxPixelSize = 1920
    static let jpegQuality = 0.85

    struct Prepared {
        /// 上げる本体。常に JPEG（EXIF なし）
        let data: Data
        let fileName: String
        let contentType: String
        /// 原本から読み取った撮影情報。**GPS は含めない**
        let exif: ExifFields?
        /// 原本の GPS を約1kmに丸めたもの。無ければ nil
        let coords: Photo.Coords?
        /// 撮影日（YYYY-MM-DD）
        let takenOn: String?
        /// 代表色（`#rrggbb`）。**読み込み中の地の色**に使う。
        /// 取れなければ nil——投稿は止めない
        ///
        /// 既定を持たせてあるのは、**組み立て直す側**（下書きの復元・テスト）
        /// が色を知らないため。色は原本からしか取れない
        var dominantColor: String? = nil
    }

    enum PrepareError: LocalizedError {
        case unreadable
        case encodeFailed
        /// 出力にまだ EXIF / GPS が残っていた
        case metadataRemains

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return L("画像を読み取れませんでした", "Couldn't read the image")
            case .encodeFailed:
                return L("画像を変換できませんでした", "Couldn't convert the image")
            case .metadataRemains:
                return L("この画像から撮影情報を取り除けませんでした。別の写真をお試しください", "Couldn't strip metadata from this image. Please try another photo.")
            }
        }
    }

    static func prepare(data: Data, fileName: String) throws -> Prepared {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw PrepareError.unreadable
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let exif = readExif(from: properties)
        let coords = readCoords(from: properties)
        let takenOn = readTakenOn(from: properties)

        let jpeg = try reencodeAsJPEG(source: source)
        try assertStripped(jpeg)

        return Prepared(
            data: jpeg,
            fileName: jpegFileName(from: fileName),
            contentType: "image/jpeg",
            exif: exif.isEmpty ? nil : exif,
            coords: coords,
            takenOn: takenOn,
            // **原本から取る。** 焼き込みや再圧縮のあとでは色がわずかに動く
            // ——読み込み中の地の色なので実害は無いが、Web と同じものを出す
            dominantColor: DominantColorExtractor.hex(from: data)
        )
    }

    // MARK: - 変換

    /// 1920px に収めて JPEG に焼き直す。
    ///
    /// サムネイル API を使うのは、**出力に元のメタデータが引き継がれない**
    /// から。`CGImageDestination` に元の properties を渡さなければ EXIF は付かない。
    /// 回転は画素に焼き込む（`WithTransform`）——落とした EXIF に
    /// Orientation も含まれるので、焼かないと横倒しになる。
    private static func reencodeAsJPEG(source: CGImageSource) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PrepareError.encodeFailed
        }
        let output = NSMutableData()
        // `CGImageDestinationCreateWithData` は `CFMutableData` を取る。
        // NSMutableData からの橋渡しは明示的に書く（暗黙に通る保証がない）
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw PrepareError.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PrepareError.encodeFailed
        }
        return output as Data
    }

    /// 出力を読み直して、EXIF / GPS / TIFF が残っていないことを確かめる。
    private static func assertStripped(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw PrepareError.encodeFailed
        }
        if properties[kCGImagePropertyGPSDictionary] != nil {
            throw PrepareError.metadataRemains
        }
        // ImageIO は JPEG に最小限の EXIF（色空間・寸法）を書くことがある。
        // 問題なのは「どこで誰が撮ったか」なので、その項目だけを見る
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            let identifying: [CFString] = [
                kCGImagePropertyExifDateTimeOriginal,
                kCGImagePropertyExifBodySerialNumber,
                kCGImagePropertyExifLensSerialNumber,
            ]
            if identifying.contains(where: { exif[$0] != nil }) {
                throw PrepareError.metadataRemains
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil {
                throw PrepareError.metadataRemains
            }
        }
    }

    // MARK: - 読み取り

    private static func readExif(from properties: [CFString: Any]) -> ExifFields {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        var fields = ExifFields()

        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // "Apple Apple iPhone 15 Pro" のような重複を避ける
        let camera = model.hasPrefix(make) ? model : [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        fields.camera = camera.isEmpty ? nil : camera

        fields.lens = (exif[kCGImagePropertyExifLensModel] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double, fNumber > 0 {
            fields.aperture = String(format: "f/%.1f", fNumber)
        }
        if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0 {
            fields.exposure = exposure >= 1
                ? String(format: "%.1fs", exposure)
                : "1/\(Int((1 / exposure).rounded()))"
        }
        if let isoList = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoList.first, iso > 0 {
            fields.iso = iso
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double, focal > 0 {
            fields.focalLength = "\(Int(focal.rounded()))mm"
        }
        fields.dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String

        return fields
    }

    /// GPS を約1km（小数第2位）に丸める。**丸める前の値は外に出さない。**
    /// サーバーも `sanitizeCoords` で同じ丸めをするが、丸める前の座標を
    /// 電波に乗せる理由が無い。
    private static func readCoords(from properties: [CFString: Any]) -> Photo.Coords? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latValue = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lngValue = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lngRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        let lat = latRef.uppercased() == "S" ? -latValue : latValue
        let lng = lngRef.uppercased() == "W" ? -lngValue : lngValue
        guard abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        return Photo.Coords(lat: (lat * 100).rounded() / 100, lng: (lng * 100).rounded() / 100)
    }

    /// 撮影日を YYYY-MM-DD にする。EXIF の日付は "2026:09:13 08:21:05"。
    ///
    /// **この形式を自前で切らない理由**: 桁揃えされていないカメラが実在し、
    /// 素朴な `split(":")` は年月日を取り違える。DateFormatter に任せる。
    private static func readTakenOn(from properties: [CFString: Any]) -> String? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        guard let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: raw) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }

    private static func jpegFileName(from original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let safe = base.isEmpty ? "photo" : base
        return "\(safe).jpg"
    }
}
