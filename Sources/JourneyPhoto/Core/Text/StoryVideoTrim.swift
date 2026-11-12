import Foundation

/// ストーリーの動画の切り取り範囲（秒・2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾）。
///
/// **画面と AVFoundation から出しておく**（Linux の `swift test` で確かめるため）。持つのは元の動画の長さ（`total`）と、
/// 残す範囲 `start ..< end`。決まりは次のとおり:
///  - 残せる長さは**最大 60 秒**（`StoryVideoRules.maxSeconds`・Web と同じ）、**最短 1 秒**（動画が 1 秒より短ければその長さ）
///  - 始点を左へ動かして 60 秒を超えるときは、**終点が引かれてついてくる**（枠が最大 60 秒で保たれる）。
///    終点を右へ動かして超えるときは、始点が押される
///  - 始点は終点を越えない・終点は始点を越えない（最短の長さを残して止まる）
///  - 60 秒より長い動画は、取り込んだ直後は**先頭の 60 秒**を選んである（`init(total:)`）
struct StoryVideoTrim: Equatable {

    /// 最長・最短（秒）と、「−1秒／＋1秒」の刻み
    static let maxLength: Double = StoryVideoRules.maxSeconds
    static let minLength: Double = 1
    static let nudgeStep: Double = 1

    /// 元の動画の長さ（秒）。読めなかったときは 0
    let total: Double
    private(set) var start: Double
    private(set) var end: Double

    /// 取り込んだ直後の範囲。**60 秒以内の動画は全部、長い動画は先頭の 60 秒**
    init(total: Double) {
        let safe = total.isFinite && total > 0 ? total : 0
        self.total = safe
        self.start = 0
        self.end = min(safe, Self.maxLength)
    }

    /// 決まりに収めて範囲を作る（保存した値・テストから）。**始点を先に決め**、終点はそこから最短〜最長の間へ収める
    init(total: Double, start: Double, end: Double) {
        let safe = total.isFinite && total > 0 ? total : 0
        let floorLength = min(Self.minLength, safe)
        let from = start.isFinite ? max(0, min(start, safe - floorLength)) : 0
        let to = end.isFinite ? end : safe
        self.total = safe
        self.start = from
        self.end = min(safe, min(max(to, from + floorLength), from + Self.maxLength))
    }

    /// 残せる最短の長さ。1 秒より短い動画はその長さ
    var minimumLength: Double { min(Self.minLength, total) }

    /// 残す長さ（秒）
    var length: Double { end - start }

    /// 動画を全部残しているか（切っていない）
    var isFull: Bool { start <= 0.001 && end >= total - 0.001 }

    /// 始点を動かす。**範囲の決まり（上の注記）に収まる所まで**
    mutating func setStart(_ seconds: Double) {
        guard total > 0, seconds.isFinite else { return }
        start = max(0, min(seconds, end - minimumLength))
        if end - start > Self.maxLength { end = start + Self.maxLength }
    }

    /// 終点を動かす
    mutating func setEnd(_ seconds: Double) {
        guard total > 0, seconds.isFinite else { return }
        end = min(total, max(seconds, start + minimumLength))
        if end - start > Self.maxLength { start = end - Self.maxLength }
    }

    /// 「−1秒／＋1秒」と読み上げの増減（長い動画の細かい合わせ）
    mutating func nudgeStart(by delta: Double) { setStart(start + delta) }
    mutating func nudgeEnd(by delta: Double) { setEnd(end + delta) }

    /// 範囲ごと動かす（選んだ枠を掴んで左右へ・2026-11-12 判断・設計の案 02）。**長さは変えず**、動画の頭と終わりで止める
    mutating func shift(toStart seconds: Double) {
        guard total > 0, seconds.isFinite else { return }
        let keep = length
        let from = max(0, min(seconds, total - keep))
        start = from
        end = from + keep
    }

    /// 60 秒の枠いっぱいか（反対のつまみがついてくる所・「60秒まで」の札と光の縁を出す）
    var atLimit: Bool { length >= Self.maxLength - 0.001 }

    /// 長さの横の注記（「全体 2:24」・2026-11-12 判断・設計の案 02）。以前は毎回2行の説明を出していた
    var totalNote: String { L("全体 \(Self.label(total))", "Total \(Self.label(total))") }

    /// **60 秒を超える動画のときだけ**添える「60秒まで」。2026-11-12 owner「・」「·」で区切らない:
    /// 「全体 2:24」とは余白（8pt）で分けて並べる
    var limitNote: String? {
        total > Self.maxLength + 0.001 ? L("60秒まで", "Up to 60s") : nil
    }

    /// 範囲の札（「0:12–1:12」）
    var rangeLabel: String { "\(Self.label(start))–\(Self.label(end))" }

    /// つまみの上の吹き出し（「0:12.4」・小数1桁まで。分は桁を揃えない）
    static func preciseLabel(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, seconds) : 0
        let tenths = Int((safe * 10).rounded(.down))
        let minutes = tenths / 600
        let rest = tenths % 600
        let whole = rest / 10
        return "\(minutes):" + (whole < 10 ? "0" : "") + "\(whole).\(rest % 10)"
    }

    /// 動画を開けないか（2026-11-12 判断・設計の案 02「動画を開けない」）。以前は窓が黒いまま何も言わなかった。
    /// **長さが読めない**、または**帯を取り終えて1コマも絵が取れなかった**とき（iCloud から読み込めない・形式に対応していない）。
    /// 帯を取り終えるまでは決めない（骨組みのまま）
    static func cannotOpen(total: Double, framesRead: Int, framesAsked: Int, stripLoaded: Bool) -> Bool {
        if !(total.isFinite && total > 0) { return true }
        return stripLoaded && framesAsked > 0 && framesRead == 0
    }

    /// 帯の読み込み中の光の位置（-1〜1・1.6 秒で左から右へ一回り）。時刻から決める（`TimelineView` が描くたびに読む）
    static func shimmerPhase(at date: Date, period: Double = 1.6) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        guard t.isFinite, period > 0 else { return -1 }
        let cycle = t.truncatingRemainder(dividingBy: period) / period
        return cycle * 2 - 1
    }

    /// 開けないときの説明（何が起きたか・空の状態の本文）
    static var cannotOpenMessage: String {
        L("iCloud から読み込めなかったか、形式に対応していません。",
          "It couldn't be loaded from iCloud, or the format isn't supported.")
    }

    // MARK: - 帯（サムネイルの列）の座標

    /// 時刻 → 帯の横位置（0...width）。範囲の外は端に寄せる
    static func position(of seconds: Double, total: Double, width: CGFloat) -> CGFloat {
        guard total > 0, width > 0, seconds.isFinite else { return 0 }
        return CGFloat(min(max(seconds / total, 0), 1)) * width
    }

    /// 帯の横位置 → 時刻（0...total）
    static func seconds(atPosition x: CGFloat, total: Double, width: CGFloat) -> Double {
        guard total > 0, width > 0, x.isFinite else { return 0 }
        return min(max(Double(x / width), 0), 1) * total
    }

    /// サムネイルを取る時刻。**動画全体を等分した各区間の真ん中**（0 秒ちょうどの黒い1コマを避ける）
    static func thumbnailTimes(total: Double, count: Int) -> [Double] {
        guard total > 0, count > 0 else { return [] }
        let step = total / Double(count)
        return (0..<count).map { (Double($0) + 0.5) * step }
    }

    /// 長さの札・読み上げ用の「0:12」（`StoryVideoClip.label` と同じ）
    static func label(_ seconds: Double) -> String { StoryVideoClip.label(seconds) }

    /// 読み上げ用の「開始 0:12・終了 1:12・長さ 1:00」
    var spokenSummary: String {
        L("開始 \(Self.label(start))、終了 \(Self.label(end))、長さ \(Self.label(length))",
          "Start \(Self.label(start)), end \(Self.label(end)), length \(Self.label(length))")
    }
}
