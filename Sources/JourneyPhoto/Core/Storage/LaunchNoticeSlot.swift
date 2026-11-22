import Foundation

/// **起動で割り込む画面は1つまで**（札 #628・2026-11-22 判断）。
///
/// owner「入口みたいな画面、多すぎるかな？」（2026-11-15）。前は条件が重なると、1回の起動で
/// 新しくなったこと → 初期ユーザー章 → はじめての硬貨 → いいねの集まった1枚 と、閉じるたびに次が出た（最大4枚）。
/// いまは**最初に出たものだけ**がこの起動の枠を取り、残りは出さずに次の起動へ回す
/// （どれも出すまで端末かサーバーに残る: 新しくなったことは見た版、初期ユーザー章は数、はじめての硬貨は端末の控え、
/// いいねの1枚は「聞いた写真」に入れない）。
///
/// 枠に入らないもの: 規約の同意（審査で要る・タブの前）、送れなかった投稿の知らせ（データを失わない）、
/// 投稿のあとの「投稿しました」（`PostedSummaryCenter`・押した操作の続き）、アイコン・カバーのお礼（知らせに替えた）
struct LaunchNoticeSlot: Equatable {

    enum Kind: String, Equatable {
        /// 大きく変わる版の「新しくなったこと」（`WhatsNew.LaunchPresentation.sheet`）
        case whatsNew
        /// 初期ユーザー章の贈り物（`FoundingGiftGate`）
        case foundingGift
        /// 旅のトランクのはじめての硬貨（`TrunkWelcome`）
        case trunkWelcome
        /// いいねの集まった1枚をカバーに（`CoverOfferStore.offerLiked`）
        case likedCover
    }

    /// この起動で枠を取ったもの
    private(set) var taken: Kind?

    /// `kind` が出してよいか（まだ誰も取っていない・自分が取った）。取りはしない
    func mayShow(_ kind: Kind) -> Bool {
        taken == nil || taken == kind
    }

    /// 出す直前に枠を取る。取れたら true（同じものが出し直すときも true）
    mutating func claim(_ kind: Kind) -> Bool {
        guard mayShow(kind) else { return false }
        taken = kind
        return true
    }
}
