import Foundation

/// 撮影スポット詳細（モック5）の、**画面から出せる決まりごと**。
///
/// ## なぜ出すのか
///
/// 🔴 **この画面は実機の絵で確かめられない。** 台帳が0件なので、
/// いま出す地点が1つも無い（`docs/MOCK_PARITY.md`）。巡回で撮ろうとして
/// 2回失敗もしている。だから**せめて中身の決まりだけは動かして確かめる**
/// ——`Shims/` の模型では `View` の中を動かせないので、ここに置いたぶんだけが
/// Linux の `swift test` で確かめられる（`StoryQueue` と同じ判断）。
enum SpotScreen {

    /// 「1/10」。**数えた数だけ**（紐づいた公開写真の枚数そのもの）。
    ///
    /// **並びの外を指さない。** 絞り込みで写真が減った回に
    /// 「5/3」と出さないため、いまの位置は枚数で止める。
    static func pagerLabel(page: Int, count: Int) -> String? {
        guard count > 0 else { return nil }
        let shown = min(max(page + 1, 1), count)
        return "\(shown)/\(count)"
    }

    /// シェアで配る文（モック5-6）。
    ///
    /// **公開スポットはサイトのページ（`/spots/<スラッグ>`）を入れる**（`pageURL`）。
    /// 以前は「ページがまだ無い」ので入れていなかったが、Web の main に
    /// `app/spots/[slug]` ができた（2026-09）。**下書きはページが建たない**
    /// （Web の `BUILD_DRAFT_SPOTS = false`）ので、呼ぶ側は `pageURL` で
    /// 公開のときだけ渡す。名前・地域・地図のリンクはそのまま。
    static func shareText(name: String, region: String?, mapURL: URL?, pageURL: URL? = nil) -> String {
        var parts = [name.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
        if let region = region?.trimmingCharacters(in: .whitespaces), !region.isEmpty {
            parts.append(region)
        }
        if let pageURL { parts.append(pageURL.absoluteString) }
        if let mapURL { parts.append(mapURL.absoluteString) }
        return parts.joined(separator: "\n")
    }

    /// 撮影スポットのサイトのページ。**公開（`published`）のときだけ**。
    /// 形は Web と同じ `<サイト>/spots/<スラッグ>`（`trailingSlash` なし）。
    /// 下書き・スラッグ無しは nil——開けないリンクを配らない
    static func pageURL(slug: String, isDraft: Bool, siteBase: URL) -> URL? {
        let slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDraft, !slug.isEmpty else { return nil }
        return siteBase.appendingPathComponent("spots").appendingPathComponent(slug)
    }

    /// 端末の地図アプリへの行き先。**座標があるときだけ**
    /// （無い地点に「地図で見る」を出さない）。
    static func mapURL(name: String, coords: Photo.Coords?) -> URL? {
        guard let coords else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coords.lat),\(coords.lng)"),
            URLQueryItem(name: "q", value: name),
        ]
        return components?.url
    }

    // MARK: - 台帳の撮影スポット（モック13・`OfficialSpotView`）

    /// 小見出し（モックの "PHOTO SPOT"）。
    ///
    /// 🔴 **下書きを「公式」と名乗らない。** 索引の全件が運営未確認の下書き
    /// （機械が1日で書いた・2026-09-25）なので、`published` になるまで
    /// 小見出しの段階でそう言う（`isDraft`）
    static func eyebrow(review: Bool) -> String {
        review ? L("下書き・未確認", "DRAFT · UNREVIEWED") : L("撮影スポット", "PHOTO SPOT")
    }

    /// 下書きの注意文。**下書きでなければ nil**（帯ごと出さない）。
    ///
    /// **日付は文に組み込んで返す**——生の値を `Text` に渡さない（4.6d の趣旨）。
    /// 時刻まで入った値が来ても日付までに切り、読めない値なら括弧ごと落とす
    static func reviewNotice(review: Bool, draftedAt: String?) -> String? {
        guard review else { return nil }
        guard let (y, m, d) = TakenDay.ymd(draftedAt) else {
            return L("運営の下書きです。まだ確認していません", "Unreviewed draft by our team")
        }
        let day = String(format: "%04d-%02d-%02d", y, m, d)
        return L("運営の下書きです。まだ確認していません（下書き作成 \(day)）",
                 "Unreviewed draft by our team (drafted \(day))")
    }

    /// 「[都道府県] · [市区町村] · N枚の写真」。地域が無ければ枚数だけ
    /// （N は `Photo.spotId` で紐づいた公開写真を数えた値）
    /// `photoCount` が nil なら枚数を言わない（写真の一覧を持たない画面から開いたとき。0 と言うと事実と違う）
    static func subtitle(region: String?, photoCount: Int?) -> String {
        var parts: [String] = []
        if let region = region?.trimmingCharacters(in: .whitespaces), !region.isEmpty {
            parts.append(region)
        }
        if let photoCount {
            parts.append(L("\(photoCount)枚の写真", photoCount == 1 ? "1 photo" : "\(photoCount) photos"))
        }
        return parts.joined(separator: " · ")
    }

    /// `OfficialSpotView` の `photosKnown` に渡す値。**写真の一覧が取れなかった回だけ false**
    /// ——取れなかったのに空を渡すと「この場所の写真（0）まだありません」と言っていた
    /// （`StoryViewerView` が `photosKnown: false` を渡すのと同じ理由）。
    /// 取れていて空なら本当に0件なので true のまま
    static func photosKnown(loadFailed: Bool, photos: [Photo]) -> Bool {
        !(loadFailed && photos.isEmpty)
    }
}
