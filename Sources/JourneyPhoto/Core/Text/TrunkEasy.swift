import Foundation

// 1.1.83 の案「トランクと旅の画面のデザイン」（2026-11-12 判断）の言葉と決まり。
// 主ボタン1つで最後まで・押せばすぐ決まり、「取り消す」「ひとつ戻す」で戻す。SwiftUI を読まない層（Linux でテストできる）。

extension TrunkText {
    /// 知らせの「取り消す」
    static var undoTitle: String { L("取り消す", "Undo") }

    /// 届いた画面で貼って閉じたあとの知らせ（1 枚は今までどおり・何枚もはおまかせの所へ貼ったこと）
    static func arrivalStuckNotice(count: Int) -> String {
        count > 1 ? L("空いている所へおまかせで貼りました", "Stuck them in free spots for you")
            : L("トランクに貼りました", "Stuck on your trunk")
    }

    /// 型を替えた知らせ（押すとすぐ替わる・取り消しで戻す）
    static func modelChangedNotice(_ name: String) -> String {
        L("「\(name)」にしました", "Switched to \u{201C}\(name)\u{201D}")
    }
}

/// ラベルが届いた画面の言葉（何枚も届いたら「まとめて貼る」1回・2026-11-12 判断）
enum TrunkArrivalCopy {
    /// 見出し（1 枚は「京都のラベルが届きました」、何枚もは「ラベルが 3 枚届きました」）
    static func title(count: Int, place: String) -> String {
        if count > 1 { return L("ラベルが \(count) 枚届きました", "\(count) labels arrived") }
        return place.isEmpty ? L("ラベルが届きました", "A label arrived")
            : L("\(place)のラベルが届きました", "A label from \(place)")
    }

    /// お礼の一行
    static func thanks(count: Int, photoTitle: String) -> String {
        if count > 1 {
            return photoTitle.isEmpty
                ? L("写真 \(count) 枚を投稿したお礼です", "Thank you for posting \(Plural.count(count, "photo"))")
                : L("「\(photoTitle)」ほか \(count - 1) 枚を投稿したお礼です",
                    "Thank you for posting \u{201C}\(photoTitle)\u{201D} and \(count - 1) more")
        }
        return photoTitle.isEmpty ? L("写真を投稿したお礼です", "Thank you for posting a photo")
            : L("「\(photoTitle)」を投稿したお礼です", "Thank you for posting \u{201C}\(photoTitle)\u{201D}")
    }

    /// 主ボタン（何枚もは「3 枚まとめて貼る」）
    static func stickTitle(count: Int) -> String {
        count > 1 ? L("\(count) 枚まとめて貼る", "Stick all \(count)") : L("トランクに貼る", "Stick on my trunk")
    }

    /// 副ボタン（手持ちへ入れて閉じる）
    static var laterTitle: String { L("あとで貼る（手持ちへ）", "Later (keep in pocket)") }

    /// 電波が無くて貼れなかった（ラベルは手持ちにある）
    static var offlineNote: String {
        L("電波が無いので貼れませんでした。ラベルは手持ちに入っています",
          "No signal, so we couldn\u{2019}t stick it. The label is in your pocket.")
    }
}

extension TrunkGachaText {
    /// 主ボタン（硬貨を入れて、そのまま回す）
    static func spinTitle(coins: Int) -> String {
        coins > 0 ? L("硬貨を入れて回す", "Insert a coin and turn") : L("硬貨がありません", "No coins")
    }

    /// 主ボタンの下の一行（ハンドルは指で回しても出る）
    static func spinHint(coins: Int, phase: TrunkGachaPhase) -> String {
        switch phase {
        case .idle:
            return coins > 0 ? L("ハンドルを指でまわしても出ます", "You can also turn the handle with your finger")
                : L("公開の投稿1件で、硬貨が1枚もらえます（1日3枚まで）", "You get one coin per public post (up to 3 a day)")
        case .turning:
            return L("右へ1周で出ます。途中で離すと戻り、硬貨は減りません",
                     "One full turn to the right. Let go early and it springs back; no coin is used")
        case .waiting:
            return L("カプセルが出てきます…", "A capsule is coming…")
        case .out:
            return L("ころん、と1つ出てきました", "Out rolls a capsule")
        }
    }

    /// 電波が無くて回せなかった（サーバーが答えていないので硬貨は減っていない）
    static var unreachable: String {
        L("電波が無いので回せませんでした。硬貨は減っていません", "No signal, so it didn\u{2019}t turn. No coin was used.")
    }
}

/// カプセルの機械の流れ（2026-11-12 判断・案: 主ボタンは「硬貨を入れて回す」1つ＋ハンドルを指で回しても出る）。
///
/// - ボタン（とハンドルを軽く押す）: 硬貨を入れ、ハンドルが自分で1周する（目盛り 12 個ぶん進める）
/// - ハンドルを指で回す: 押さえた所から回り始め、1周で出る。**途中で離すと元へ戻り、硬貨は減らない**
///   （部品は1周したときにサーバーが決める・硬貨もそのとき減る。今の決まりのまま）
enum TrunkGachaFlow {
    /// 自分で回すときの1歩（目盛り 30° ずつ・12 歩で1周）
    static let autoStep = TrunkCrank.tickStep
    /// 自分で回す1歩の間（秒）。12 歩で約 0.84 秒
    static let autoStepSeconds = 0.07

    /// 自分で回すときの歩数（1周まで）
    static var autoSteps: Int { Int((TrunkCrank.goal / autoStep).rounded(.up)) }

    /// 指を離したときの行き先
    enum Release: Equatable {
        /// 1周した: 回す（サーバーに聞く）
        case draw
        /// 押しただけ（動きが少ない）: ボタンと同じく自分で1周する
        case autoTurn
        /// 途中で離した: 元へ戻す（硬貨は減らない）
        case springBack
    }

    static func release(_ crank: TrunkCrank) -> Release {
        if crank.isDone { return .draw }
        if crank.moved <= TrunkCrank.tapSlop { return .autoTurn }
        return .springBack
    }
}

extension TrunkCrank {
    /// 自分で1歩回す（`TrunkGachaFlow.autoStep`）。越えた目盛りの数を返す
    @discardableResult
    mutating func autoAdvance() -> Int {
        guard !isDone else { return 0 }
        return turn(by: TrunkGachaFlow.autoStep)
    }
}

/// 自分のトランクのふた（2026-11-12 判断・案「ふた・中身・型」: 開くと自分で開く・2 回 → 1 回）。
/// 「ふたを開ける」「中身を手に取る」のボタンと開き具合の棒をやめ（棒は読み上げのときだけ）、下は一言だけ
enum TrunkLidCopy {
    static func hint(_ p: Double) -> String {
        if p <= 0.02 { return L("トランクを押すと、ふたが開きます", "Tap the trunk to open the lid") }
        if p >= 0.98 { return L("押すと手に取れます · ふたを上へ払うと閉じます", "Tap to pick up · Swipe the lid up to close it") }
        return TrunkLid.hint(p)
    }

    /// 指を離したときの行き先。**払った勢い**（指の速さから見込んだ終わりの位置 `predictedEndTranslation`）で決める——
    /// 開いたふたを上へ払えば、半分まで引かなくても閉じる（2026-11-12 判断・案「上へ払うと閉じる」）。ゆっくり離せば、
    /// 見込みは今の位置とほぼ同じなので前と同じ「近い方へ」
    static func settled(from start: Double, predictedDy: Double) -> Double {
        TrunkLid.settled(TrunkLid.dragged(from: start, dy: predictedDy))
    }

    /// 開いたら自分でふたを開けるか（引いている最中・もう開いている・中身を持っているときは動かさない）
    static func opensOnAppear(p: Double, dragging: Bool, holding: Bool) -> Bool {
        !dragging && !holding && p == 0
    }
}

/// 部品箱の圏外の帯（2026-11-12 判断・案「部品箱」の状態: 前に見た部品箱を出し、付け替えは電波が戻ってから）
enum TrunkPartsOfflineCopy {
    static var title: String { L("電波が届いていません", "No signal") }
    static var detail: String {
        L("前に見た部品箱を出しています。付け替えは電波が戻ってから", "Showing your parts box from last time. Change parts once you\u{2019}re back online.")
    }
}
