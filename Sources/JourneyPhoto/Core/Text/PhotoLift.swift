import Foundation

/// **ホームの写真の行き先**（2026-11-12・札 #543・資料第6章 段1「ホーム」）。
///
/// ホームの写真の読み上げの操作「保存・送る・ストーリーで紹介」の決まり（実行は `PhotoLiftOverlay`）。
/// 選んだ後3秒は取り消せる（送るは3秒たってから送り出す）。
///
/// 2026-11-25 判断（札 #733）: 写真を 0.35秒押さえて手に取り、上の帯・右の半円・下の顔の段へ運ぶ指の身振りは、
/// 1.1.84 から止めていた（`homeGestureEnabled = false`。run 1182 で、札の身振りがホームの払いを奪っていた）。
/// 止めたまま使っていなかったので、身振りの値（押さえる長さ・帯と半円の当たり・弾く判定）とはじめての案内を消した。
/// 戻すときは札 #733 の片づけの PR の前の版から持ってくる（UI 試験の「手に取って運ぶ」の段はコミット e76c348f3 の前にある）
enum PhotoLift {

    /// 選んだ後の取り消しの間（秒）
    static let undoSeconds: Double = 3
    /// 下の顔の段の高さ
    static let bottomBand: Double = 128

    /// 行き先
    enum Target: Equatable {
        /// みんなへ・ストーリーで紹介
        case story
        /// とっておく（保存）
        case save
        /// 下の顔の段の人へ送る
        case face(Int)
    }

    /// ストーリーで紹介を出すか。**自分の写真のときだけ**。
    /// 2026-11-12 判断（確かめ役）: 他人の写真を作者名なしで自分のストーリーに出せてしまうので、他人の写真には出さない
    static func allowsStory(ownerId: String?, me: String?) -> Bool {
        PhotoOwnership.isMine(ownerId: ownerId, me: me)
    }

    /// 選んだ後の一言
    static func doneMessage(_ target: Target, faceName: String?) -> String {
        switch target {
        case .save: return L("保存しました", "Saved")
        case .story: return L("ストーリーで紹介します", "Sharing to your story")
        case .face:
            if let faceName, !faceName.isEmpty { return L("\(faceName) へ送ります", "Sending to \(faceName)") }
            return L("送ります", "Sending")
        }
    }

    /// 送る文（写真のページのリンク・DM は文字だけの口）。題があれば題を添える
    static func shareText(title: String?, url: String) -> String {
        let head = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return head.isEmpty ? url : "\(head)\n\(url)"
    }
}
