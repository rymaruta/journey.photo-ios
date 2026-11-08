import Foundation

/// 行った県マップの**画面の文言**（札 #503・提案書 第2版 04 節の言葉）。画面を持たない層に置き、
/// 禁止語・読み上げの形を Linux の `swift test` で見張る。
///
/// 言葉の決まり: 「行った県」「回数」「記録する」「外す」。**使わない**: 撮りどき・捨てる・注目スポット・
/// この場所・ガイドを見る・撮影地ガイド。写真から導く県は「撮影地」で言う。
/// 「あなたの記録」と言い、地図の数が事実とは限らない（自己申告）ことを画面でも隠さない
enum VisitedMapText {

    // MARK: - 見出し・数

    static var title: String { L("行った県", "Prefectures visited") }

    /// 「31/47」
    static func ratio(_ visited: Int) -> String { "\(visited)/\(VisitedPrefectures.total)" }

    /// 入口の札の読み上げ（「行った県、31 / 47、ボタン」）
    static func entryAccessibility(_ visited: Int) -> String {
        L("行った県、\(visited) / 47", "Prefectures visited, \(visited) of 47")
    }

    /// 周の行。1周もそろっていなければ nil（行った県の数がそのまま進み具合）
    /// 例「2 周そろった · 3 周目 12/47」「1 周そろった」（進行中が0県なら周目を出さない）
    static func roundsLine(completed: Int, inProgress: (round: Int, done: Int)) -> String? {
        guard completed >= 1 else { return nil }
        let done = L("\(completed) 周そろった", completed == 1 ? "1 round complete" : "\(completed) rounds complete")
        guard inProgress.done > 0 else { return done }
        let next = L("\(inProgress.round) 周目 \(inProgress.done)/47", "Round \(inProgress.round): \(inProgress.done)/47")
        return "\(done) · \(next)"
    }

    /// 内訳（バッジ「都道府県」の数とは別）。「写真から 28 県 · 手で 3 県」
    static func breakdown(fromPhotos: Int, byHand: Int) -> String {
        L("写真から \(fromPhotos) 県 · 手で \(byHand) 県", "From photos \(fromPhotos) · by hand \(byHand)")
    }

    static var breakdownNote: String {
        L("バッジ「都道府県」の数とは別の、あなたの記録です。",
          "This is your own record, separate from the Prefectures badge.")
    }

    // MARK: - 県の読み上げ・数が変わったとき

    /// 「東京都、5 回」「東京都、未」「東京都、写真の候補」
    static func prefectureAccessibility(_ name: String, count: Int, isCandidate: Bool) -> String {
        if count > 0 { return L("\(name)、\(count) 回", "\(name), \(count) \(count == 1 ? "time" : "times")") }
        if isCandidate { return L("\(name)、写真の候補", "\(name), suggested from photos") }
        return L("\(name)、未", "\(name), not yet")
    }

    /// 数が変わったあとの読み上げ「東京都、6 回。行った県 31」
    static func changeAnnouncement(_ name: String, count: Int, visited: Int) -> String {
        if count == 0 { return L("\(name)の記録を外しました。行った県 \(visited)", "Removed \(name). Visited \(visited)") }
        return L("\(name)、\(count) 回。行った県 \(visited)", "\(name), \(count). Visited \(visited)")
    }

    static func tapHint(addsCount: Bool) -> String {
        addsCount ? L("ダブルタップで 1 回足す", "Double-tap to add one visit")
                  : L("ダブルタップで札を開く", "Double-tap to open details")
    }

    // MARK: - スイッチ

    static var switchTitle: String { L("タップで回数を足す", "Tap to add a visit") }

    static func switchNote(on: Bool) -> String {
        on ? L("県をタップするたびに 1 回ずつ増えます。まちがえたら「取り消す」で戻せます。",
               "Each tap on a prefecture adds one visit. Undo with the button that appears.")
           : L("オフのあいだは、県をタップすると札が開きます。回数は札の ＋ で足せます。",
               "While off, tapping a prefecture opens its card. Add visits with + there.")
    }

    // MARK: - 札（県）

    static func visitCount(_ n: Int) -> String { L("\(n) 回", n == 1 ? "1 time" : "\(n) times") }

    static var recentDates: String { L("最近の日付", "Recent dates") }
    static var noDates: String { L("まだ記録がありません", "No record yet") }

    static var addVisit: String { L("1 回足す", "Add one visit") }
    static var removeVisit: String { L("1 回減らす（0 回で記録を外す）", "Remove one visit (at 0 the record is cleared)") }
    static var record: String { L("記録する", "Record") }
    static var candidateNote: String {
        L("撮影地から見つかった県です。記録にするのはあなたです。", "Found from where your photos were taken. You decide whether to record it.")
    }
    static var dismissCandidate: String { L("候補から外す", "Not a candidate") }
    static var restoreCandidate: String { L("候補に戻す", "Suggest again") }

    // MARK: - 取り消し・同じ日

    static var undo: String { L("取り消す", "Undo") }
    static var undoStep: String { L("ひとつ戻す", "Step back") }

    static func recorded(_ name: String, count: Int) -> String {
        L("\(name)を記録しました（\(count) 回）", "Recorded \(name) (\(count))")
    }

    static func reduced(_ name: String, count: Int) -> String {
        count == 0 ? L("\(name)の記録を外しました", "Cleared \(name)")
                   : L("\(name)を 1 回減らしました（\(count) 回）", "Removed one for \(name) (\(count))")
    }

    static var recordedAllToast: String { L("47県を記録しました", "Recorded all 47") }
    static var clearedAllToast: String { L("記録をすべて外しました", "Cleared all records") }

    static var sameDayTitle: String { L("今日は記録済みです", "Already recorded today") }
    static var sameDayQuestion: String { L("もう 1 回足しますか", "Add another visit?") }
    static var sameDayAdd: String { L("足す", "Add") }
    static var cancel: String { L("やめる", "Cancel") }

    // MARK: - 近くの県・一覧

    static var nearby: String { L("近くの県", "Nearby") }
    static var listTitle: String { L("県の一覧", "List") }
    static var showList: String { L("一覧", "List") }
    static var showMap: String { L("地図", "Map") }

    /// 地方の進み「関東 5/7」
    static func regionProgress(name: String, visited: Int, total: Int) -> String { "\(name) \(visited)/\(total)" }

    // MARK: - 凡例

    static var legendNone: String { L("未", "Not yet") }
    static var legendCandidate: String { L("写真の候補", "Suggested") }
    static var legendFourPlus: String { L("4 回以上", "4+") }
    static func legendTimes(_ n: Int) -> String { L("\(n) 回", "\(n)×") }

    // MARK: - 状態

    static var loadingPhotos: String { L("写真から県を調べています", "Looking for prefectures in your photos") }
    static var emptyTitle: String { L("まだ記録がありません", "Nothing recorded yet") }
    static var emptyBody: String { L("県をタップして記録することもできます。写真を投稿すると、撮影地から候補が出ます。",
                                     "Tap a prefecture to record it. Posting photos suggests prefectures from where they were taken.") }
    static var postPhoto: String { L("写真を投稿する", "Post a photo") }
    static var failedPhotos: String { L("写真から県を調べられませんでした。記録はこの端末に残っています。",
                                        "Couldn’t read your photos. Your record is safe on this device.") }
    static var retry: String { L("もう一度試す", "Try again") }
    static var allVisited47: String { L("47県ぜんぶ行った", "I’ve been to all 47") }
    static var allVisitedConfirmTitle: String { L("47県を記録しますか", "Record all 47?") }
    static var allVisitedConfirmBody: String {
        L("まだ記録のない県を、今日の日付で 1 回ずつ記録します。あとから 1 つずつ外せます。",
          "Prefectures without a record get one visit dated today. You can clear them one by one later.")
    }
    static var clearAll: String { L("記録をすべて外す", "Clear all records") }
    static var clearAllConfirmTitle: String { L("記録をすべて外しますか", "Clear all records?") }
    static var clearAllConfirmBody: String { L("写真は消えません。「ひとつ戻す」で戻せます。", "Your photos are not deleted. You can step back.") }
    static var confirm: String { L("記録する", "Record") }
    static var clearConfirm: String { L("すべて外す", "Clear all") }

    // MARK: - 設定の表示（変えられない）

    static var privateNote: String {
        L("あなただけの記録です。ほかの人には見えません。硬貨・バッジ・Pro には関係しません。",
          "Only you can see this. It has nothing to do with coins, badges, or Pro.")
    }

    // MARK: - 祝い

    static func celebrationEyebrow(_ celebration: VisitedPrefectures.Celebration) -> String {
        switch celebration {
        case .allVisited: return L("47 都道府県", "47 PREFECTURES")
        case .roundCompleted(let n): return L("\(n) 周目", "ROUND \(n)")
        }
    }

    static func celebrationTitle(_ celebration: VisitedPrefectures.Celebration) -> String {
        switch celebration {
        case .allVisited: return L("47県、そろいました", "All 47, done")
        case .roundCompleted(let n): return L("\(n) 周、そろいました", "Round \(n), done")
        }
    }

    static func celebrationBody(_ celebration: VisitedPrefectures.Celebration) -> String {
        switch celebration {
        case .allVisited: return L("ここまでの旅の記録です。回数を足していくと、地図の色が変わります。",
                                   "Here is your record so far. Adding visits changes the colors on the map.")
        case .roundCompleted: return L("すべての県が、また 1 回ずつ増えました。", "Every prefecture has gained another visit.")
        }
    }

    static var celebrationRecordCounts: String { L("回数を記録する", "Record visits") }
    static var close: String { L("閉じる", "Close") }

    // MARK: - 拡大

    static var zoomIn: String { L("拡大", "Zoom in") }
    static var zoomOut: String { L("縮小", "Zoom out") }
    static var mapAccessibility: String { L("行った県の地図", "Map of prefectures visited") }

    /// 沖縄の挿入図の名前
    static var okinawaInset: String { L("沖縄県", "Okinawa") }

    // MARK: - バッジからの入口

    static var openFromBadge: String { L("行った県の地図を見る", "See your prefecture map") }

    /// 禁止語（試験が全文言を走査する）
    static let forbiddenWords = ["撮りどき", "捨てる", "注目スポット", "撮影地ガイド", "ガイドを見る", "この場所"]
}
