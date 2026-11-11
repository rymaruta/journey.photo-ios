import Foundation

/// **今週のお題**（札 #537 案2・2026-11-11 判断。前は「今日のテーマ」を日替わりで回していた）。
///
/// 🔴 なぜ週替わりに: 日替わりの7つのテーマに付いた公開の写真は**0枚**だった（2026-11-11 に `photos.json` で数えた）。
/// 載せる人が数人の今は、1日では誰も間に合わず、毎日「まだ誰もいない」お題だけが替わっていく。
/// 1週間あれば数人が同じお題で載せられ、みんなの参加が札に並ぶ（`participants`）。
///
/// **季節×撮影スポット。** お題は季節（その週の月曜の月・`SpotBodyText.season(ofMonth:)`）ごとの一覧から回す。
/// 季節の代表のお題（桜・海・紅葉・雪）は、その季節の撮影スポットへ誘う言い方にしてある。
/// ホームの「おすすめ」には同じ季節の撮影スポットの段（`HomeSpotShelf`）が並ぶ。
///
/// **サーバーは何も持っていない**（前と同じ）:
/// - お題は**日付から決まる**（週の通し番号で一覧を回す）。全員が同じ週に同じお題を見るのに通信は要らない
/// - 「参加する」は**そのタグを入れた投稿画面を開く**だけ（`MissionRouter.join`）
/// - 参加した数は**公開の写真のタグと投稿日で数える**（`participants`）。サーバーで数えてはいない
/// - 同じお題に誰かが載せたときの知らせは**作っていない**（サーバーの変更が要る・札 #537 に報告）
///
/// ⚠️ **一覧・順番・週の区切りは Web の `lib/utils/weeklyTheme.ts` と同じ。** ずれるとアプリと Web でお題が割れる
/// （両方の試験が同じ日付と答えで縛る）。
enum WeeklyTheme: Equatable {

    struct Theme: Equatable, Identifiable {
        /// 投稿に入れるタグ。**決まった選択肢（`TagChoices.all`）の中から選ぶ**
        /// ——お題専用の語を増やすと、絞り込みの棚がその週だけ散らかる
        let tag: String
        let title: String
        let prompt: String

        var id: String { tag }
    }

    /// 季節の名前（`SpotBodyText.season(ofMonth:)` の値）の順
    static let seasons = ["spring", "summer", "autumn", "winter"]

    /// 季節ごとのお題。**隣り合う季節で同じタグを使わない**——季節の変わり目の週で
    /// 同じお題が2週続かないように（`WeeklyThemeTests` が縛る）。順番に意味はある（週の通し番号で回す）
    static let themesBySeason: [String: [Theme]] = [
        "spring": [
            Theme(tag: "桜", title: L("桜のころ", "Cherry blossom season"),
                  prompt: L("桜の撮影スポットで、咲いている今を。", "Catch the blossoms at a photo spot.")),
            Theme(tag: "花", title: L("足もとの色", "Color underfoot"),
                  prompt: L("小さくても、目を引いた色を。", "Small things that caught your eye.")),
            Theme(tag: "朝", title: L("朝のはじまり", "First light"),
                  prompt: L("一日の最初の色を撮ってみませんか。", "Catch the day's first color.")),
            Theme(tag: "公園", title: L("近くの公園", "The park nearby"),
                  prompt: L("いつもの公園の、今週の景色を。", "This week's view of a park you know.")),
            Theme(tag: "川", title: L("川のある景色", "Along the river"),
                  prompt: L("流れのそばで見つけた一枚を。", "A frame found by the water's flow.")),
        ],
        "summer": [
            Theme(tag: "海", title: L("水のある風景", "By the water"),
                  prompt: L("海辺の撮影スポットで、水のある一枚を。", "A shot by the sea at a photo spot.")),
            Theme(tag: "空", title: L("夏の空", "Summer sky"),
                  prompt: L("見上げた空の色を。", "The color of the sky above you.")),
            Theme(tag: "夜", title: L("夜のあかり", "Night lights"),
                  prompt: L("暗くなってから見えてくるものを。", "What only appears after dark.")),
            Theme(tag: "雨", title: L("雨の日の景色", "Rainy days"),
                  prompt: L("雨の日にしか撮れない一枚を。", "A shot only a rainy day can give.")),
            Theme(tag: "山", title: L("山と空", "Mountains and sky"),
                  prompt: L("雄大な自然がつくる、心を動かす風景を。", "Landscapes that move you.")),
        ],
        "autumn": [
            Theme(tag: "夕焼け", title: L("光と影", "Light and shadow"),
                  prompt: L("光がつくる特別な瞬間を見つけよう。", "Find a moment shaped by light.")),
            Theme(tag: "紅葉", title: L("色づく景色", "Autumn colors"),
                  prompt: L("紅葉の撮影スポットで、今だけの色を。", "Autumn colors at a photo spot, only now.")),
            Theme(tag: "神社", title: L("その土地の場所", "Places of the land"),
                  prompt: L("その土地にしかない場所を訪ねて。", "Somewhere only there.")),
            Theme(tag: "森", title: L("森を歩く", "Into the woods"),
                  prompt: L("木々のあいだの光と影を。", "Light and shade between the trees.")),
            Theme(tag: "湖", title: L("湖のほとり", "By the lake"),
                  prompt: L("静かな水面に映るものを。", "What the still water reflects.")),
        ],
        "winter": [
            Theme(tag: "雪", title: L("雪の景色", "Snowscapes"),
                  prompt: L("雪の撮影スポットで、白い一枚を。", "A white frame at a snowy photo spot.")),
            Theme(tag: "冬", title: L("冬の光", "Winter light"),
                  prompt: L("低い日差しがつくる、冬だけの色を。", "Colors only the low winter sun makes.")),
            Theme(tag: "夜", title: L("冬のあかり", "Winter lights"),
                  prompt: L("暗くなってから見えてくるものを。", "What only appears after dark.")),
            Theme(tag: "山", title: L("冬の山", "Winter mountains"),
                  prompt: L("澄んだ空気の中の山を。", "Mountains in the clear winter air.")),
        ],
    ]

    /// 1970-01-01（木）の、西暦1年1月1日を1とした通し日数（Web の `EPOCH_ORDINAL`）
    static let epochOrdinal = 719_163
    /// 週の区切りの月曜（1970-01-05）の通し日数。**週は月曜から**
    static let mondayOrdinal = 719_167

    /// 端末の暦の今日の通し日数（西暦・土地の年月日）。
    ///
    /// **西暦で数える。** 端末の暦のまま紀元から数えると、和暦（令和の初日から）や
    /// タイ仏暦の端末が別のお題になり「全員が同じ週に同じお題」が崩れる。
    /// **土地の年月日を取り出してから数える**（Linux の Foundation の `ordinality` はタイムゾーンを見ない）
    static func dayOrdinal(_ now: Date, calendar: Calendar) -> Int {
        let local = calendar.gregorianKeepingZone.dateComponents([.year, .month, .day], from: now)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let noon = utc.date(from: DateComponents(year: local.year, month: local.month, day: local.day, hour: 12))
        return noon.flatMap { utc.ordinality(of: .day, in: .era, for: $0) } ?? epochOrdinal
    }

    /// 週の通し番号（1970-01-05 の週が 0）。月曜の0時（土地）で替わる
    static func weekIndex(_ now: Date, calendar: Calendar) -> Int {
        let offset = dayOrdinal(now, calendar: calendar) - mondayOrdinal
        return offset >= 0 ? offset / 7 : -((-offset + 6) / 7)
    }

    /// その週の月曜の年月日（西暦）
    static func monday(ofWeek week: Int) -> DateComponents {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let days = mondayOrdinal + week * 7 - epochOrdinal
        let date = Date(timeIntervalSince1970: TimeInterval(days) * 86_400 + 12 * 3_600)
        return utc.dateComponents([.year, .month, .day], from: date)
    }

    /// その週のお題。**季節はその週の月曜の月で決める**（週の途中で月が替わってもお題は替わらない）
    static func theme(ofWeek week: Int) -> Theme {
        let season = SpotBodyText.season(ofMonth: monday(ofWeek: week).month ?? 1)
        let themes = themesBySeason[season] ?? themesBySeason["autumn"]!
        let index = ((week % themes.count) + themes.count) % themes.count
        return themes[index]
    }

    /// 今週のお題
    static func current(_ now: Date = Date(), calendar: Calendar = .current) -> Theme {
        theme(ofWeek: weekIndex(now, calendar: calendar))
    }

    /// 今週（土地の月曜0時〜次の月曜0時）
    static func weekRange(_ now: Date, calendar: Calendar) -> Range<Date>? {
        let gregorian = calendar.gregorianKeepingZone
        let parts = monday(ofWeek: weekIndex(now, calendar: calendar))
        guard let start = gregorian.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)),
              let end = gregorian.date(byAdding: .day, value: 7, to: start) else { return nil }
        return start..<end
    }

    /// 写真がお題のタグを持ち、`range` の間に投稿されたか
    private static func joins(_ photo: Photo, theme: Theme, range: Range<Date>) -> Bool {
        let key = TagChoices.key(theme.tag)
        guard (photo.tags ?? []).contains(where: { TagChoices.key($0) == key }),
              let created = photo.createdAt, let date = NotificationGroups.parse(created) else { return false }
        return range.contains(date)
    }

    /// **みんなの参加**: 今週お題のタグを付けて載せた公開の投稿（新しい順・1つの投稿は1枚＝いちばん新しい写真）。
    /// 札に横に並べる（`WeeklyThemeCard`）。同じ投稿の写真は1つに数える（`PhotoGroups.groupKey`）
    static func participants(_ theme: Theme, photos: [Photo], now: Date = Date(),
                             calendar: Calendar = .current) -> [Photo] {
        guard let range = weekRange(now, calendar: calendar) else { return [] }
        let matched = GallerySort.new.apply(photos.filter { joins($0, theme: theme, range: range) })
        var seen = Set<String>()
        return matched.filter { seen.insert(PhotoGroups.groupKey(of: $0)).inserted }
    }

    /// もう参加したか。**自分の写真を見て決める**（今週そのタグを付けて上げたものがあるか）。
    ///
    /// 下書きも数える——上げようとした事実はあるので、「参加していない」と言い張らない。
    /// 参加済みの週は「参加する」を押せない「参加済み」にする（同じ週に何度も促さない）
    static func hasJoined(_ theme: Theme, myPhotos: [Photo],
                          now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let range = weekRange(now, calendar: calendar) else { return false }
        return myPhotos.contains { joins($0, theme: theme, range: range) }
    }
}
