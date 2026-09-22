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
    /// 🔴 **journey-photo.com のリンクは入れない。** スポットのページ
    /// （`/spots/<スラッグ>`）はまだ作っていない（Phase 1.5）ので、
    /// 入れると**開けないリンクを配る**ことになる。名前・地域・地図の
    /// リンクだけにして、受け取った人がその場所へ行けるようにする。
    static func shareText(name: String, region: String?, mapURL: URL?) -> String {
        var parts = [name.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
        if let region = region?.trimmingCharacters(in: .whitespaces), !region.isEmpty {
            parts.append(region)
        }
        if let mapURL { parts.append(mapURL.absoluteString) }
        return parts.joined(separator: "\n")
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
}
