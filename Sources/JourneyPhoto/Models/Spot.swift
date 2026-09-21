import Foundation

/// 撮影スポット（地点そのもの）。Web の `lib/data/spots.ts` の `Spot` に対応する。
///
/// 写真の `location` は**撮影者が打った文字列**で、実データでは
/// 「東京」「フランス」「北海道」のような**地域**が大半だった
/// （2026-09-21 実測・14種のうち個別の地点は4つ）。台帳はその隙間を埋める
/// ——地点に ID・住所・地域・種別を持たせ、写真から `spotId` で指す。
struct Spot: Identifiable, Decodable, Equatable {

    /// 台帳の鍵。**名前から作らない**ので、改名しても変わらない
    let spotId: String
    /// URL に出る綴り。作ったときに決めて、改名しても変えない
    let slug: String
    /// 正式名
    let name: String
    /// 別名・旧称・英語表記
    let aliases: [String]?
    /// 住所（1行）
    let address: String?
    let region: Region?
    /// 公開座標（写真と同じ約1km精度）
    let coords: Photo.Coords?
    /// 種別（神社 / 公園 / 山 …）
    let category: String?
    /// 代表写真の id
    let coverPhotoId: String?
    let createdAt: String?
    let updatedAt: String?

    var id: String { spotId }

    struct Region: Decodable, Equatable {
        let country: String?
        let prefecture: String?
        let city: String?

        /// 画面に出す1行（「香川県 観音寺市」）。**空の階層は詰める**
        var line: String {
            [country, prefecture, city]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
}
