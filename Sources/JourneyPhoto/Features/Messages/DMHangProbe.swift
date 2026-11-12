import Foundation

/// **UI テストの事実取りだけ**: DM の会話が下へ払った直後から固まる件（2026-11-12 run 1164・1171・統合の枝 1.1.84）で、
/// 疑う箇所を1つずつ外す・固定する印（Debug のみ・Release では必ず全部 false）。
///
/// 起動の引数 `-JPDM<名前> YES` で効く。同じ試験（`DMHangProbeTests`）を印ありとなしで1回の Mac の回に並べて流し、
/// **どの印で固まらなくなるか**を数で見る（推定で直さない・CLAUDE.md）。直しが決まったら、この印と試験は外す。
///
/// | 印 | 外すもの |
/// |---|---|
/// | `JPDMNoSpotCard` | 観光スポットの札（`DMSpotCard`）。リンクの通は文の吹き出しのまま出す |
/// | `JPDMSpotCardFixed` | 札は出すが、読み込み中・読めた・読めないの高さを同じ値に固定する |
/// | `JPDMSpotCardStatic` | 札は出すが、読み込まない（いつも「読めない」＝リンクの文）。`.task` の状態の替わりを外す |
/// | `JPDMNoSpotMessages` | 見本の会話から、観光スポットの2通（リンクと「雪吊り…」）を除く（dm-base と同じ会話） |
/// | `JPDMNoWidthRead` | 会話の幅を読む `onGeometryChange` → 吹き出しの最大幅（幅は 390pt の値で固定） |
/// | `JPDMNoTripBand` | 旅行プランの帯と、その索引の読み込み（`trip.load`） |
/// | `JPDMPlainText` | 吹き出しの文のリンクの印（`AttributedString`）。ただの文にする |
/// | `JPDMNoInnerIds` | 行の中の `.id(message.id)`（吹き出し・時刻・空の枠） |
/// | `JPDMNoAutoScroll` | 開いたとき・数が変わったときの `scrollTo`（いちばん下へ送る） |
/// | `JPDMEagerStack` | `LazyVStack` を `VStack` にする（遅延の配置そのものが要るかの確かめ） |
/// | `JPDMRevertSpotFix` | 直し（札の枠 `DMSpotCardBox` と `DMSpotCardMemory`）を戻す。札はいつも「読み込み中」から始まり、状態ごとに高さが違う（直す前の形） |
enum DMHangProbe {
    static let names = [
        "NoSpotCard", "SpotCardFixed", "SpotCardStatic", "NoSpotMessages", "NoWidthRead", "NoTripBand",
        "PlainText", "NoInnerIds", "NoAutoScroll", "EagerStack", "RevertSpotFix",
    ]

    static func on(_ name: String) -> Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "JPDM" + name)
        #else
        return false
        #endif
    }

    static var noSpotCard: Bool { on("NoSpotCard") }
    static var spotCardFixed: Bool { on("SpotCardFixed") }
    static var spotCardStatic: Bool { on("SpotCardStatic") }
    static var noSpotMessages: Bool { on("NoSpotMessages") }
    static var noWidthRead: Bool { on("NoWidthRead") }
    static var noTripBand: Bool { on("NoTripBand") }
    static var plainText: Bool { on("PlainText") }
    static var noInnerIds: Bool { on("NoInnerIds") }
    static var noAutoScroll: Bool { on("NoAutoScroll") }
    static var eagerStack: Bool { on("EagerStack") }
    static var revertSpotFix: Bool { on("RevertSpotFix") }

    // MARK: 数（札が出た・消えた・読み始めた・読み終えた回数。主スレッドの見張りのファイルの各行に `dm=` で出す）

    private static let countLock = NSLock()
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func count(_ name: String) {
        #if DEBUG
        countLock.lock()
        counts[name, default: 0] += 1
        countLock.unlock()
        #endif
    }

    /// `spotCard.appear=3,spotCard.load=3,…`（何も数えていなければ空）
    static var countSummary: String {
        countLock.lock()
        defer { countLock.unlock() }
        return counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// 札を固定する高さ（読めた札のいちばん高い形より大きめ: 写真 130 ＋ 名前2行・種類・ボタン 44・出典 ≒ 300）
    static let spotCardFixedHeight: CGFloat = 320

    /// 効いている印（会話の見えない要素 `dm.probe` の値の `hangProbe=` に出す。試験が印の効きを確かめる）
    static var active: String {
        names.filter(on).joined(separator: ",")
    }
}
