import Foundation

/// タグ・色・機材・いまの季節の写真（板 12）の、画面を持たない部分。
///
/// 見出しの小さい字・先頭の大きい1枚の文字・シェアで配るもの。
/// どの入口から来ても同じ形にする（`CollectionPhotosScreen`）。
enum CollectionScreen {

    /// 題の下の小さい字（板 12 の「00枚 · いまの季節」）。
    /// **枚数は並ぶ写真を数えたもの。** 添え書きが無ければ枚数だけ。
    /// **読み込み中は枚数を出さない**——まだ数えていないものを「0枚」と言わない
    /// （添え書きだけ、それも無ければ空）
    static func subtitle(count: Int, note: String?, isLoading: Bool = false) -> String {
        let extra = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if isLoading { return extra }
        let counted = L("\(count)枚", "\(count) photos")
        return extra.isEmpty ? counted : "\(counted) · \(extra)"
    }

    /// 先頭の大きい1枚に載せる大きい字（板 12 の「[撮影地]」）。
    /// **撮影地が無ければ題**、どちらも無ければ出さない（空の帯を作らない）
    static func leadHeadline(_ photo: Photo) -> String? {
        let place = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { return place }
        let title = photo.displayTitle
        return title.isEmpty ? nil : title
    }

    /// 先頭の1枚の「@投稿者」。**写真に添えられた名前があるときだけ**
    /// ——代わりの言葉（「ユーザー」）に @ を付けて人の名前のように見せない
    static func leadAuthor(_ photo: Photo) -> String? {
        let name = (photo.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : "@\(name)"
    }

    /// その集約の Web のページ。**撮影地だけ**——`/location/<スラッグ>` は
    /// `LocationSlug` が Web の `slugify` と同じ綴りを作る。
    /// タグ・カテゴリは Web 側に別名の表（`CATEGORY_ALIASES` ほか）があり、
    /// アプリに写していないので**綴りを当て推量しない**（404 を配らない）
    static func pageURL(_ kind: PhotoQuery.Collection?) -> URL? {
        guard case .location(let value)? = kind else { return nil }
        let slug = LocationSlug.make(value)
        guard !slug.isEmpty else { return nil }
        // **先に符号化しない。** `appendingPathComponent` が自分で符号化するので、
        // 先にやると `%` がもう一度 `%25` になる（Linux で確かめた）
        return AppConfig.siteBaseURL.appendingPathComponent("location/\(slug)")
    }

    /// シェアで配る文字。題と枚数に、**開ける URL を1つ**添える
    /// ——集約のページがあればそれ、無ければ先頭の写真のページ。
    /// 写真の URL は公開の一覧に載っている写真だけ（`PhotoLink`）
    static func shareText(title: String, count: Int, kind: PhotoQuery.Collection?, lead: Photo?) -> String {
        var lines = ["\(title) · \(L("\(count)枚", "\(count) photos"))"]
        if let url = pageURL(kind) ?? lead.flatMap({
            // 公開範囲を絞った写真は、どの URL でも開けないので配らない（`PhotoDetailView.shareURL`）
            RestrictedFeed.isRestricted($0) ? nil : PhotoLink.url(photoId: $0.id, isPublished: $0.published != false)
        }) {
            lines.append(url.absoluteString)
        }
        return lines.joined(separator: "\n")
    }
}
