import Foundation

/// すれちがいの説明の文（設定の札・オンにする前の説明・カードの但し書き）。
/// **仕組みの事実に合わせる**（2026-10-16 の読み直し）。
///
/// 中身は暗号化しておらず、近くの Bluetooth 機器なら誰でも読める・値は乗車券を変えるまで同じ・
/// ブロックした人の端末にも届きうる（`PassRadio` の注記）。「いま近くに誰がいるかは見られません」のような、
/// 仕組みが守っていない約束は書かない。テストで見張る（`PassExchangeTests`）
enum PassPrivacyText {

    static var noteTitle: String {
        L("近くの Bluetooth 機器から、乗車券の写真、ひとこと、区間（発と着）が読めます",
          "Bluetooth devices nearby can read your ticket photo, note and route (from and to)")
    }

    /// 電波で出す中身（`PassExchange.Payload`: 写真の id・ひとこと・発・着・居住地を出すかの印・券面の種類）を**全部**書く
    /// （2026-10-16 の読み直し: 発・着と居住地が抜けていた。2026-10-17: 券面の種類を足した）
    static var noteBody: String {
        L("乗車券の中身は暗号化していません。このアプリでなくても、近くで Bluetooth を調べる機器なら、次のものが読めます。\n乗車券の写真（公開一覧から持ち主も分かります）、ひとこと、区間（発と着）、居住地を出すかどうか、券面の種類\n「発」を居住地にしていると、受け取った人にプロフィールの居住地の都道府県が出ます。中身は乗車券を変えるまで同じです。\nブロックした人にも、あなたの乗車券が届くことがあります。すれちがってすぐ届くこともあるので（受け取る人の設定によります）、届いた時刻から、あなたが少し前に近くにいたことが相手に分かります。",
          "Your ticket isn\u{2019}t encrypted. Any Bluetooth device nearby \u{2014} not only this app \u{2014} can read:\nyour ticket photo (and, from the public gallery, who posted it), your note, the route (from and to), whether to show where you live, and your ticket design.\nIf \u{201C}From\u{201D} is set to your home, people who receive your ticket see the prefecture from your profile. It stays the same until you change your ticket.\nPeople you blocked may still receive your ticket. It may reach people right after you pass (it depends on their settings), so they can tell you were nearby a little earlier.")
    }

    /// オンにする前の説明の点（記号・文）
    static var introPoints: [(symbol: String, text: String)] {
        [
            ("dot.radiowaves.left.and.right",
             L("近くにいた人と、あなたが選んだ写真1枚を乗車券にして交換します。Bluetooth を使います。",
               "Swap one photo each, as a ticket, with people you pass nearby. This uses Bluetooth.")),
            ("antenna.radiowaves.left.and.right",
             L("中身は暗号化していません。乗車券の写真、ひとこと、区間（発と着）、居住地を出すかどうか、券面の種類は、近くの Bluetooth 機器なら誰でも読め、写真から持ち主も分かります。「発」を居住地にすると、受け取った人に居住地の都道府県が出ます。中身は乗車券を変えるまで同じです。",
               "Nothing is encrypted. Your ticket photo, note, route (from and to), whether to show where you live and your ticket design can be read by any Bluetooth device nearby, and the photo shows who posted it. If \u{201C}From\u{201D} is set to your home, people who receive your ticket see your prefecture. It stays the same until you change your ticket.")),
            ("clock",
             L("受け取った乗車券は、すれちがうとすぐ届きます。知らせは \(PassPrivacyText.noticeMinutes) 分に1回まで。設定で、夕方 18 時にまとめて受け取ることもできます。",
               "Tickets you receive arrive as soon as you pass. Alerts come at most once every \(PassPrivacyText.noticeMinutes) minutes. In Settings, you can get them together at 6 PM instead.")),
            ("mappin",
             L("すれちがった場所は「〇〇のあたり」、時刻は「15 時ごろ」くらいの大まかさで、この iPhone の中にだけ残ります。",
               "Where and when you passed is kept only on this iPhone, roughly (\u{201C}around \u{2026}\u{201D}, \u{201C}around 3 PM\u{201D}).")),
            ("hand.raised",
             L("ブロックした人の乗車券はあなたには出ませんが、あなたの乗車券はブロックした人にも届くことがあります。いつでもオフにできます。",
               "Tickets from people you blocked aren\u{2019}t shown to you, but your ticket may still reach them. Turn it off at any time.")),
        ]
    }

    /// 知らせをまとめる間（分・`PassExchange.noticeInterval` から）
    static var noticeMinutes: Int { Int(PassExchange.noticeInterval / 60) }

    /// 設定の「夕方にまとめて受け取る」の説明（2026-11-10）
    static var eveningDetail: String {
        L("オフなら、すれちがうとすぐ届きます（知らせは \(noticeMinutes) 分に1回まで）。オンなら、その日の分を夕方 18 時にまとめて届けます。",
          "When off, tickets arrive as soon as you pass (alerts at most once every \(noticeMinutes) minutes). When on, the day\u{2019}s tickets arrive together at 6 PM.")
    }

    /// 裏のひとことの但し書き（署名が無いので、写真の持ち主が書いたとは限らない）
    static var noteSource: String {
        L("相手の端末から届いた文（写真の持ち主が書いたとは限りません）",
          "Sent from the other device \u{2014} not necessarily written by the photo\u{2019}s owner")
    }

    /// 「ありがとう」の下の一行
    static var thanksNotice: String {
        L("相手にあなたの名前でありがとうが届きます", "They\u{2019}ll get your thanks, with your name")
    }
}
