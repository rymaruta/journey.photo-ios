import Foundation

/// **旅行プランが写真で埋まる**（札 #710 の案3・2026-11-23 owner 承認）。
///
/// 旅行プランの各場所に、自分が投稿した写真のうち「同じ観光スポット（または撮影地の鍵）で、プランのその日に撮ったもの」を出す。
/// まだの場所は、**今日の分だけ**点線の枠を出し、押すと観光スポットを撮影地に入れた投稿の画面が開く。
///
/// 2026-11-23 判断:
/// - 出すのは**自分の写真だけ**。プランを仲間と共有していても、他人の写真は出さない
///   （CLAUDE.md「他人の写真は、その人のもの」。他人の写真は持ち主の写真へのリンクにとどめる）
/// - 突き合わせは端末だけ。サーバー・DB は変えない。プランに写真を保存しない
/// - 日付の無いプラン・日は突き合わせない（どの日の写真か言えないので、作り話をしない）
/// - 点線の枠は観光スポットの場所だけ（投稿の画面に渡せる行き先は観光スポット `UploadSpotTarget`。撮影地の鍵だけの場所は
///   写真が並ぶだけ）
enum TripPlanPhotos {

    /// その場所で、その日に撮った自分の写真（いちばん新しい1枚）。日付が無ければ nil
    static func mine(for item: TripItem, on day: String?, mine: [Photo]) -> Photo? {
        guard let day, let (y, m, d) = TakenDay.ymd(day) else { return nil }
        let onDay = mine.filter { photo in
            guard let taken = TakenDay.ymd(photo.date) else { return false }
            return taken == (y, m, d)
        }
        guard !onDay.isEmpty else { return nil }
        let hits: [Photo]
        switch item {
        case .spot(let spotId, _):
            hits = onDay.filter { $0.spotId == spotId }
        case .location(let slug, _):
            hits = DerivedSpot.allMergedBySlug(in: onDay).first { $0.slug == slug }?.photos ?? []
        }
        return hits.max { a, b in sortKey(a) < sortKey(b) }
    }

    /// 新しさの物差し（撮影日時、無ければ投稿日時）
    private static func sortKey(_ photo: Photo) -> String {
        photo.exif?.dateTimeOriginal ?? photo.createdAt ?? ""
    }

    /// 点線の枠（「ここで撮った1枚を載せる」）を出すか。**今日の日の、まだ写真の無い観光スポットだけ**
    static func invites(_ item: TripItem, on day: String?, today: String, hasPhoto: Bool) -> Bool {
        guard !hasPhoto, let day, day == today else { return false }
        if case .spot = item { return true }
        return false
    }

    /// 行の写真（番号の丸の右・44pt）。**自分がそこで撮った写真があればそれ、無ければ観光スポットの写真**。
    /// 撮影地だけの場所で自分の写真も無ければ nil（今の形のまま）。
    ///
    /// 2026-11-23（owner「AIでプラン作った時に画像出てこないぞ」）: AI が作っている途中の行は観光スポットの写真を出していたのに、
    /// 作り終えた日程の行には写真を出す仕組みが無く、写真が消えて見えた。作っている途中の行と同じ形にそろえる
    static func thumb(mine: Photo?, spot: OfficialSpot?) -> TripStopThumb? {
        if let mine { return .mine(mine) }
        if let image = spot?.photo { return .spot(image) }
        return nil
    }

    /// 行の下の一行「あなたの1枚　8:12」（時刻が分からなければ「あなたの1枚」だけ）
    static func line(_ photo: Photo) -> String {
        let head = L("あなたの1枚", "Your photo")
        guard let time = clock(photo.exif?.dateTimeOriginal) else { return head }
        return head + "\u{3000}" + time
    }

    /// 枠の横の誘いの字
    static var inviteLine: String { L("ここで撮った1枚を載せる", "Post a photo you took here") }

    /// `2026-11-23T08:12:00` → `8:12`
    static func clock(_ raw: String?) -> String? {
        guard let raw, let t = raw.firstIndex(of: "T") ?? raw.firstIndex(of: " ") else { return nil }
        let nums = raw[raw.index(after: t)...].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 2, (0...23).contains(nums[0]), (0...59).contains(nums[1]) else { return nil }
        return String(format: "%d:%02d", nums[0], nums[1])
    }
}

/// 旅行プランの行の写真（`TripPlanPhotos.thumb`）
enum TripStopThumb {
    /// 自分がその日そこで撮った写真
    case mine(Photo)
    /// 観光スポットの写真（台帳の公開の写真。出典は開いた先の観光スポットの頁に出す・行きたい場所の行と同じ扱い）
    case spot(SpotImage)

    var isMine: Bool {
        if case .mine = self { return true }
        return false
    }
}
