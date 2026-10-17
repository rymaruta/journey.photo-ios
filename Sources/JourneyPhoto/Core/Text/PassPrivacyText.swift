import Foundation

/// すれちがいの説明の文（設定の札・オンにする前の説明・カードの但し書き）。
/// **仕組みの事実に合わせる**（2026-10-16 の読み直し）。
///
/// 中身は暗号化しておらず、近くの Bluetooth 機器なら誰でも読める・値は乗車券を変えるまで同じ・
/// ブロックした人の端末にも届きうる（`PassRadio` の注記）。「いま近くに誰がいるかは見られません」のような、
/// 仕組みが守っていない約束は書かない。テストで見張る（`PassExchangeTests`）
enum PassPrivacyText {

    static var noteTitle: String {
        L("近くの Bluetooth 機器から、乗車券の写真・ひとこと・発と着の字が読めます",
          "Bluetooth devices nearby can read your ticket photo, note and from/to text")
    }

    /// 電波で出す中身（`PassExchange.Payload`: 写真の id・ひとこと・発・着・居住地を出すかの印・券面の種類）を**全部**書く
    /// （2026-10-16 の読み直し: 発・着と居住地が抜けていた。2026-10-17: 券面の種類を足した）
    static var noteBody: String {
        L("カードの中身は暗号化していません。このアプリでなくても、近くで Bluetooth を調べる機器からは、電波で出している中身——乗車券の写真（公開一覧から持ち主も分かります）・ひとこと・乗車券の発と着の字・居住地を出すかの印・券面の種類——が読めます。「発」を居住地にしているときは、受け取った人にあなたのプロフィールの居住地の都道府県が出ます。乗車券を変えるまで同じ値です。ブロックした人にも、あなたのカードは届きえます。受け取ったカードはその日の夕方にまとめて届きます。",
          "Your card isn\u{2019}t encrypted. Any Bluetooth device nearby \u{2014} not only this app \u{2014} can read what it sends: your ticket photo (and, from the public gallery, who posted it), your note, the from/to text on the ticket, whether to show where you live and your ticket design. If \u{201C}From\u{201D} is set to your home, people who receive your card see the prefecture from your profile. It stays the same until you change your ticket. People you blocked may still receive your card. Cards you receive arrive together that evening.")
    }

    /// オンにする前の説明の点（記号・文）
    static var introPoints: [(symbol: String, text: String)] {
        [
            ("dot.radiowaves.left.and.right",
             L("近くにいたアプリの人と、あなたが選んだ写真1枚がカードで交換されます。Bluetooth を使います。",
               "You and app users nearby swap one photo each as a card. This uses Bluetooth.")),
            ("antenna.radiowaves.left.and.right",
             L("オンの間は、乗車券の写真・ひとこと・乗車券の発と着の字・居住地を出すかの印・券面の種類を暗号化せずに電波で出します。近くの Bluetooth 機器なら誰でも読め、写真から持ち主も分かります。「発」を居住地にしていると、受け取った人に居住地の都道府県が出ます。乗車券を変えるまで同じ値です。",
               "While on, your ticket photo, note, the from/to text on the ticket, whether to show where you live and your ticket design are sent over the air unencrypted. Any Bluetooth device nearby can read them and find who posted the photo. If \u{201C}From\u{201D} is set to your home, people who receive your card see your prefecture. They stay the same until you change your ticket.")),
            ("clock",
             L("受け取ったカードは、その日の夕方 18 時に束でまとめて届きます。",
               "Cards you receive arrive together at 6 PM that day.")),
            ("mappin",
             L("すれちがった場所は「〇〇のあたり」、時刻は「15 時ごろ」の粗さで、この iPhone の中にだけ残ります。",
               "Where and when you passed is kept only on this iPhone, roughly (\u{201C}around \u{2026}\u{201D}, \u{201C}around 3 PM\u{201D}).")),
            ("hand.raised",
             L("ブロックした人のカードはあなたには出ませんが、あなたのカードはブロックした人にも届きえます。いつでもオフにできます。",
               "Cards from people you blocked aren\u{2019}t shown to you, but your card may still reach them. Turn it off at any time.")),
        ]
    }

    /// 裏のひとことの但し書き（署名が無いので、写真の持ち主が書いたとは限らない）
    static var noteSource: String {
        L("相手の端末から届いた文（写真の持ち主が書いたとは限りません）",
          "Sent from the other device \u{2014} not necessarily written by the photo\u{2019}s owner")
    }

    /// 「ありがとう」の下の一行
    static var thanksNotice: String {
        L("相手にあなたの名前でいいねが届きます", "They\u{2019}ll get a like from you, with your name")
    }
}
