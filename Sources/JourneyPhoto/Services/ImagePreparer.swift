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

    /// カメラで撮った1枚に、撮影情報（撮影日時・機種など）を付け直す。
    ///
    /// カメラの1枚は `UIImage` を経由して JPEG にするので、本体には EXIF が残らず、
    /// `prepare` が読む撮影日（`takenOn`）が**いつも空**だった（旅の記録・撮影日で並べる一覧から落ちる）。
    ///
    /// **2026-10-02 判断: カメラが付ける撮影情報（`info[.mediaMetadata]`）を先に使い、
    /// 撮影日時が無ければ撮った時刻（端末の時計・端末の時間帯）を撮影日にする。**
    /// その場で撮った写真なので、端末の今の時刻が撮影日時そのもの。
    /// EXIF の撮影日時は撮った土地の壁時計なので、端末の時間帯で書くのが同じ意味になる。
    ///
    /// **位置は読まない。** `UIImagePickerController` は位置を付けない（付いていても今の扱いのまま、
    /// カメラの写真は座標なし）。座標は `prepared` のまま
    static func applyingCaptureInfo(_ prepared: Prepared, metadata: [CFString: Any], capturedAt: Date,
                                    timeZone: TimeZone = .current) -> Prepared {
        var exif = readExif(from: metadata)
        var takenOn = readTakenOn(from: metadata)
        if exif.dateTimeOriginal == nil || takenOn == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            let stamp = formatter.string(from: capturedAt)
            exif.dateTimeOriginal = exif.dateTimeOriginal ?? stamp
            takenOn = takenOn ?? String(stamp.prefix(10))
        }
        return Prepared(
            data: prepared.data,
            fileName: prepared.fileName,
            contentType: prepared.contentType,
            exif: exif.isEmpty ? nil : exif,
            coords: prepared.coords,
            takenOn: takenOn,
            dominantColor: prepared.dominantColor
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
        guard let image = downsampledImage(source: source, maxPixelSize: maxPixelSize) else {
            throw PrepareError.encodeFailed
        }
        return try encodeJPEG(image)
    }

    /// 縮めて読むときの指定。**上げる経路と写真の編集（`PhotoRenderer`）で同じものを使う。**
    ///
    /// - `ThumbnailMaxPixelSize` は**長い辺**の画素数。元より大きくはしない
    /// - 向きは画素に焼く（`WithTransform`）
    /// - **HDR（PQ / HLG）は SDR に直して読む**（`kCGImageSourceDecodeToSDR`・iOS 17+）。
    ///   HDR のまま 8bit の JPEG に焼くと、明るい所が白く飛ぶ（2026-10-02 のレビュー）
    static func downsampleOptions(maxPixelSize: Int) -> [CFString: Any] {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToSDR,
        ]
    }

    /// 長い辺 `maxPixelSize` に縮めて読む（`downsampleOptions`）
    static func downsampledImage(source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions(maxPixelSize: maxPixelSize) as CFDictionary)
    }

    /// **自前で描いた画像**（写真の編集の書き出し・`PhotoRenderer`）を、原本と同じ関所に通す:
    /// JPEG に焼いて、EXIF / GPS が残っていないことを読み直して確かめる。
    /// 大きさはここでは変えない——呼ぶ側が `maxPixelSize` に収めてから渡す
    ///
    /// `encode` は試験のための差し口（撮影情報を書き込む焼き方を渡し、関所が投げるのを見る）。
    /// アプリからは渡さない
    static func encodeStripped(_ image: CGImage,
                               encode: (CGImage) throws -> Data = ImagePreparer.encodeJPEG) throws -> Data {
        let jpeg = try encode(image)
        try assertStripped(jpeg)
        return jpeg
    }

    /// CGImage を JPEG に焼く。**元の properties を渡さない**ので EXIF は付かない。
    /// 色空間は画像のもの（ICC として埋め込まれる）
    static func encodeJPEG(_ image: CGImage) throws -> Data {
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

    /// 出力を読み直して、EXIF / GPS / TIFF / XMP が残っていないことを確かめる。
    /// 試験から呼ぶので `private` にしない
    static func assertStripped(_ data: Data) throws {
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
        // **XMP も見る。** 上の辞書は EXIF・GPS・TIFF の欄だけで、XMP の包み（撮影地の市名・
        // 作成日時など）に残ったものは見えない。今の焼き直しは XMP を書かないが、書く形に変わっても
        // 素通ししないように、場所・日時・機材を言う項目だけを確かめる
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            let identifying = [
                "exif:GPSLatitude", "exif:GPSLongitude", "exif:DateTimeOriginal",
                "tiff:Make", "tiff:Model", "xmp:CreateDate",
                "photoshop:City", "photoshop:DateCreated", "Iptc4xmpCore:Location",
            ]
            if identifying.contains(where: { CGImageMetadataCopyTagWithPath(metadata, nil, $0 as CFString) != nil }) {
                throw PrepareError.metadataRemains
            }
        }
    }

    // MARK: - 読み取り

    /// 試験から呼ぶので `private` にしない
    static func readExif(from properties: [CFString: Any]) -> ExifFields {
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
        // 🔴 **`Int(...)` に通す値は `Int(exactly:)` で受ける。** 無限大・桁あふれの値
        // （壊れた EXIF・極端に小さい露出）で `Int(...)` はアプリごと落ちる。見ていたのは
        // `> 0` だけだった。表せない値は出さない
        if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0, exposure.isFinite {
            if exposure >= 1 {
                fields.exposure = String(format: "%.1fs", exposure)
            } else if let denominator = Int(exactly: (1 / exposure).rounded()) {
                fields.exposure = "1/\(denominator)"
            }
        }
        if let isoList = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoList.first, iso > 0 {
            fields.iso = iso
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double, focal > 0,
           let millimeters = Int(exactly: focal.rounded()) {
            fields.focalLength = "\(millimeters)mm"
        }
        fields.dateTimeOriginal = storedDateTime(exif[kCGImagePropertyExifDateTimeOriginal] as? String)

        return fields
    }

    /// GPS を約1km（小数第2位）に丸める。**丸める前の値は外に出さない。**
    /// サーバーも `sanitizeCoords` で同じ丸めをするが、丸める前の座標を
    /// 電波に乗せる理由が無い。
    ///
    /// **`0,0` は「座標なし」。** GPS を掴めなかったカメラ・アプリが 0 を
    /// 書くことがあり、そのまま送るとギニア湾（ヌル島）にピンが立つ。
    static func readCoords(from properties: [CFString: Any]) -> Photo.Coords? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latValue = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lngValue = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lngRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        let lat = latRef.uppercased() == "S" ? -latValue : latValue
        let lng = lngRef.uppercased() == "W" ? -lngValue : lngValue
        guard lat.isFinite, lng.isFinite, abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        guard !(lat == 0 && lng == 0) else { return nil }
        return Photo.Coords(lat: (lat * 100).rounded() / 100, lng: (lng * 100).rounded() / 100)
    }

    /// EXIF の撮影日時（`2026:09:13 08:21:05`）を、**保存する形**
    /// `2026-09-13T08:21:05` にする。
    ///
    /// **EXIF の綴りのまま送っていた**ので、Web の写真ページ（`ExifSpecs` の
    /// `formatStoredDateTime` は `YYYY-MM-DD[T ]HH:mm` しか読まない）に
    /// アプリから上げた写真の撮影日時が出なかった。
    /// 読めない値は送らない（nil）。既に `YYYY-MM-DD…` の形ならそのまま
    static func storedDateTime(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil { return raw }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: raw) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return out.string(from: date)
    }

    /// 撮影日を YYYY-MM-DD にする。EXIF の日付は "2026:09:13 08:21:05"。
    ///
    /// **この形式を自前で切らない理由**: 桁揃えされていないカメラが実在し、
    /// 素朴な `split(":")` は年月日を取り違える。DateFormatter に任せる。
    private static func readTakenOn(from properties: [CFString: Any]) -> String? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        return takenOn(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
    }

    /// EXIF の日時（撮った土地の壁時計）から日付だけを取る。
    ///
    /// **UTC で読んで UTC で書く**（`storedDateTime` と同じ）。端末の時間帯で読むと、
    /// 端末の土地で夏時間に切り替わる時刻（ニューヨークの `2026:03:08 02:30:00` など）は
    /// 存在しない時刻として nil になり、日本で撮った写真の撮影日が落ちていた
    static func takenOn(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: raw) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }

    private static func jpegFileName(from original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let safe = base.isEmpty ? "photo" : base
        return "\(safe).jpg"
    }
}
