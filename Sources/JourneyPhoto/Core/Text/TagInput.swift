import Foundation

/// タグの入力と、写真の絞り込み。
///
/// **`@MainActor` の型に置かない。** 置くと静的メソッドまで MainActor に
/// 縛られ、テスト（`XCTestCase` のメソッドは isolation を持たない）から
/// 呼べなくなる——`Call to main actor-isolated static method in a
/// synchronous nonisolated context` でコンパイルが落ちる。
/// 画面からもテストからも呼ぶ計算は、素の `enum` に置く。
enum TagInput {

    /// 読点・カンマ・空白のどれで区切っても同じに扱う。
    /// **重複は落とす**（同じタグが2つ付くと絞り込みの件数がずれる）。
    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in text.components(separatedBy: CharacterSet(charactersIn: ",、 　\n")) {
            let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, !seen.contains(tag.lowercased()) else { continue }
            seen.insert(tag.lowercased())
            result.append(tag)
        }
        return result
    }

    // MARK: - 候補チップ（Web の `lib/utils/ownValues.ts` と対）

    /// いまの欄にそのタグが入っているか。**大小・`#`・日英の別名は畳んで見る。**
    static func has(_ current: String, tag: String) -> Bool {
        let key = TagChoices.key(tag)
        guard !key.isEmpty else { return false }
        return current.split(separator: ",").contains { TagChoices.key(String($0)) == key }
    }

    /// 欄の文字列を組み直す。**末尾に区切りを残す。**
    ///
    /// 残さないと、**チップを押した直後に打つと前のタグに繋がる**
    /// ——`桜` を押して `京都` と打つと `"桜京都"` という1つの嘘のタグになる。
    private static func join(_ parts: [String]) -> String {
        let kept = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return kept.isEmpty ? "" : kept.joined(separator: ", ") + ", "
    }

    /// タグを足す。**同じ鍵のものが既にあれば何もしない**
    /// （`fuji` の欄に `Fuji` を押して2つ並ぶのを避ける）。
    static func append(_ current: String, tag: String) -> String {
        let add = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !add.isEmpty else { return current }
        let parts = current.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let key = TagChoices.key(add)
        if parts.contains(where: { TagChoices.key($0) == key }) { return current }
        return join(parts + [add])
    }

    /// チップの押下。**入っていれば外す、入っていなければ足す。**
    ///
    /// 足すだけだと、**既に付いているタグのチップを押しても何も起きない**
    /// （一覧の絞り込みは押し直して外せるのに、投稿側だけ古いままだった）。
    static func toggle(_ current: String, tag: String) -> String {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard has(current, tag: t) else { return append(current, tag: t) }
        let key = TagChoices.key(t)
        return join(current.split(separator: ",")
            .map { String($0) }
            .filter { TagChoices.key($0) != key })
    }

    /// 欄の**最後の欠片**が「打ちかけ」なら返す（候補と丸ごと同じなら
    /// 「選び終えた1つ」なので空）。
    ///
    /// **この判定を2か所に書かない。** 絞る側（`suggest`）と、チップを押した
    /// ときに欠片を捨てる側（`dropFragment`）が同じ答えを使う。別々に書いた
    /// Web の版は、**打って絞ってチップを押すと欠片がタグとして残った**。
    static func typingFragment(_ all: [String], current: String) -> String {
        let frag = (current.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !frag.isEmpty else { return "" }
        let key = TagChoices.key(frag)
        return all.contains { TagChoices.key($0) == key } ? "" : frag
    }

    /// 打ちかけの欠片を欄から落とす（チップを押すときに使う）。
    static func dropFragment(_ all: [String], current: String) -> String {
        guard !typingFragment(all, current: current).isEmpty else { return current }
        guard let cut = current.lastIndex(of: ",") else { return "" }
        return String(current[current.startIndex..<cut])
    }

    /// 候補を、**打ちかけの文字で絞る**。
    ///
    /// 何も打っていなければ全部出す（20語は全部並ぶ——Web は
    /// `suggestTags(TAG_CHOICES, …, TAG_CHOICES.length)` で呼んでいる）。
    static func suggest(_ all: [String], current: String) -> [String] {
        let frag = typingFragment(all, current: current)
        guard !frag.isEmpty else { return all }
        var raw = frag.lowercased()
        while raw.hasPrefix("#") { raw.removeFirst() }
        let key = TagChoices.key(frag)
        return all.filter { tag in
            var r = tag.lowercased()
            while r.hasPrefix("#") { r.removeFirst() }
            return r.contains(raw) || TagChoices.key(tag).contains(key)
        }
    }
}

enum PhotoQuery {

    /// 題・撮影地・タグ・カテゴリのどれかに含まれれば拾う。
    /// 大文字小文字と全角半角は区別しない。
    static func match(_ photos: [Photo], query: String) -> [Photo] {
        let needle = query.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        guard !needle.isEmpty else { return [] }
        return photos.filter { photo in
            let haystack = [
                photo.displayTitle,
                photo.location ?? "",
                photo.category ?? "",
                (photo.tags ?? []).joined(separator: " "),
            ].joined(separator: " ")
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            return haystack.contains(needle)
        }
    }

    /// タグ・撮影地・カテゴリでの絞り込み。
    ///
    /// **撮影地はゆるく一致させる。** Web 側の `photosInCollection` が
    /// 「パリ」「パリ, フランス」「オペラ・ガルニエ（パリ）」を寄せているので、
    /// 完全一致で絞ると結果が食い違う。
    enum Collection: Equatable {
        case tag(String)
        case location(String)
        case category(String)
        /// 機材。Web の `/camera/*`。**値は `CameraName.deduped` を通したもの**
        /// ——生のままだと同じ機種が2つに割れる
        case camera(String)

        var title: String {
            switch self {
            case .tag(let value): return "#\(value)"
            case .location(let value): return value
            case .category(let value): return value
            case .camera(let value): return value
            }
        }
    }

    static func photos(_ photos: [Photo], in collection: Collection) -> [Photo] {
        switch collection {
        case .tag(let value):
            let needle = value.lowercased()
            return photos.filter { ($0.tags ?? []).contains { $0.lowercased() == needle } }
        case .category(let value):
            // **綴りではなく鍵で。** `建築` と `architecture` は同じ分類
            // （Web の `slugify(_, "category")`）。生の値で比べると
            // 同じ主題が2つに割れる
            let key = CategoryChoices.key(value)
            return photos.filter { CategoryChoices.key($0.category ?? "") == key }
        case .location(let value):
            let needle = value.lowercased()
            return photos.filter {
                guard let location = $0.location?.lowercased() else { return false }
                return location == needle || location.contains(needle) || needle.contains(location)
            }
        case .camera(let value):
            // **必ず `CameraName.deduped` を通して比べる。** 保存済みの値には
            // メーカー名が二重に残っている行があり（実データ）、生のまま
            // 比べると同じ機種の写真が集まらない
            let needle = CameraName.deduped(value)?.lowercased()
            return photos.filter { CameraName.deduped($0.exif?.camera)?.lowercased() == needle }
        }
    }

    /// 「この写真に近いもの」。同じ撮影地を先に、足りなければタグが重なるもので埋める。
    /// **自分自身は入れない。**
    static func related(to photo: Photo, from photos: [Photo], limit: Int = 12) -> [Photo] {
        let others = photos.filter { $0.id != photo.id }
        var picked: [Photo] = []
        var seen = Set<String>()

        if let location = photo.location?.lowercased(), !location.isEmpty {
            for item in others where (item.location?.lowercased() ?? "") == location {
                if seen.insert(item.id).inserted { picked.append(item) }
            }
        }

        let tags = Set((photo.tags ?? []).map { $0.lowercased() })
        if !tags.isEmpty {
            for item in others where !tags.isDisjoint(with: Set((item.tags ?? []).map { $0.lowercased() })) {
                // **この境目はテストで殺せない（等価変異）。**
                // `>=` を `>` にしても、最後の `prefix(limit)` が
                // 同じ形に削るので外からは区別できない——変異を当てて
                // 確かめた。早く抜けるためだけの条件なので、見張りが
                // 無いことを承知で残す（`photo-gallery` の
                // `shouldScan` と同じ扱い）
                if picked.count >= limit { break }
                if seen.insert(item.id).inserted { picked.append(item) }
            }
        }
        return Array(picked.prefix(limit))
    }

    /// 多い順にタグを数える。**種類が少ないので全部数えてよい**（30枚・59種）。
    /// よく使われているタグ。**鍵で畳んでから数える**
    /// （`風景` と `landscape` を別々に数えない。Web の `tagKey` と同じ）。
    /// 返すのは**最初に出てきた綴り**——画面には打たれたままを見せる。
    static func topTags(in photos: [Photo], limit: Int = 12) -> [String] {
        var counts: [String: Int] = [:]
        var labels: [String: String] = [:]
        for tag in photos.flatMap({ $0.tags ?? [] }) {
            let key = TagChoices.key(tag)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
            if labels[key] == nil { labels[key] = tag }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .compactMap { labels[$0.key] }
    }

    /// 打った文字で絞る。**題・説明・撮影地・タグ**を見る
    /// （Web の `useGallery` の `query` と同じ範囲）。
    ///
    /// **地名もここで拾う。** チップの候補は決まった20語だけにしたので
    /// （`TagChoices.all`——地名や一回きりの名詞は候補にしない方針）、
    /// 「helsinki」のような固有名詞はここから探す。
    static func photos(_ photos: [Photo], matching query: String) -> [Photo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return photos }
        return photos.filter { photo in
            let haystack = [
                photo.displayTitle,
                photo.location ?? "",
                photo.paragraphs.joined(separator: " "),
                (photo.tags ?? []).joined(separator: " "),
                photo.category ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
    }

    /// 候補のタグと、その枚数。**決まった20語だけ**（`TagChoices.all`）を
    /// 多い順に。0枚の語は出さない（押しても空になるチップを置かない）。
    ///
    /// 提案の絵の「winter 13 / finland 12 …」にあたる。**数を出すのは、
    /// 押す前に手応えが分かるから**——1枚しか無い語を押すのは徒労になる。
    static func tagCounts(in photos: [Photo], limit: Int = 12) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tag in photos.flatMap({ $0.tags ?? [] }) {
            counts[TagChoices.key(tag), default: 0] += 1
        }
        return TagChoices.all
            .compactMap { choice -> (tag: String, count: Int)? in
                let count = counts[TagChoices.key(choice)] ?? 0
                return count > 0 ? (tag: choice, count: count) : nil
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
            .prefix(limit)
            .map { $0 }
    }

    /// 選んだタグで絞る。**全部を持つ写真だけ**（Web の `wanted.every`）。
    /// 比べるのは鍵（`#` と大小、日英の別名を無視する）。
    static func photos(_ photos: [Photo], withAllTags tags: [String]) -> [Photo] {
        let wanted = Set(tags.map { TagChoices.key($0) }.filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return photos }
        return photos.filter { photo in
            let have = Set((photo.tags ?? []).map { TagChoices.key($0) })
            return wanted.isSubset(of: have)
        }
    }
}
