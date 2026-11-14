import Foundation

/// 投稿画面の下の主ボタン（「3枚を投稿する」）の字と、押せないときの理由（2026-11-14・#188・点検「直すべき 2」）。
///
/// 🔴 **「投稿する」は下の主ボタン1つ。** 前は右上の 15pt の字だけで、片手の親指からいちばん遠い角だった
/// （6.9 型で上から約 113pt・持ち替えが要る）。板の投稿画面（`project/Upload.dc.html`）は、上のバーの右を
/// 空け（左に閉じる・真ん中に題・右は 44pt の空き）、下の帯（黒 55%＋ぼかし＋白 8% の線）に幅いっぱいの
/// 白の主ボタン「3枚を投稿する」を置く。**右上の「投稿する」は残さない**——板が右を空けており、主は
/// 1画面に1つ（Components 01）。同じ操作を2か所に置くと、どちらが決める所か迷う。押す回数は変わらない（1回）。
///
/// - 高さは主ボタンの 50（`JPHeight.primaryButton`）。板の投稿画面は 52 のままだが、デザインシステムが
///   「ボタンの高さは 50（主）と 44（副）の2種類だけ。以前の 52 はやめた」と決めており、画面ごとに割らない
/// - 色は白（写真のある画面の主ボタン・CLAUDE.md）。`jpPillButton(.primary)`
/// - 押せない間は 32% に薄め、理由を下に1行（Components 01「使えないとき」）
/// - 送っている間は輪を前に足し「投稿しています 2/3」（Components 01「進行中」）
enum UploadSubmitBar {

    /// 主ボタンの字。2枚以上は枚数を言う（押す前に何枚が出るか分かる）
    static func title(count: Int) -> String {
        count > 1 ? L("\(count)枚を投稿する", "Post \(count) photos") : L("投稿する", "Post")
    }

    /// 送っている間の字（前に輪を足す）
    static let sendingTitle = L("投稿しています", "Posting")

    /// 押せない間の薄さ（Components 01「使えないとき 32%」）
    static let disabledOpacity = 0.32

    /// 押せないときの理由（ボタンの下に1行）。押せる・送っている最中は nil
    static func blockedReason(hasPhotos: Bool, loading: Bool, working: Bool) -> String? {
        if working { return nil }
        if loading { return L("写真を読み込んでいます", "Loading photos") }
        if !hasPhotos { return L("写真を選ぶと投稿できます", "Choose a photo to post") }
        return nil
    }
}
