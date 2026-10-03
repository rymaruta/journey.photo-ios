import Foundation

/// 投稿画面を軽くするための決まり（2026-10-03・計画9「投稿の摩擦を下げる」）。
///
/// いちばん多い道は「写真を選ぶ → 撮影地 → 投稿する」。公開範囲・親しい友達・曲・アルバム・
/// SNS・カテゴリは**機能は残したまま**「詳しい設定」に畳む（今の既定値のまま投稿できる）。
/// 畳んでいても**いま何になっているかは行の右に出す**——公開範囲や SNS が見えないまま
/// 投稿されないように。
///
/// **`@MainActor` の型に置かない**（`UploadGrouping` と同じ理由——試験から直に呼ぶ）。
enum UploadDetails {

    /// 「詳しい設定」の行に出す、いまの値のまとめ。
    ///
    /// **公開範囲はいつも先頭に出す**（既定の「全体に公開」でも省かない）。旅の写真から来た回は
    /// 非公開で始まるので、畳んだままでも「非公開」と読めないといけない。
    /// 曲・アルバム・SNS・カテゴリは**付けたときだけ**足す（既定の「無し」は並べない）。
    static func summary(published: Bool, audience: Audience, songTitle: String?,
                        albumTitle: String?, sharesToSocial: Bool, category: String) -> String {
        var parts = [published ? audience.label : L("非公開", "Private")]
        if let songTitle, !songTitle.isEmpty { parts.append(L("曲", "Song")) }
        if let albumTitle, !albumTitle.isEmpty { parts.append(L("アルバム", "Album")) }
        // SNS は載せられるとき（公開・全体に公開）だけ効く（`ThreadsShare.isEligible`）。
        // 効かない回に「SNS」と書くと、載ると思わせる
        if sharesToSocial, ThreadsShare.isEligible(published: published, audience: audience) {
            parts.append(L("SNS にも載せる", "Share to social"))
        }
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.joined(separator: " · ")
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

    /// 「ライブラリから選ぶ」を押したときに `showLibrary` に入れる値の順。
    /// **立ったままなら一度下ろしてから立てる**（true に true を入れても変化にならず、開かない）
    static func libraryOpenSteps(isPresented: Bool) -> [Bool] {
        isPresented ? [false, true] : [true]
    }
}
