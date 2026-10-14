import Foundation

/// **v2 の物差し**（Artifact「デザインシステム v2」04 間隔と角・02 字の段、2026-10-14）。
///
/// v2 のいちばんの変更は「全画面が同じ物差しで組まれていること」。画面ごとに 10・14・18 と
/// 書いていた余白・角・高さを、ここの名前で書く。**値は数だけで持つ**（SwiftUI に触らない）——
/// Linux のテストで「4 の倍数か」「12pt を割っていないか」を見張るため（`DesignFoundationTests`）。
///
/// 押せるものの 44 は `WebTheme.minTapTarget`、上のバーの印の 17 は `WebTheme.toolbarIconSize`
/// にある（同じ値を2つ作らない）。

/// 余白。**すべて 4 の倍数、迷ったら 8 の倍数**（板の space-1〜16）
enum JPSpace {
    /// 字と印のすき間
    static let xxs: CGFloat = 4
    /// チップの間
    static let xs: CGFloat = 8
    /// 行の中の要素の間
    static let s: CGFloat = 12
    /// 画面の左右の端・札の内側
    static let m: CGFloat = 16
    /// シートの左右の端
    static let l: CGFloat = 20
    /// 見出しと中身の間
    static let xl: CGFloat = 24
    /// 節と節の間
    static let section: CGFloat = 32
    /// 空の状態の上の余白
    static let emptyTop: CGFloat = 48
    /// 画面の最後（下のタブに隠れない）
    static let screenEnd: CGFloat = 64

    /// 画面の左右の端（`m`）。写真の主役だけ端 8 まで広げる（ホームの1枚目）
    static let gutter: CGFloat = m

    static let all: [CGFloat] = [xxs, xs, s, m, l, xl, section, emptyTop, screenEnd]
}

/// 角の丸み（板の radius-xs〜xl）。ボタン・チップは丸（`Capsule`）
enum JPRadius {
    /// 小さい写真
    static let xs: CGFloat = 6
    /// 入力欄・行の写真（場所の札の 56 の写真）
    static let s: CGFloat = 10
    /// 入力欄（48 の欄）・写真の格子の外枠の角 14 は `m`
    static let field: CGFloat = 12
    /// 写真の札・案内の帯
    static let m: CGFloat = 14
    /// 札
    static let l: CGFloat = 16
    /// シートの上
    static let xl: CGFloat = 24

    static let all: [CGFloat] = [xs, s, field, m, l, xl]
}

/// 線の太さ
enum JPStroke {
    /// 区切り線・札の縁・線のボタンの縁
    static let hairline: CGFloat = 1
    /// 件数バッジ・未読の点の黒い縁、選んでいるタブの下線、未見の輪
    static let emphasis: CGFloat = 2
    /// 未見の輪と写真の間の黒いすき間
    static let ringGap: CGFloat = 3
}

/// 部品の高さ（板の Components 01・05）
enum JPHeight {
    /// 主ボタン（1画面に1つ）
    static let primaryButton: CGFloat = 50
    /// 副ボタン（線・行動の札・「もう一度」）。押せるものの最小と同じ
    static let secondaryButton: CGFloat = 44
    /// 行の中の小ボタン（フォロー）の見た目。当たりは 44
    static let inlineButton: CGFloat = 36
    /// 入力欄
    static let field: CGFloat = 48
    /// 一行の行
    static let row: CGFloat = 52
    /// 二行の行・人の行
    static let tallRow: CGFloat = 64
}

/// 字の段（板 02）。**見出しは明朝、本文はシステム、数字は SF の等幅数字。**
///
/// 本文系の最小は 12（`WebTheme.minBodyText`）、11 は眉ラベルだけ。明朝の最小は 18
/// （黒地の上の細い横画が潰れる）——空の状態の見出しだけ板の 20 を使う。
/// `JPFont` はここの大きさから `Font` を作る
enum JPTypeScale {
    // 明朝（Shippori Mincho B1）
    /// 旅の一冊の表紙・写真の詳細の題（Display）
    static let display: Double = 32
    /// 人の名前・画面の題（Title 1）
    static let title1: Double = 26
    /// 画面の大見出し・節の見出し・カードの題（Title 2）
    static let title2: Double = 22
    /// 空・失敗の状態の見出し（Components 06 の 20）
    static let stateTitle: Double = 20
    /// 札の題。**明朝はここが下限**（Title 3）
    static let title3: Double = 18

    // システム
    /// ナビ・シートの題（SF 600）
    static let headline: Double = 17
    /// 本文・ボタンの字（SF 400 / 600）
    static let body: Double = 15
    /// 副文・文字ボタン
    static let footnote: Double = 13
    /// 注記。**本文系の最小**
    static let caption: Double = 12
    /// 眉ラベルだけ（SF 600・字間 0.14em）
    static let eyebrow: Double = 11
    /// 眉ラベルの字間（0.14em）
    static let eyebrowTracking: Double = eyebrow * 0.14

    // 数字（SF の等幅数字）
    /// 旅の記録の距離（SF 300）
    static let figureLarge: Double = 30
    /// 投稿・フォロワー・フォロー中（SF 400）
    static let figureMedium: Double = 20
    /// 撮影情報・座標・時刻
    static let meta: Double = 12

    static let mincho: [Double] = [display, title1, title2, stateTitle, title3]
    static let text: [Double] = [headline, body, footnote, caption, figureLarge, figureMedium, meta]
}
