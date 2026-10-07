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
    ///
    /// 2026-10-07 判断: 撮影地のページも、**並ぶ写真に公開の写真（`SpotScreen.isOnPublicSite`）が
    /// 1枚以上あるときだけ**（`SpotScreen.locationPageURL` と同じ決まり）。下書き・限定写真の詳細から
    /// 開いた一覧は、Web に建たない `/location/<スラッグ>` を配っていた
    static func pageURL(_ kind: PhotoQuery.Collection?, photos: [Photo]) -> URL? {
        guard case .location(let value)? = kind else { return nil }
        return SpotScreen.locationPageURL(slug: LocationSlug.make(value), photos: photos,
                                          siteBase: AppConfig.siteBaseURL)
    }

    /// 詳細から開いた一覧に、**開いた写真自身**を足す（2026-10-07）。
    ///
    /// 2026-10-07 判断: 下書き・公開範囲を絞った写真は公開の一覧（`fetchPhotos`）に載らないので、
    /// その詳細から撮影地の行を押すと、押した写真さえ無い空の一覧になっていた。行を押せない文字に
    /// するより、**押した写真が並ぶ**ほうが「この撮影地の写真」として自然（同じ撮影地の公開の写真が
    /// あれば一緒に並ぶ）。足すのは公開の一覧に載らない写真で、その集約に当たり、まだ並んでいない
    /// ときだけ。公開の写真は一覧から来るので足さない（消された・非公開にされた写真を残さない）。
    /// 足した写真は配れないので、共有の URL は付かない（`pageURL`・`isShareable`）
    static func withOpened(_ list: [Photo], opened: Photo?, kind: PhotoQuery.Collection) -> [Photo] {
        guard let opened, !SpotScreen.isOnPublicSite(opened),
              !list.contains(where: { $0.id == opened.id }),
              !PhotoQuery.photos([opened], in: kind).isEmpty else { return list }
        return [opened] + list
    }

    /// 配ってよい写真か。**公開範囲を絞った写真と下書きは、どの URL でも Web で開けない**
    /// （Web が読む一覧は公開の写真だけ——`?photo=` に振り替えても「見つかりませんでした」）
    static func isShareable(_ photo: Photo) -> Bool {
        photo.published != false && !RestrictedFeed.isRestricted(photo)
    }

    /// 共有に添える写真。**先頭ではなく、最初に配ってよい写真**（先頭が絞った写真だと、
    /// 残りは開けるのに URL が1本も付かなかった）
    static func shareLead(_ photos: [Photo]) -> Photo? {
        photos.first(where: isShareable)
    }

    /// シェアで配る文字。題と枚数に、**開ける URL を1つ**添える
    /// ——集約のページがあればそれ、無ければ `lead`（`shareLead` が選んだ、最初に
    /// 配ってよい写真）のページ。配れない写真には URL を付けない（`isShareable`）
    /// `photos` は並んでいる写真（撮影地のページを付けてよいかを見る）
    static func shareText(title: String, count: Int, kind: PhotoQuery.Collection?, lead: Photo?,
                          photos: [Photo]) -> String {
        var lines = ["\(title) · \(L("\(count)枚", "\(count) photos"))"]
        if let url = pageURL(kind, photos: photos) ?? lead.flatMap({
            // 配れない写真（絞った・下書き）は URL を付けない（`PhotoDetailView.shareURL`）
            isShareable($0) ? PhotoLink.url(photoId: $0.id, isPublished: true) : nil
        }) {
            lines.append(url.absoluteString)
        }
        return lines.joined(separator: "\n")
    }
}
