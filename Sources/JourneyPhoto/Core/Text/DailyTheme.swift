import Foundation

/// 今日のテーマ（モック1 の「今日のミッション」）。
///
/// **サーバーは何も持っていない。** テーマを配る口も、参加を数える口も
/// 無い。だからこの機能は**端末側だけで完結する形**にする:
///
/// - テーマは**日付から決まる**（固定の一覧を日で回す）。だから
///   **全員が同じ日に同じテーマ**を見るのに、通信は1回も要らない
/// - 「参加する」は**そのタグを入れた投稿画面を開く**だけ
/// - 参加済みかどうかは**自分の写真を見て決める**（今日そのタグで
///   上げたものがあるか）。印を端末に置くだけだと、消せば嘘になる
///
/// **参加人数は出さない。** 数えていないので置けば嘘になる。
enum DailyTheme: Equatable {

    struct Theme: Equatable, Identifiable {
        /// 投稿に入れるタグ。**決まった選択肢（`TagChoices.all`）の中から選ぶ**
        /// ——テーマ専用の語を増やすと、絞り込みの棚がその日だけ散らかる
        let tag: String
        let title: String
        let prompt: String

        var id: String { tag }
    }

    /// 一覧。**順番に意味はある**（日付で回すので、隣り合う日が
    /// 似たテーマにならないように季節をばらけさせてある）。
    static let themes: [Theme] = [
        Theme(tag: "夕焼け", title: L("光と影", "Light and shadow"),
              prompt: L("光がつくる特別な瞬間を見つけよう。", "Find a moment shaped by light.")),
        Theme(tag: "山", title: L("山と空", "Mountains and sky"),
              prompt: L("雄大な自然がつくる、心を動かす風景を。", "Landscapes that move you.")),
        Theme(tag: "朝", title: L("朝のはじまり", "First light"),
              prompt: L("一日の最初の色を撮ってみませんか。", "Catch the day's first colour.")),
        Theme(tag: "海", title: L("水のある風景", "By the water"),
              prompt: L("海・湖・川——水がある場所の一枚を。", "Sea, lake or river.")),
        Theme(tag: "夜", title: L("夜のあかり", "Night lights"),
              prompt: L("暗くなってから見えてくるものを。", "What only appears after dark.")),
        Theme(tag: "花", title: L("足もとの色", "Colour underfoot"),
              prompt: L("小さくても、目を引いた色を。", "Small things that caught your eye.")),
        Theme(tag: "神社", title: L("その土地の場所", "Places of the land"),
              prompt: L("その土地にしかない場所を訪ねて。", "Somewhere only there.")),
    ]

    /// 今日のテーマ。**日付から決まる**ので、同じ日なら何度開いても同じ。
    ///
    /// 区切りは**その端末の暦の1日**（協定世界時ではない）——
    /// 日付が変わった瞬間に切り替わるのが、見ている人の感覚に合う。
    static func today(_ now: Date = Date(), calendar: Calendar = .current) -> Theme {
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let index = ((day % themes.count) + themes.count) % themes.count
        return themes[index]
    }

    /// もう参加したか。**自分の写真を見て決める**
    /// （今日そのタグを付けて上げたものがあるか）。
    ///
    /// 下書きも数える——上げようとした事実はあるので、
    /// 「参加していない」と言い張らない。
    static func hasJoined(_ theme: Theme, myPhotos: [Photo],
                          now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let key = TagChoices.key(theme.tag)
        return myPhotos.contains { photo in
            guard (photo.tags ?? []).contains(where: { TagChoices.key($0) == key }) else { return false }
            guard let created = photo.createdAt, let date = NotificationGroups.parse(created) else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        }
    }
}
