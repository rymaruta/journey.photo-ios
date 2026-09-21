import Foundation

/// 一覧の組み方（リズム）。
///
/// **等間隔の格子をやめる。** 2列の格子は破綻しないが、どの写真も同じ
/// 大きさなので「並んでいる」以上の意味が出ない。owner の求めは
/// 「モダンで革新的」——**写真に強弱を付ける**のがいちばん効く。
///
/// **写真の縦横比は使えない。** 公開 JSON に寸法が無い
/// （`app/data/photos.json` の30枚を実測。`exif.imageSize` は0件）。
/// 読み込んでから測ると、来るたびに高さが変わって画面が跳ねる。
/// だから**位置で決まるリズム**にする——見た目は不揃いでも、
/// 組みは最初から決まっているので跳ねない。
///
/// リズムは5枚でひと回り:
///
///     ┌───────────────┐   0 … 大きく1枚（16:9）
///     ├───────┬───────┤   1,2 … 2枚ずつ（1:1）
///     ├───────┼───────┤   3,4
///     └───────┴───────┘
///
/// **端数で崩さない。** 残り1枚なら、その1枚だけで横いっぱいの段にする
/// （半分だけ写真がある段を作らない）。
enum EditorialLayout {

    enum Row: Identifiable, Equatable {
        /// 横いっぱいの1枚
        case hero(Photo)
        /// 横に2枚（2枚目が無ければ1枚で横いっぱい）
        case pair(Photo, Photo?)

        var id: String {
            switch self {
            case .hero(let photo): return "hero-\(photo.id)"
            case .pair(let first, let second): return "pair-\(first.id)-\(second?.id ?? "")"
            }
        }
    }

    /// ひと回りの枚数。**大きい1枚 ＋ 2枚×2段**
    static let cycle = 5

    static func rows(_ photos: [Photo]) -> [Row] {
        var rows: [Row] = []
        var queue = photos[...]
        while let first = queue.first {
            queue = queue.dropFirst()
            // ひと回りの先頭は大きく
            if rows.isEmpty || (rows.count % 3) == 0 {
                rows.append(.hero(first))
                continue
            }
            let second = queue.first
            if second != nil { queue = queue.dropFirst() }
            rows.append(.pair(first, second))
        }
        return rows
    }

    /// 段の高さの比（横幅に対する割合）。
    /// 大きい段は 16:9 寄り、2枚の段は正方形。
    static func aspect(for row: Row) -> Double {
        switch row {
        case .hero: return 16.0 / 10.0
        case .pair: return 1.0
        }
    }
}
