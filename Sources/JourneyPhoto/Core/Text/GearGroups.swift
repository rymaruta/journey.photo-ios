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

        /// 一覧の上に置く一言。
        ///
        /// 2026-10-07 判断: **焦点距離そのものを言う。** 以前は「ダイナミックな風景」「遠くの絶景を」
        /// で、中身（料理・接写も焦点距離で入る）と合わなかった。並ぶのは何を撮ったかではなく
        /// 何ミリで撮ったかなので、画角の話だけをする
        var note: String { L(noteText.ja, noteText.en) }

        /// 一言の日英（テストで英語の側も確かめるため対で持つ）
        var noteText: (ja: String, en: String) {
            switch self {
            case .wide: return ("広く写す", "Takes in a wide view")
            case .standard: return ("見た目に近い広さで写す", "Close to what the eye sees")
            case .telephoto: return ("遠くを引き寄せる", "Brings distant subjects closer")
            }
        }

        /// 画面に出す範囲。**分け方を隠さない**。英語表示では「〜」を使わない
        var range: String { L(rangeText.ja, rangeText.en) }

        var rangeText: (ja: String, en: String) {
            switch self {
            case .wide: return ("〜35mm", "up to 35mm")
            case .standard: return ("36〜70mm", "36–70mm")
            case .telephoto: return ("71mm〜", "71mm+")
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
