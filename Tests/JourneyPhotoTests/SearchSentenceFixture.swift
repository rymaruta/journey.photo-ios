@testable import JourneyPhoto

/// 「自然な文で探す」（札 #623）の読み取りを数える文の例 20件（2026-11-15）。
///
/// 1〜3 は案の模型の例。ほかは担当が、探す人が打ちそうな文として書いた（実際の利用者の検索の記録ではない）。
/// 言葉の表と同じ担当が書いたので、表に甘い。10 と 20 は表に無い言い方（「日が沈む頃」「暗くなってから」）で、
/// 端末の AI が埋めるかを見る。
///
/// 正しいとするのは、字の語・季節・時間帯・欄の無い条件の4つがすべて合うとき（使わなかった語は数えない）
enum SearchSentenceFixture {

    struct Case {
        let sentence: String
        let text: String?
        let season: ShootingTime.Season?
        let dayPart: ShootingTime.DayPart?
        var unsupported: [SearchSentence.Unsupported] = []
        /// 言葉の表で読めるはずか（表に無い言い方は false）
        var table = true

        func matches(_ r: SearchSentence.Reading) -> Bool {
            r.text == text && r.season == season && r.dayPart == dayPart && r.unsupported == unsupported
        }
    }

    static let cases: [Case] = [
        Case(sentence: "京都 紅葉 夜", text: "京都", season: .autumn, dayPart: .night),
        Case(sentence: "雨でも撮れる所", text: nil, season: nil, dayPart: nil, unsupported: [.rain]),
        Case(sentence: "静岡で夕日の海", text: "静岡", season: nil, dayPart: .evening),
        Case(sentence: "北海道の雪景色", text: "北海道", season: .winter, dayPart: nil),
        Case(sentence: "桜と富士山", text: "富士山", season: .spring, dayPart: nil),
        Case(sentence: "東京の夜景", text: "東京", season: nil, dayPart: .night),
        Case(sentence: "秋の朝の雲海", text: nil, season: .autumn, dayPart: .morning),
        Case(sentence: "夏の花火を見たい", text: nil, season: .summer, dayPart: .night),
        Case(sentence: "金沢 冬", text: "金沢", season: .winter, dayPart: nil),
        Case(sentence: "日が沈む頃の海", text: "海", season: nil, dayPart: .evening, table: false),
        Case(sentence: "もみじ狩りに行きたい", text: nil, season: .autumn, dayPart: nil),
        Case(sentence: "星空がきれいな山", text: "山", season: nil, dayPart: .night),
        Case(sentence: "屋内で撮れる場所", text: nil, season: nil, dayPart: nil, unsupported: [.indoor]),
        Case(sentence: "長野 新緑", text: "長野", season: .spring, dayPart: nil),
        Case(sentence: "早朝の鳥居", text: "鳥居", season: nil, dayPart: .morning),
        Case(sentence: "ライトアップされたお寺", text: "寺", season: nil, dayPart: .night),
        Case(sentence: "人の少ない紅葉スポット", text: nil, season: .autumn, dayPart: nil, unsupported: [.crowd]),
        Case(sentence: "沖縄 夏 ビーチ", text: "沖縄", season: .summer, dayPart: nil),
        Case(sentence: "冬の夕方の白川郷", text: "白川郷", season: .winter, dayPart: .evening),
        Case(sentence: "暗くなってからの京都タワー", text: "京都タワー", season: nil, dayPart: .night, table: false),
    ]
}
