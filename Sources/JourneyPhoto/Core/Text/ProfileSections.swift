import Foundation

/// マイページ（モック2）の、**出す／出さないの決まり**。
///
/// 🔴 **この画面は実機の絵で確かめられない**（CI の巡回はログインしない）。
/// 見なくても分かるように、判断だけを画面から出す
/// ——`Shims/` の模型では `View` の中を動かせないので、ここに置いたぶんだけが
/// Linux の `swift test` で確かめられる（`SpotScreen` と同じ判断）。
enum ProfileSections {

    /// ストーリーハイライトの輪を出すか（モック2-5）。
    ///
    /// - **読み終わるまで出さない。** 先に空の行を出すと、読み終わった
    ///   瞬間に入れ替わってちらつく
    /// - **他人のページで0件なら、行ごと消す。** サーバーは「追っていない人」にも
    ///   0件を返す（`canSeeHighlights`）ので、「見られません」と書くと
    ///   **在ることを教える**ことになる
    /// - 自分のページは0件でも出す（そこにしか「新規」が無い）
    static func showsHighlights(loaded: Bool, isMine: Bool, count: Int) -> Bool {
        guard loaded else { return false }
        return isMine || count > 0
    }

    /// 「行きたい場所」の札に何を出すか（モック2-6）。
    enum WishlistState: Equatable {
        /// 並べる
        case list
        /// まだ1つも入れていない
        case empty
        /// 入れてあるが、引き当て先（公開一覧）をまだ読み終えていない
        case loading
        /// **入れてあるのに引き当て先が取れていない**（「無い」と言わない）
        case couldNotLoad
    }

    /// 「行きたい」の撮影地の行を引き当てる写真。**公開一覧と自分の写真を合わせる**。
    ///
    /// 🔴 **自分の写真だけでは足りない。** 「行きたい」を押すスポットの画面は、
    /// 地図・検索・写真の詳細から**他人の写真で**開くのがふつう（地図は公開一覧を
    /// 読む）。以前は `model.photos`（自分の写真）だけから地点を導いていたので、
    /// 他人の写真の撮影地に押した「行きたい」が**一度もマイページに出なかった**。
    ///
    /// 同じ写真が両方に在る（自分の公開写真）ので **ID で1枚に寄せる**——寄せないと
    /// 地点の枚数が倍になる。**自分の写真を先に採る**（非公開も含む、手元でいちばん新しい姿）
    static func wishlistPool(feed: [Photo], mine: [Photo]) -> [Photo] {
        var seen = Set<String>()
        var pool: [Photo] = []
        for photo in mine + feed where seen.insert(photo.id).inserted {
            pool.append(photo)
        }
        return pool
    }

    /// 「行きたい」に入れた撮影地の行（`wishlistPool` から導いた地点のうち、鍵が入っているもの）
    static func wantedPlaces(keys: Set<String>, feed: [Photo], mine: [Photo]) -> [DerivedSpot.Place] {
        wantedPlaces(keys: keys, pool: wishlistPool(feed: feed, mine: mine))
    }

    /// 引き当て先を先に絞った（ブロック・通報を外した）束から導く。
    ///
    /// **鍵（スラッグ）で1行に寄せる。** `DerivedSpot.all` はラベルで寄せるが、
    /// 「高屋-神社」と「高屋 神社」のように別のラベルが同じ鍵になる。束が他人の
    /// 写真まで広がったので当たりやすく、同じ id の行が2つ並ぶと一覧が壊れる。
    /// **写真は両方を合わせる**（片方だけ残すと、枚数・表紙・開いた先の写真が半分になる）
    static func wantedPlaces(keys: Set<String>, pool: [Photo]) -> [DerivedSpot.Place] {
        var order: [String] = []
        var merged: [String: DerivedSpot.Place] = [:]
        for place in DerivedSpot.all(in: pool) where keys.contains(place.slug) {
            guard let first = merged[place.slug] else {
                merged[place.slug] = place
                order.append(place.slug)
                continue
            }
            let known = Set(first.photos.map(\.id))
            let photos = (first.photos + place.photos.filter { !known.contains($0.id) })
                .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            merged[place.slug] = DerivedSpot.Place(label: first.label, slug: first.slug, photos: photos,
                                                   broader: first.broader, categories: first.categories,
                                                   coords: first.coords ?? place.coords)
        }
        return order.compactMap { merged[$0] }.sorted { $0.count > $1.count }
    }

    /// 並べられた行が覚えている鍵より少なく、**引き当て先が取れていない**。
    /// 一部だけ自分の写真で見つかった回に、欠けた行を黙って落とさない（一行添える）
    static func wishlistPartlyMissing(shownCount: Int, savedIdCount: Int, sourceFailed: Bool) -> Bool {
        sourceFailed && shownCount < savedIdCount
    }

    /// - Parameters:
    ///   - wantedCount: 突き合わせて残った件数。**撮影地の行と台帳のスポットの行
    ///     （`OfficialWishlist.rows`）を足したもの**——スポットだけ入れた人を
    ///     「まだ無い」にしない
    ///   - savedIdCount: この端末が覚えている鍵の数
    ///   - loaded: 引き当て先（公開一覧）を読み終えたか
    ///   - sourceFailed: 引き当て先（公開一覧）の最後の読み込みが失敗したか
    ///
    /// 🔴 **「まだ無い」と「取れていない」を分ける。** 入れた覚えがあるのに
    /// 「まだありません」と出ると、消えたように見える。
    ///
    /// 🔴 **「取れていない」は読み込みの失敗で決める。件数の食い違いでは決めない。**
    /// 以前は「導いた地点が0件なら取れていない」と見ていたので、写真を1枚も
    /// 上げていない人（地点0件）は、公開一覧が取れていても「写真の一覧を取れません
    /// でした」と出ていた。逆に自分の写真が1枚でもあれば、公開一覧が取れていなくても
    /// 「まだありません」と言っていた
    static func wishlist(wantedCount: Int, savedIdCount: Int,
                         loaded: Bool, sourceFailed: Bool) -> WishlistState {
        if wantedCount > 0 { return .list }
        guard savedIdCount > 0 else { return .empty }
        if sourceFailed { return .couldNotLoad }
        if !loaded { return .loading }
        return .empty
    }
}
