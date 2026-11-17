import Foundation

/// 投稿画面を軽くするための決まり（2026-10-03・計画9「投稿の摩擦を下げる」）。
///
/// いちばん多い道は「写真を選ぶ → 撮影地 → 投稿する」。公開範囲・親しい友達・曲・アルバム・
/// カテゴリは**機能は残したまま**「詳しい設定」に畳む（今の既定値のまま投稿できる）。
/// 畳んでいても**いま何になっているかは行の右に出す**——公開範囲が見えないまま
/// 投稿されないように。「SNS にも載せる」の行は 1.1.83 で無くした（投稿のあとに毎回共有カード・`PostedShareCard`）
///
/// **`@MainActor` の型に置かない**（`UploadGrouping` と同じ理由——試験から直に呼ぶ）。
enum UploadDetails {

    /// 「詳しい設定」の行に出す、いまの値のまとめ。
    ///
    /// **公開範囲はいつも先頭に出す**（既定の「全体に公開」でも省かない）。旅の写真から来た回は
    /// 非公開で始まるので、畳んだままでも「非公開」と読めないといけない。
    /// 曲・アルバム・カテゴリは**付けたときだけ**足す（既定の「無し」は並べない）。
    static func summary(published: Bool, audience: Audience, songTitle: String?,
                        albumTitle: String?, category: String) -> String {
        var parts = [published ? audience.label : L("非公開", "Private")]
        if let songTitle, !songTitle.isEmpty { parts.append(L("曲", "Song")) }
        if let albumTitle, !albumTitle.isEmpty { parts.append(L("アルバム", "Album")) }
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.joined(separator: "\u{2002}")
    }

    /// 撮影地の下に「撮影地のページに作例として並ぶ」と一言出すか。
    ///
    /// **実際に並ぶときだけ出す。** 並ぶ仕組みは撮影地の文字列での集約（アプリの
    /// `DerivedSpot`・Web の `/location/<スラッグ>`）。公開一覧（Web の `photos.json`）に
    /// 載るのは**公開・全体に公開**の写真だけで、絞った写真・非公開は撮影地のページに並ばない
    /// （`RestrictedFeed` の注記）。撮影地が空でも並ばない
    static func showsSampleNote(location: String, published: Bool, audience: Audience) -> Bool {
        guard published, audience == .everyone else { return false }
        return !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// その一言。**2枚から**と添える——撮影地のページは同じ撮影地の写真が2枚から開く
    /// （`DerivedSpot.minPhotosForSpotPage`・Web の `MIN_INDEXABLE_LOCATION`）。
    /// 1枚目の人に「もう並んでいる」と思わせない
    static var sampleNote: String {
        L("同じ撮影地の写真とまとまり、撮影地のページに作例として並びます（2枚から）",
          "Joins other photos from this place as an example on its place page (from 2 photos)")
    }

    /// 「撮影地の位置を付ける」の切り替えの名前（2026-10-18 判断・`UploadLocationPreference`）。
    /// **約1kmに丸めることを名前に入れる**——何が送られるかを、切り替える前に読めるように
    static var locationToggleTitle: String {
        L("撮影地の位置を付ける（約1kmに丸めて保存）", "Attach the place's location (rounded to about 1 km)")
    }

    /// 投稿の画面の切り替えの名前（2026-11-12 判断・案「投稿まわりのデザイン」02）。「約1kmに丸めて」は
    /// すぐ下の一言（`uploadLocationToggleNote` のオン）に移した——名前を短くしても、切り替える前に読める所にある。
    /// ストーリーの「誰に見せる？」は下の一言が別なので、名前に入れたまま（`locationToggleTitle`）
    static var uploadLocationToggleTitle: String { L("撮影地の位置を付ける", "Attach the place's location") }

    /// 投稿の画面の撮影地の欄の下の1行（2026-11-16 判断・使い勝手の見直し A11・模型 MBEk の A11）。3行の札
    /// （`uploadLocationToggleTitle` と2行の `uploadLocationToggleNote`）を1行に縮めた。何が送られるか（約1kmに丸める）は
    /// 1行の中に残す。オンで写真の位置から撮影地を入れたかは欄の下の一言（`UploadPlaceStatus`）が言う
    static var uploadLocationLineTitle: String {
        L("地図に位置を載せる（約1kmに丸める）", "Put the location on the map (rounded to about 1 km)")
    }

    /// 投稿の画面の切り替えの下の一言。オンは「約1kmに丸めて地図に載せます」、オフは前のまま。
    /// オンも言い切らない——書き換えた撮影地には写真の位置を付けないことがある（2026-10-18 の決まり・`PlaceCoordsRule`）
    static func uploadLocationToggleNote(attaches: Bool) -> String {
        attaches
            ? L("約1kmに丸めて地図に載せます（撮影地を書き換えると載せないことがあります）",
                "Rounded to about 1 km and put on the map (editing the place may keep it off).")
            : locationToggleNote(attaches: false)
    }

    /// 「この写真を見て撮影（任意）」の印（写真と矢印）。構図を重ねて撮る（`camera.viewfinder`）と分ける（2026-11-12）
    static let inspiredSymbol = "photo.badge.arrow.down"

    /// 切り替えの下の一言。**いまの値で何が起きるか**を言う。オンも言い切らない（書き換えた撮影地には
    /// 写真の位置を付けないことがある・`PlaceCoordsRule`）
    ///
    /// オフの一言は次と食い違わないように（2026-10-18 の見直し）:
    /// - 自分で選んだ場所（候補・撮影スポット・スポットの画面から開いた回）は、その場所の位置が地図に載る
    /// - 手で書いた地名には、サーバーが地名から大まかな位置を付けることがある（`geoApprox`）
    /// - 自動の地名を本人が直してからオフにしたら、直した地名は残る（「自動では入れません」とだけ言い、
    ///   「撮影地を外します」とは言わない）
    static func locationToggleNote(attaches: Bool) -> String {
        attaches
            ? L("写真の位置情報から撮影地を入れ、地図に載せます（撮影地を書き換えると載せないことがあります）",
                "Fills in the place from the photo's location and puts it on the map (editing the place may keep it off).")
            : L("写真の位置は送らず、撮影地も自動では入れません。地図に載るのは自分で選んだ場所だけです（書いた地名から大まかな位置を付けることがあります）",
                "The photo's location isn't sent, and the place isn't filled in for you. Only places you choose go on the map (a rough location may come from a place name you type).")
    }

    /// 投稿画面を開いたときに、写真を選ぶ画面を**自動で一度だけ**開くか。
    ///
    /// 「追加」→「ライブラリから選ぶ」の2手を省く。開かないのは:
    /// - もう写真がある（旅の写真から来た・読み込み中）
    /// - 一度開いた（閉じてから戻ってきた回・選ぶ画面をやめた回に、また開かない）
    /// - 送っている間
    /// カメラは「追加」に残る（選ぶ画面をやめれば帯の「追加」から撮れる）
    static func autoOpensLibrary(hasPhotos: Bool, alreadyOffered: Bool, isWorking: Bool) -> Bool {
        !hasPhotos && !alreadyOffered && !isWorking
    }

    /// 自動で開くまで待つ時間。シート（投稿画面）が下から出きる時間（約0.5秒）より長めに取る。
    /// 当て推量に頼り切らない——出なかった回は `libraryOpenSteps` で立て直せる
    static let autoOpenDelayNanoseconds: UInt64 = 900_000_000

    /// 題・説明・タグの候補（端末の AI・札 #622）を作り始めるまで待つ時間。撮影地は写真の位置から少し遅れて入り、
    /// 打って直すこともあるので、入り終わってから1回だけ作る（待つ間に撮影地が変われば取り消して待ち直す）
    static let suggestDelayNanoseconds: UInt64 = 800_000_000

    /// 候補の札の並びの行（写真ごとに「題の候補の数」と「説明の候補の有無」の2行）。`UploadView` が変わりを見る
    static func suggestLayoutRows(id: UUID, titles: Int, caption: Bool) -> [String] {
        ["\(id.uuidString)|title|\(titles)", "\(id.uuidString)|caption|\(caption)"]
    }

    /// 候補の札が変わったときに、打っている欄へ送り直すか（#622・#607）。**打っている欄より下の札だけが変わったときは
    /// 送らない**——題の欄の下の題の候補・説明の欄の下の説明の候補は、打っている欄を動かさない（送ると、打ち始めの
    /// 1字で欄が下の端へ跳ねる）。ほかの写真の札や、説明を打っている写真の題の候補は、欄を動かす
    static func suggestMovesFocusedField(old: [String], new: [String], focused: UploadFieldFocus) -> Bool {
        let changed = Set(new).symmetricDifference(Set(old)).map { row -> String in
            let parts = row.split(separator: "|")
            return parts.count >= 2 ? "\(parts[0])|\(parts[1])" : row
        }
        let below: Set<String>
        switch focused {
        case .title(let id): below = ["\(id.uuidString)|title", "\(id.uuidString)|caption"]
        case .caption(let id): below = ["\(id.uuidString)|caption"]
        }
        return changed.contains { !below.contains($0) }
    }

    /// 「ライブラリから選ぶ」を押したときに `showLibrary` に入れる値の順。
    /// **立ったままなら一度下ろしてから立てる**（true に true を入れても変化にならず、開かない）
    static func libraryOpenSteps(isPresented: Bool) -> [Bool] {
        isPresented ? [false, true] : [true]
    }
}

/// 撮影地の欄の下の一言と候補のチップ（2026-11-16 判断・使い勝手の見直し A11・模型 MBEk の A11）。
///
/// 前は、撮影地が写真の位置から入ったのか、入らなかったのかが画面から分からなかった。位置の無い写真は
/// 撮影地を押して字を打つしかなかった（2回＋字）。欄の下に一言で状態を言い、入らなかったときは候補を押すだけ（1回）にする。
/// 板 Upload には無い段（模型の寸法: 一言は 12 の真鍮、チップは高さ 36・白 14%・字 13）
enum UploadPlaceStatus: Equatable {
    /// 写真の位置から引いた地名のまま（「写真の位置から入れました　変える」）
    case fromPhoto
    /// 写真に位置が無く、欄が空（「写真に位置情報が無いので、入れてください」と候補）
    case needsPlace
    /// 写真に位置はあるが入れない回（「地図に位置を載せる」がオフ・本人が空にした・「変える」を押した）。一言なしで候補だけ
    case choose
    /// 何も出さない（本人が書いた・候補から選んだ・写真の位置から引いている途中）
    case none

    /// - Parameters:
    ///   - location: 欄の字
    ///   - photoPlaceName: 写真の位置から自動で入れた地名（`PendingPhoto.photoPlaceName`）
    ///   - photoHasCoords: 写真に位置があるか（`prepared.coords`）
    ///   - attaches: 「地図に位置を載せる」（`UploadViewModel.attachesLocation`）。オフなら写真の位置から入れない
    ///   - clearedByUser: 入っていた撮影地を本人が空にした（`PendingPhoto.locationClearedByUser`）
    static func of(location: String, photoPlaceName: String?, photoHasCoords: Bool,
                   attaches: Bool, clearedByUser: Bool) -> UploadPlaceStatus {
        let now = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !now.isEmpty {
            let auto = photoPlaceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !auto.isEmpty && now == auto ? .fromPhoto : .none
        }
        if !photoHasCoords { return .needsPlace }
        // 位置のある写真で空: 入れない回（オフ・空にした）は候補だけ。オンで引いている途中は出さない
        // （数秒で地名が入る。チップを出してすぐ消すと、押そうとした所が動く）
        return !attaches || clearedByUser ? .choose : .none
    }

    /// 欄の下の一言。出さないなら nil
    var line: String? {
        switch self {
        case .fromPhoto: return L("写真の位置から入れました", "Filled in from the photo's location")
        case .needsPlace: return L("写真に位置情報が無いので、入れてください", "This photo has no location. Please add the place.")
        case .choose, .none: return nil
        }
    }

    /// 一言の右の「変える」（押すと欄を空にして候補を出し、欄に字を打てるようにする）
    var offersChange: Bool { self == .fromPhoto }
    static var changeTitle: String { L("変える", "Change") }

    /// 候補のチップを出すか
    var showsChips: Bool { self == .needsPlace || self == .choose }

    /// チップの1つ
    enum Chip: Equatable, Identifiable {
        /// 写真の近くの観光スポット
        case spot(OfficialSpot)
        /// 最近使った撮影地（この端末で投稿した撮影地・`RecentSearchesStore.places`）
        case recent(String)

        var id: String {
            switch self {
            case .spot(let spot): return "spot:\(spot.spotId)"
            case .recent(let name): return "recent:\(name)"
            }
        }
        var name: String {
            switch self {
            case .spot(let spot): return spot.name
            case .recent(let name): return name
            }
        }
    }

    /// 並べる数（模型: 3つ。字が大きいときは横に送れる）
    static let chipLimit = 3

    /// チップの並び。**近くの観光スポットが先**（撮った場所に近い順・`PlaceSpotSuggestions`）、残りに最近使った撮影地。
    /// 同じ名前は1つ（観光スポットを残す）。合わせて `chipLimit` まで
    static func chips(nearSpots: [OfficialSpot], recent: [String], limit: Int = chipLimit) -> [Chip] {
        var out: [Chip] = []
        var names = Set<String>()
        for spot in nearSpots where names.insert(MapSearch.fold(spot.name)).inserted {
            out.append(.spot(spot))
        }
        for name in recent {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, names.insert(MapSearch.fold(trimmed)).inserted else { continue }
            out.append(.recent(trimmed))
        }
        return Array(out.prefix(limit))
    }

    /// 近くの観光スポットを探す位置。この写真の位置、無ければ同じ投稿のほかの写真の位置（同じ旅で撮った1枚）。
    /// 🔴 **「地図に位置を載せる」がオフなら使わない**（オフは「写真の位置を使わない」。端末の中で引くだけでも、
    /// 写真の位置から選んだ候補を見せない・`UploadViewModel.attachesLocation` の注記と同じ線）
    static func chipCenter(own: Photo.Coords?, others: [Photo.Coords?], attaches: Bool) -> Photo.Coords? {
        guard attaches else { return nil }
        return own ?? others.lazy.compactMap { $0 }.first
    }
}
