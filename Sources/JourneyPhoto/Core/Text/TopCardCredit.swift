import Foundation

/// ホームの上の札（と探すの「今日の一問」の札・`TopCardFace`）の、写真の出典の1行。
///
/// **2026-11-14 判断（owner「出典のせいで縦をとるのあんまり好きじゃない」）: 札の背（116）も行の数（1行）も変えず、
/// 出典の頭（「写真: 作者」の頭）を必ず見せる。**
///
/// 前は「地域　写真: 作者 / ライセンス」を1本の字にして**真ん中で**切っていた（#417 ③）。Mac run 1274 の実測で、
/// 札の字の幅は 222.0pt、「福岡県　久留米市　写真: Asturio Cantabrio / CC BY-SA 4.0」は 307.0pt 要り、
/// 画面には「福岡県　久留米市　写…rio / CC BY-SA 4.0」と出ていた——切れるのはちょうど出典の頭（「写真: 作者」）で、
/// 頭の地域と末尾のライセンス名だけが残り、誰の写真か読めない。索引の作者つきの写真 1,045 件では、
/// 全文が 222pt に入るのは約 15%（実測2件で合わせた字幅の目安）。残りの約 85% で同じように切れていた。
///
/// いまは、入る最初の形を出す（`TopCardFace` の `ViewThatFits`）:
///   1. 地域（県　市）＋出典の全文
///   2. 県だけ＋出典の全文
///   3. 出典の全文
///   4. それでも入らなければ、**作者の後ろだけを切る**（「写真: 作者の頭… / ライセンス」）。
///      ライセンス名は残す（先に幅を取る）
///
/// 削るのは地域から（出典ではない・地域は札を押した先の頁の頭にある）。出典の全文は、札を押した先
/// （撮影スポットの頁・今日の一問・払う画面の `SpotImageCredit`）にリンクつきで出ていて、読み上げも札では全文を読む
/// （`spoken`）。作者とライセンスを並べて出す決まり（CC BY・CC BY-SA の条件・docs/spot-samples-commons.md）は
/// どの形でも崩さない——どの形にも「写真: 作者の頭」と「ライセンス名」が入る
struct TopCardCredit: Equatable {
    /// 地域（「岡山県　倉敷市」・`OfficialSpot.regionLabel`）
    let region: String?
    /// 県だけ（地域が長いときの2つ目の形）
    let prefecture: String?
    /// 出典の前半（「写真: 作者」・`SpotImage.creditAuthor`）
    let author: String
    /// ライセンス名（「CC BY-SA 4.0」）
    let license: String

    init(region: String? = nil, prefecture: String? = nil, photo: SpotImage) {
        self.region = Self.nonEmpty(region)
        self.prefecture = Self.nonEmpty(prefecture)
        author = photo.creditAuthor
        license = photo.license
    }

    /// 撮影スポットの写真の出典（地域つき）
    init(spot: OfficialSpot, photo: SpotImage) {
        self.init(region: spot.regionLabel, prefecture: spot.region?.prefecture, photo: photo)
    }

    /// 出典の全文（「写真: 作者 / ライセンス」・`SpotImage.credit` と同じ字）
    var credit: String { author + licenseTail }

    /// 作者の後ろに続く分（「 / ライセンス」）。4つ目の形では、作者を切ってもこれは残す
    var licenseTail: String { " / \(license)" }

    /// 読み上げる全文（地域と出典）。札を1つの要素として読むとき、形にかかわらずこれを読む
    var spoken: String { Self.join(region, credit) }

    /// 1行に収める形（入る最初のものを出す）。**どれも出典の全文を含む**——削るのは地域だけ。
    /// 同じ字の形は1つにまとめる（地域が無い・県だけの地域）
    var wholeLines: [String] {
        var lines: [String] = []
        for line in [Self.join(region, credit), Self.join(prefecture, credit), credit] where !lines.contains(line) {
            lines.append(line)
        }
        return lines
    }

    /// どの形も入らないときに必ず見せる頭（「写真: 」と作者の初めの数文字）。UI テストの事実取り（`TopCardProbe`）が、
    /// 4つ目の形でこの幅が残っているかを確かめる
    var head: String { String(author.prefix(Self.headPrefixCount(author))) }

    /// 頭として残す字の数（「写真: 」＋作者の初めの 4 文字。短い作者は全部）
    static func headPrefixCount(_ author: String) -> Int {
        let label = L("写真: ", "Photo: ")
        return min(author.count, label.count + 4)
    }

    private static func join(_ lead: String?, _ credit: String) -> String {
        guard let lead else { return credit }
        return lead + "\u{2002}" + credit
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }
}
