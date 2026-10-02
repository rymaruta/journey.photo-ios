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

    /// 一覧の格子に出す軽い版（`thumbSrc`）。**Web と同じ大きさと品質**
    /// （`lib/utils/image.ts` の `createThumbnail(file, 512, 0.75)`）。
    ///
    /// アプリで上げた写真には `thumbSrc` が無く、一覧が元画像（〜1920px）を読んでいた
    /// （2026-10-02 の調査）。形式だけは JPEG——Web は WebP だが、ImageIO は WebP を
    /// 書けない。サーバーは `image/jpeg` を受ける（`uploadPolicy.ts` の許可リスト）
    static let thumbnailMaxPixelSize = 512
    static let thumbnailQuality = 0.75

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
        /// 一覧用の 512px JPEG（EXIF なし・本体と同じ関所を通したもの）。
        /// **作れなければ nil——投稿は止めない**（Web もサムネ無しで続ける）。
        /// 組み立て直す側（下書きの復元・テスト）は持たないので既定は nil
        var thumbnail: Data? = nil

        /// サムネのファイル名（Web の `thumbFileName` と同じ `<名前>_thumb.jpg`）
        var thumbnailFileName: String {
            "\((fileName as NSString).deletingPathExtension)_thumb.jpg"
        }
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

    /// - Parameter withThumbnail: 一覧用の 512px も作るか。**写真の投稿・差し替えだけ** true
    ///   （ストーリー・アイコン・カバーは `thumbSrc` を持たないので作らない——縮小と読み直しが1回ずつ無駄になる）
    static func prepare(data: Data, fileName: String, withThumbnail: Bool = false) throws -> Prepared {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw PrepareError.unreadable
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let exif = readExif(from: properties)
        let coords = readCoords(from: properties)
        let takenOn = readTakenOn(from: properties)

        let jpeg = try reencodeAsJPEG(source: source, maxPixelSize: maxPixelSize, quality: jpegQuality)
        try assertStripped(jpeg)
        // **縮めた本体から作る**（Web と同じ。原本の 24〜48MP をもう一度読まない）。
        // 本体は向きを焼き込み済みで EXIF も無い。**同じ関所（`assertStripped`）を通す**
        // ——通らなければサムネを上げない（素通ししない）
        let thumbnail = withThumbnail ? makeThumbnail(fromJPEG: jpeg) : nil

        return Prepared(
            data: jpeg,
            fileName: jpegFileName(from: fileName),
            contentType: "image/jpeg",
            exif: exif.isEmpty ? nil : exif,
            coords: coords,
            takenOn: takenOn,
            // **原本から取る。** 焼き込みや再圧縮のあとでは色がわずかに動く
            // ——読み込み中の地の色なので実害は無いが、Web と同じものを出す
            dominantColor: DominantColorExtractor.hex(from: data),
            thumbnail: thumbnail
        )
    }

    /// 一覧用の 512px。作れない・メタデータを消せたと確かめられないときは nil
    private static func makeThumbnail(fromJPEG jpeg: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let thumb = try? reencodeAsJPEG(source: source, maxPixelSize: thumbnailMaxPixelSize,
                                              quality: thumbnailQuality),
              (try? assertStripped(thumb)) != nil else { return nil }
        return thumb
    }

    // MARK: - 変換

    /// `maxPixelSize` に収めて JPEG に焼き直す（本体は 1920px・サムネは 512px）。
    ///
    /// サムネイル API を使うのは、**出力に元のメタデータが引き継がれない**
    /// から。`CGImageDestination` に元の properties を渡さなければ EXIF は付かない。
    /// 回転は画素に焼き込む（`WithTransform`）——落とした EXIF に
    /// Orientation も含まれるので、焼かないと横倒しになる。
    private static func reencodeAsJPEG(source: CGImageSource, maxPixelSize: Int, quality: Double) throws -> Data {
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
            kCGImageDestinationLossyCompressionQuality: quality
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
