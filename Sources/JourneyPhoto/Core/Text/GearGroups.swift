import Foundation

/// 「機材から探す」（モック9）。
///
/// **レンズの名前では分けない。** 実データのレンズ名は27枚で数種類しか無く、
/// しかも「FE 24-105mm F4 G OSS」のようなズームは1本で広角も望遠も撮れる。
/// 分けるなら**その1枚を実際に何ミリで撮ったか**（`exif.focalLength`）。
/// 実データでは **27/30枚**が焦点距離を持っている（2026-09-21 実測）。
///
/// **注意して読むこと**: EXIF の焦点距離は**実焦点距離**で、35mm 換算ではない。
/// 小さなセンサー（スマホ）の「7mm」は、画角としては広角にあたる。
/// 実データの `7mm` は iPhone 14 Pro の1枚で、広角に入るのは結果として正しい。
/// センサーの大きさを見ずに分けている、という限界はここに書いておく。
enum GearGroups {

    enum Group: String, CaseIterable, Identifiable {
        case wide
        case standard
        case telephoto

        var id: String { rawValue }

        var label: String {
            switch self {
            case .wide: return L("広角で撮る", "Wide")
            case .standard: return L("標準で撮る", "Standard")
            case .telephoto: return L("望遠で撮る", "Telephoto")
            }
        }

        var note: String {
            switch self {
            case .wide: return L("ダイナミックな風景", "Sweeping landscapes")
            case .standard: return L("旅の定番スナップ", "Everyday snapshots")
            case .telephoto: return L("遠くの絶景を", "Distant views")
            }
        }

        /// 画面に出す範囲。**分け方を隠さない**
        var range: String {
            switch self {
            case .wide: return "〜35mm"
            case .standard: return "36〜70mm"
            case .telephoto: return "71mm〜"
            }
        }
    }

    /// 「35mm」「f=35 mm」などから数を取り出す。読めなければ nil
    static func millimeters(_ text: String?) -> Double? {
        guard let text else { return nil }
        var digits = ""
        for character in text {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        guard let value = Double(digits), value > 0 else { return nil }
        return value
    }

    static func group(of photo: Photo) -> Group? {
        guard let mm = millimeters(photo.exif?.focalLength) else { return nil }
        if mm <= 35 { return .wide }
        if mm <= 70 { return .standard }
        return .telephoto
    }

    struct Section: Identifiable, Equatable {
        let group: Group
        let photos: [Photo]
        var id: String { group.rawValue }
        var count: Int { photos.count }
    }

    /// 棚に並べる。**写真が1枚も無い群は出さない**（空の棚を作らない）
    static func sections(in photos: [Photo], limit: Int = 12) -> [Section] {
        Group.allCases.compactMap { group in
            let matched = GallerySort.popular.apply(photos.filter { self.group(of: $0) == group })
            guard !matched.isEmpty else { return nil }
            return Section(group: group, photos: Array(matched.prefix(limit)))
        }
    }
}
