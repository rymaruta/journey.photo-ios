import Foundation

// 1.1.83 の案「トランクと旅の画面のデザイン」（2026-11-12 判断）の言葉と決まり。
// 主ボタン1つで最後まで・押せばすぐ決まり、「取り消す」「ひとつ戻す」で戻す。SwiftUI を読まない層（Linux でテストできる）。

extension TrunkText {
    /// 知らせの「取り消す」
    static var undoTitle: String { L("取り消す", "Undo") }

    /// 届いた画面で貼って閉じたあとの知らせ（1 枚は今までどおり・何枚もはおまかせの所へ貼ったこと）
    /// まとめて貼る途中で貼れなかった分（`left`）があれば、貼れた枚数と手持ちに残った枚数を言う
    static func arrivalStuckNotice(count: Int, left: Int = 0) -> String {
        if left > 0 {
            return L("\(count) 枚貼りました。\(left) 枚は手持ちにあります",
                     "Stuck \(count). \(left) still in your pocket")
        }
        return count > 1 ? L("空いている所へおまかせで貼りました", "Stuck them in free spots for you")
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

    /// 主ボタンの下の一行。2026-11-23（札 #716・案の頁の「言葉」）: 起きたことは動きで見せ、文は次にできることだけ。
    /// 返事を待つ間とカプセルが出たときは文なし（溜めと、落ちて弾む動きで見せる）。前の「カプセルが出てきます…」
    /// 「ころん、と1つ出てきました」（実況の文）は消した
    static func spinHint(coins: Int, phase: TrunkGachaPhase, offline: Bool = false) -> String {
        switch phase {
        case .idle:
            if coins == 0 {
                return L("公開の投稿1件で、硬貨を1枚もらえます（1日3枚まで）", "You get one coin per public post (up to 3 a day)")
            }
            return offline ? L("電波が戻ると回せます", "You can turn it once you\u{2019}re back online")
                : L("ハンドルを指で回しても出ます", "You can also turn the handle with your finger")
        case .turning:
            return L("途中で離すと戻ります。硬貨は減りません", "Let go early and it springs back. No coin is used.")
        case .waiting, .out:
            return ""
        }
    }

    /// 回している間の帯（「ハンドルを右へ回す 42%」）
    static var turningTitle: String { L("ハンドルを右へ回す", "Turn the handle right") }

    /// 圏外と分かっているとき、回す前に出す一言（ボタンは押せない・2026-11-23 札 #716）
    static var offlineNote: String {
        L("電波が無いので回せません。硬貨は減りません", "No signal, so it can\u{2019}t turn. No coin is used.")
    }

    /// 送ったあとに切れた・時間切れのとき（回ったかどうか分からない）の一言。読み直した硬貨の数を前と比べて言い分ける
    /// （2026-11-12 判断）。減っていれば回っていた（出た部品は部品箱にある）、減っていなければ回っていない、
    /// 読み直せなければ分からないと言う（分からないことを「減っていません」と言わない）
    static func afterUnsure(coinsBefore: Int, coinsAfter: Int?) -> String {
        guard let after = coinsAfter else {
            return L("回せたか分かりませんでした。電波のある所で部品箱を開くと分かります",
                     "Couldn\u{2019}t tell whether it turned. Open your parts box where you have a signal to see.")
        }
        if after < coinsBefore {
            return L("回せていました。出た部品は部品箱にあります", "It did turn. The part is in your parts box.")
        }
        return L("回せませんでした。硬貨は減っていません", "It didn\u{2019}t turn. No coin was used.")
    }

    /// 送る前から圏外と分かっていて、送らなかった（サーバーに何も届いていないので硬貨は減っていない）
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

    /// 自分で回している途中で、次の1歩を進めるか（画面を離れたら止めて元へ戻し、サーバーには送らない）
    static func keepsAutoTurning(visible: Bool) -> Bool { visible }

    /// 機械に見せる硬貨の数（確かめ役の指摘 2026-11-23）。入れている間も、回している間も、入れた1枚を引いて見せる。
    /// 入れる動きで「いちばん上を隠す」と、6枚以上のときは重ねた絵が5枚のままなので、回り始めると隠した1枚が戻って見えた
    static func shownCoins(stored: Int, phase: TrunkGachaPhase, inserting: Bool) -> Int {
        inserting || phase == .turning || phase == .waiting ? max(0, stored - 1) : stored
    }

    /// 待っているときの操作（2026-11-23 札 #716）
    struct Idle: Equatable {
        /// 「硬貨を入れて回す」を押せる
        let canTurn: Bool
        /// 回す前に出す圏外の一言
        let offlineNote: Bool
        /// ハンドルを触ったら回り始める（false なら小さく揺れるだけ）
        let crankTurns: Bool
    }

    /// 0枚は投稿への一手（回せない・ハンドルは揺れる）。圏外は一言を出して押せない（ハンドルは揺れる）
    static func idle(coins: Int, offline: Bool, busy: Bool = false) -> Idle {
        guard coins > 0 else { return Idle(canTurn: false, offlineNote: false, crankTurns: false) }
        if offline { return Idle(canTurn: false, offlineNote: true, crankTurns: false) }
        return Idle(canTurn: !busy, offlineNote: false, crankTurns: !busy)
    }

    /// 開けた画面を閉じたあと（「もう1回まわす」を押していれば、硬貨を入れて続けて回す。圏外・0枚なら回さない）
    static func afterOpenClosed(again: Bool, coins: Int, offline: Bool) -> Bool {
        again && idle(coins: coins, offline: offline).canTurn
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
        // 2つの手は改行で分ける（区切りの記号を使わない）
        if p >= 0.98 { return L("押すと手に取れます\nふたを上へ払うと閉じます", "Tap to pick up\nSwipe the lid up to close it") }
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
