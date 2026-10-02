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
    /// 代表色（`#rrggbb`）。**読み込み中の地の色**と「色から探す」に使う。
    /// 持たない写真もある（アプリが送り始めたのは 2026-09-22 から）
    let dominantColor: String?

    let title: LocalizedText?
    let description: LocalizedParagraphs?
    let category: String?
    let tags: [String]?
    let location: String?
    let published: Bool?

    /// いいねの数。**並び替えの「人気順」で使う。**
    /// `scripts/sync-photos-from-ddb.js` が公開 JSON に載せている
    /// （落とすと人気順が**黙って効かなくなる**ので落としていない、と
    ///  あちらのコメントが書いている）。持たない写真は 0 として扱う。
    ///
    /// **`var` なのは、公開 JSON の数が古いから。** JSON はサイトを建てた
    /// 時点の数で、いいねでは建て直らない。`PublicGalleryService` が
    /// 管理 API の `GET /photos`（DynamoDB を直に読む）の数で上書きする
    /// （`LiveLikes`）。Web の `usePhotos` が同じ口で差し替えているのと同じ
    var likes: Int?
    /// `likes` が**いつ時点の数か**（いまの数を取りに行った時刻）。
    /// 静的 JSON のままなら nil（＝サイトを建てた時点・どの答えより古い）。
    /// サーバーに無い項目なので、読むときは常に nil で来る
    var likesAsOf: Date?
    /// owner が手で選んだ「おすすめ」。トップのカテゴリ別の特集に出る
    /// （Web の `lib/utils/featured.ts`）。
    let featured: Bool?

    /// 同じ投稿としてまとめる印。**行は1枚ずつのまま**
    /// （個別ページもサイトマップもこれまでどおり）で、
    /// アプリだけが1つのカードに束ねる
    let groupId: String?

    /// 公開範囲（`followers` / `closeFriends`）。**付いていない＝全体に公開**。
    ///
    /// 付いている行は静的サイトの一覧に載らないので、ここに値が入るのは
    /// `GET /feed/restricted` と `GET /user/photos` から来た写真だけ。
    let audience: String?

    let userId: String?
    let uploadedBy: String?
    /// `var` は編集の控えを一覧に重ねるとき、一覧の今の名前を残すため（`PhotoEditOverlay.overlaid`）
    var displayName: String?
    let createdAt: String?
    let updatedAt: String?
    /// 撮影日（YYYY-MM-DD）。持っている写真は少ない（実データで 8/30）
    let date: String?

    /// 撮影地（約1km精度に丸め済み）
    let coords: Coords?
    /// 撮影スポット台帳（`app/data/spots.json`）への参照。
    ///
    /// **確定した紐づけにだけ入る。** 空の写真は今までどおり
    /// `location` の文字列だけを持つ——台帳はその上に足す情報で、
    /// 撮影地を置き換えるものではない。
    let spotId: String?
    /// 正方形に切り抜くときの中心（0〜1）。未設定なら中央
    let focalPoint: FocalPoint?
    let exif: Exif?
    /// 写真に付けた曲。30秒の試聴だけを持つ（`previewUrl` は必須）
    let song: Song?
    /// 元画像の表示寸法（EXIF の回転を反映済み）。**ビルドが書く**（`scripts/generate-thumbnails.js`
    /// の `buildMetaFields`）ので、持たない写真も多い（`photos.json` の実測で 0/30 の頃がある）
    let width: Double?
    let height: Double?

    /// 縦横比（幅 ÷ 高さ）。寸法が無い・おかしいときは nil。
    /// **読み込む前に枠を取る**ために使う（旅の本で、遅れて出た絵が下のページを押し下げないように）
    var aspectRatio: Double? {
        guard let width, let height, width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let ratio = width / height
        // 極端な値（壊れた寸法）では枠を取らない——細すぎる・平たすぎる枠より、今の出し方の方がまし
        return (0.2...5).contains(ratio) ? ratio : nil
    }

    /// **送る側にもなる。** 写真を直すときに座標も一緒に送るので
    /// `Encodable` が要る（`PhotoPatch.coords`）。
    struct Coords: Codable, Equatable {
        let lat: Double
        let lng: Double
    }

    struct FocalPoint: Decodable, Equatable {
        let x: Double
        let y: Double
    }

    struct Song: Codable, Equatable {
        init(title: String, artist: String?, artwork: String?, previewUrl: String, trackUrl: String?,
             startSec: Int? = nil) {
            self.title = title
            self.artist = artist
            self.artwork = artwork
            self.previewUrl = previewUrl
            self.trackUrl = trackUrl
            self.startSec = startSec
        }

        private enum CodingKeys: String, CodingKey {
            case title, artist, artwork, previewUrl, trackUrl, startSec
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            artist = try c.decodeIfPresent(String.self, forKey: .artist)
            artwork = try c.decodeIfPresent(String.self, forKey: .artwork)
            previewUrl = try c.decode(String.self, forKey: .previewUrl)
            trackUrl = try c.decodeIfPresent(String.self, forKey: .trackUrl)
            // **読めない値で曲ごと落とさない**（無いのと同じに扱う）
            startSec = Self.clampStart((try? c.decodeIfPresent(Double.self, forKey: .startSec)) ?? nil)
        }

        let title: String
        let artist: String?
        let artwork: String?
        /// 30秒の試聴。**https のみ**（サーバーが検証している）
        let previewUrl: String
        let trackUrl: String?
        /// 「好きな部分」＝30秒の試聴の中で鳴らし始める位置（秒・1〜29）。Web のストーリーで
        /// 選べる（`stories.ts` が 0〜29 に丸めて保存）。**読まずにいたので、アプリで見る人には
        /// いつも曲の頭が流れていた**（Web はこの位置から流す）
        let startSec: Int?

        /// サーバーと同じ丸め（`stories.ts`: 0 以下は無し・29 まで・四捨五入）
        static func clampStart(_ raw: Double?) -> Int? {
            guard let raw, raw.isFinite, raw > 0 else { return nil }
            let start = min(29, Int(raw.rounded()))
            return start > 0 ? start : nil
        }

        /// 試聴の長さ（秒）
        static let previewSeconds = 30

        /// 流し始めの上限。**表示秒数ぶんが試聴の中に収まる所まで**（Web の `maxSongStart`
        /// ＝ 30 − 表示秒数・`songTrim.ts`）。越えると、見る人には試聴の終わりの数秒が
        /// くり返し鳴る（841b917 のレビュー）
        static func maxStart(window: Int) -> Int {
            max(0, previewSeconds - max(0, window))
        }

        /// 流し始めを変えた曲（ストーリーの「流し始め」・owner の「自由度が低い」2026-09-29）。
        /// `window`（表示秒数）が収まる所までに寄せ、**丸めはサーバーと同じ `clampStart`**
        /// （0 は「頭から」＝無し）
        func starting(at seconds: Double?, window: Int) -> Song {
            let capped = seconds.map { min($0, Double(Self.maxStart(window: window))) }
            return Song(title: title, artist: artist, artwork: artwork, previewUrl: previewUrl,
                        trackUrl: trackUrl, startSec: Self.clampStart(capped))
        }

        /// 表示秒数が収まる流し始めにした曲。**収まっていればそのまま**（同じ値を返す＝
        /// 閉じるときの「変更あり」を作らない）。下書きを戻したとき・表示秒数を延ばしたときに通す
        func fitting(window: Int) -> Song {
            guard let start = startSec, start > Self.maxStart(window: window) else { return self }
            return starting(at: Double(start), window: window)
        }

        /// 「0:12 から」の言い方（流し始めを選ぶ画面・曲のメニュー）
        static func startLabel(_ seconds: Int?) -> String {
            let sec = max(0, seconds ?? 0)
            guard sec > 0 else { return L("頭から", "From the start") }
            let time = String(format: "%d:%02d", sec / 60, sec % 60)
            return L("\(time) から", "From \(time)")
        }

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

    /// 地図のピンの画像（44pt の角丸）。**256px（`thumbSm`）から**——512px を読む必要は無い。
    /// 無ければ一覧と同じものに落とす（Web の `PhotoMap.tsx` の `thumbSm || thumbSrc || src` と同じ順）
    var pinImageURL: URL? {
        URL(string: thumbSm ?? thumbSrc ?? src256 ?? src)
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
