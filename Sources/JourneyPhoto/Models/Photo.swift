import Foundation

/// 1枚の写真。`api-user/src/types.ts` の `Photo` に対応する。
///
/// **非公開のフィールドは持たない。** `srcOriginal`（EXIF 除去前の原本・GPS 入り）
/// と `key` は公開 JSON から落とされている（`lib/server/photos.ts` の
/// `PRIVATE_FIELDS`）。ここで定義すると「取れるはず」と勘違いした実装を誘うので、
/// 自分の写真を編集する経路で必要になるまで足さない。
struct Photo: Identifiable, Decodable, Equatable {
    let id: String
    /// 詳細表示用の画像（≤1600）
    let src: String
    /// 一覧グリッド用の軽量サムネイル（512px WebP）。無い写真は src を使う
    let thumbSrc: String?
    let src256: String?
    let thumbAvif: String?
    let thumbSm: String?
    let thumbSmAvif: String?
    let srcAvif: String?
    /// 極小ぼかしプレビュー（data:image/webp;base64,...）
    let blurDataURL: String?

    let title: LocalizedText?
    let description: LocalizedParagraphs?
    let category: String?
    let tags: [String]?
    let location: String?
    let published: Bool?

    let userId: String?
    let uploadedBy: String?
    let displayName: String?
    let createdAt: String?
    let updatedAt: String?
    /// 撮影日（YYYY-MM-DD）。持っている写真は少ない（実データで 8/30）
    let date: String?

    /// 撮影地（約1km精度に丸め済み）
    let coords: Coords?
    /// 正方形に切り抜くときの中心（0〜1）。未設定なら中央
    let focalPoint: FocalPoint?
    let exif: Exif?
    /// 写真に付けた曲。30秒の試聴だけを持つ（`previewUrl` は必須）
    let song: Song?

    struct Coords: Decodable, Equatable {
        let lat: Double
        let lng: Double
    }

    struct FocalPoint: Decodable, Equatable {
        let x: Double
        let y: Double
    }

    struct Song: Codable, Equatable {
        init(title: String, artist: String?, artwork: String?, previewUrl: String, trackUrl: String?) {
            self.title = title
            self.artist = artist
            self.artwork = artwork
            self.previewUrl = previewUrl
            self.trackUrl = trackUrl
        }

        let title: String
        let artist: String?
        let artwork: String?
        /// 30秒の試聴。**https のみ**（サーバーが検証している）
        let previewUrl: String
        let trackUrl: String?

        var previewURL: URL? { URL(string: previewUrl) }
        var artworkURL: URL? { artwork.flatMap(URL.init(string:)) }
    }

    struct Exif: Decodable, Equatable {
        let camera: String?
        let lens: String?
        let aperture: String?
        let exposure: String?
        let iso: Int?
        let focalLength: String?
        let whiteBalance: String?
        let imageSize: String?
        let dateTimeOriginal: String?
    }

    // MARK: - 表示のための導出

    /// **サーバーが入れていた「無題」は題として扱わない**（`PhotoTitle`）。
    var displayTitle: String { PhotoTitle.display(title?.resolved()) }
    var paragraphs: [String] { description?.resolved() ?? [] }

    /// 一覧に出す画像。軽い順に落としていく。
    var gridImageURL: URL? {
        URL(string: thumbSrc ?? src256 ?? src)
    }

    /// 一覧で切り抜くときに残す側。**持ち主が選んだ位置**（`focalPoint`）。
    var gridCrop: FocalCrop {
        guard let focalPoint else { return .center }
        return FocalCrop.bucket(x: focalPoint.x, y: focalPoint.y)
    }

    var detailImageURL: URL? {
        URL(string: src)
    }

    /// 読み上げ用の代替テキスト。題が無ければ撮影地で補う
    /// （Web 側 `lib/utils/photoAlt.ts` と同じ考え方）。
    var accessibilityText: String {
        let title = displayTitle
        if !title.isEmpty { return title }
        if let location, !location.isEmpty { return L("\(location) の写真", "Photo taken at \(location)") }
        return L("写真", "Photo")
    }
}

/// 1件ずつ復号して、**読めなかった行だけを落とす**入れ物。
///
/// `[Photo]` としてまとめて復号すると、**1行の型違いで一覧が丸ごと消える**。
/// Web 側も同じ判断をしている（`lib/utils/apiRows.ts` の `usablePhotoRows`
/// ——「おかしい項目だけを落とし、読める項目は出す」）。
struct LenientPhotoList: Decodable {

    let photos: [Photo]
    /// 落とした行の数。**黙って捨てない**ために数えておく
    let dropped: Int

    init(from decoder: Decoder) throws {
        // **要素の復号を絶対に失敗させない形にする。** 失敗させて
        // `catch` で読み飛ばす書き方だと、失敗時に添字が進んだかどうかが
        // `JSONDecoder` の実装依存になり、good な行を1つ余計に捨てうる。
        let rows = try [Row](from: decoder)
        photos = rows.compactMap(\.photo)
        dropped = rows.count - photos.count
    }

    private struct Row: Decodable {
        let photo: Photo?
        init(from decoder: Decoder) throws {
            photo = try? Photo(from: decoder)
        }
    }
}
