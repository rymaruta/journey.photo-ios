import Foundation

/// **手に取って運ぶ**（2026-11-12・札 #543・資料第6章 段1「ホーム」・推奨 B＋A）。
///
/// ホームの写真を 0.35秒押さえて手に取り、親指の近くの行き先へ運ぶか、その向きへ短く弾く。
/// 行き先は3つ（**上の帯＝ストーリーで紹介・右の半円＝とっておく・下の顔の段＝この人へ送る**）。
/// 左の縁は「戻る」の払いとぶつかるので使わない。落とした後3秒は取り消せる（送るは3秒たってから送り出す）。
/// 押す回数は 保存 2→0・送る 3→0・ストーリーで紹介 3→0（＋作る画面）。今のボタンは全部残す（読み上げの道）。
///
/// 値は章の模型（`home2.js`）の値。**実機で触って決める**（章「確かめていないこと」）:
/// 押さえる 0.35秒・動いたら手に取らない 10pt・右の半円の半径 105pt・弾く判定（離す直前 90ms の速さ
/// 0.5pt/ms 以上・20pt 以上動いた）
enum PhotoLift {

    /// 押さえる長さ（秒）。ストーリーで止まるのと同じ長さ
    static let pressSeconds = 0.35
    /// 押さえている間にこれ以上動いたらスクロール（手に取らない）
    static let moveTolerance: Double = 10
    /// 落とした後の取り消しの間（秒）
    static let undoSeconds: Double = 3
    /// はじめての1回だけ出す3つの向きの矢印の長さ（秒）
    static let hintSeconds: Double = 2.2

    /// 上の帯の高さ（ここより上で離すとストーリーで紹介）
    static let topBand: Double = 110
    /// 下の顔の段の高さ（ここより下で離すと顔）
    static let bottomBand: Double = 128
    /// 右の半円の半径
    static let saveRadius: Double = 105
    /// 右の半円の中心の高さ（画面の高さに対する割合。章の模型 430 / 844）
    static let saveCenterRatio = 430.0 / 844.0
    /// 近づくと吸い付き始める距離（帯・半円の外側）
    static let nearSlack: Double = 40

    /// 弾く判定に使う、離す直前の時間（秒）
    static let flickWindow = 0.09
    /// 弾いたと見なす速さ（pt/秒）。0.5pt/ms
    static let flickSpeed: Double = 500
    /// 弾いたと見なす最小の動き（pt）
    static let flickDistance: Double = 20

    /// 行き先
    enum Target: Equatable {
        /// 上の帯（みんなへ・ストーリーで紹介）
        case story
        /// 右の半円（とっておく＝保存）
        case save
        /// 下の顔の段の何人目か
        case face(Int)
    }

    /// 右の半円の中心（画面の右の縁の上）
    static func saveCenter(width: Double, height: Double) -> (x: Double, y: Double) {
        (width, height * saveCenterRatio)
    }

    /// 指の位置の行き先（無ければ nil・外で離すと元へ戻る）
    static func target(x: Double, y: Double, width: Double, height: Double, faces: Int) -> Target? {
        if y < topBand { return .story }
        let c = saveCenter(width: width, height: height)
        if hypot(x - c.x, y - c.y) < saveRadius { return .save }
        if faces > 0, y > height - bottomBand {
            let slot = width / Double(faces)
            return .face(max(0, min(faces - 1, Int(x / slot))))
        }
        return nil
    }

    /// 近くまで来た行き先（吸い付きの合図。中に入っていれば `target` と同じ）
    static func near(x: Double, y: Double, width: Double, height: Double, faces: Int) -> Target? {
        if let inside = target(x: x, y: y, width: width, height: height, faces: faces) { return inside }
        if y < topBand + nearSlack { return .story }
        let c = saveCenter(width: width, height: height)
        if hypot(x - c.x, y - c.y) < saveRadius + nearSlack { return .save }
        if faces > 0, y > height - bottomBand - nearSlack { return .face(-1) }
        return nil
    }

    /// 弾いた向き
    enum Flick: Equatable {
        /// 右へ＝とっておく
        case save
        /// 上へ＝ストーリーで紹介
        case story
        /// 下へ＝送る人の列を開いたままにする
        case faces
    }

    /// 指の跡（時刻・位置）から、弾いたか。**離す直前 `flickWindow` 秒の速さ**で見る。
    /// 左へ弾いても何もしない（左の縁は戻る）
    static func flick(samples: [(t: Double, x: Double, y: Double)]) -> Flick? {
        guard let last = samples.last, let first = samples.first,
              hypot(last.x - first.x, last.y - first.y) >= flickDistance else { return nil }
        let recent = samples.filter { last.t - $0.t <= flickWindow }
        guard let from = recent.first, last.t > from.t else { return nil }
        let dt = last.t - from.t
        let vx = (last.x - from.x) / dt, vy = (last.y - from.y) / dt
        guard hypot(vx, vy) >= flickSpeed else { return nil }
        if abs(vx) >= abs(vy) { return vx > 0 ? .save : nil }
        return vy < 0 ? .story : .faces
    }

    /// 指の上の札「離すと 保存」（離すと何が起きるかだけ）
    static func releaseLabel(_ target: Target?, faceName: String? = nil) -> String {
        switch target {
        case .story: return L("離すと ストーリーで紹介", "Release to share to story")
        case .save: return L("離すと 保存", "Release to save")
        case .face:
            if let faceName, !faceName.isEmpty { return L("離すと \(faceName) へ送る", "Release to send to \(faceName)") }
            return L("離すと 送る", "Release to send")
        case nil: return L("離すと 元に戻る", "Release to put back")
        }
    }

    /// 落とした後の一言
    static func doneMessage(_ target: Target, faceName: String?) -> String {
        switch target {
        case .save: return L("しおりにとっておきました", "Saved to your bookmarks")
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
