import SwiftUI

/// 入力と確定の部品（板 41〜47「はじめる・安全・設定」の列）。
///
/// **板は7画面とも同じ3つの形を使っている**——見出し付きの 48pt の欄、
/// カプセル（v2 で塗り 50・線 44）、下に固定したぼかしの帯。以前は画面ごとに書き分けて
/// いて、同じ「パスワードの欄」でもログインは枠付き・変更は素の行、と割れていた。

/// 見出し付きの入力欄（板: 12px・medium・白72% の見出し ＋ 48pt・角丸12・
/// 地6% の欄）。複数行（通報の補足）は 88pt。
///
/// **縁は `WebTheme.outline`（#666666・2026-10-17 判断）。** 画面の板は縁 12% で描いてあるが、
/// 黒の上で 1.27 しかなく、地も 6% なので欄の在りかが見えなかった（完成度レビュー P2）。
/// デザインシステムの入力欄（03 の検索欄・`outline`・部品の縁の 3:1）に合わせた
///
/// **字は文字の大きさの設定に追従させる**（`.caption` = 12・`.subheadline` = 15 が
/// 既定の大きさで板の px と同じ。固定の pt にすると、大きな文字の人だけ読めない）
struct JPField<Content: View>: View {

    let title: String
    var multiline = false
    /// 1行の欄の高さ（既定は板の 48。ログイン画面は画面の大きさで 44 / 50・2026-11-23 判断・`SignInLayout.Metrics`）
    var height: CGFloat = JPHeight.field
    let content: Content

    init(_ title: String, multiline: Bool = false, height: CGFloat = JPHeight.field, @ViewBuilder content: () -> Content) {
        self.title = title
        self.multiline = multiline
        self.height = height
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JPFieldTitle(title)
            content
                .font(.subheadline)
                .accessibilityLabel(title)
                .jpFieldBox(multiline: multiline, height: height)
        }
    }
}

extension View {
    /// 入力欄の枠（`JPField` の中身と同じ形: 地 白 6%・縁・角 12・高さ 48）。
    /// **欄の名前の見出しを別に置く画面**（投稿の「撮影地」は候補の行が欄の下に続く）でも同じ枠を使う
    /// （2026-10-21・撮影地の欄だけ枠が無く、押せる欄に見えなかった・全画面の点検 run 609）
    func jpFieldBox(multiline: Bool = false, height: CGFloat = JPHeight.field) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, multiline ? 12 : 0)
            .frame(maxWidth: .infinity, minHeight: multiline ? 88 : height,
                   alignment: multiline ? .topLeading : .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.outline, lineWidth: 1))
    }
}

/// `jpForm()` の行の決まり（テストで見張る）
enum JPFormLayout {
    /// 行の左右の余白＝画面の端（板 16）。**0 にしない**——0 だと欄が節の端に付き、節の角で欠ける（2026-11-25）
    static let sideInset: CGFloat = JPSpace.gutter
    /// 行の上下の余白
    static let rowGap: CGFloat = 8
}

/// 入力欄の見本の字（placeholder）。**白 50%（`WebTheme.placeholder`）**——入力欄の地 #161617 の上で 5.24:1。
///
/// 2026-11-14 判断（点検「画面と手ざわり」・直すべき）: `WebTheme.placeholder` は定義してあったのに、
/// どの入力欄も使っておらず、iOS の既定の見本の色（暗い画面で 235,235,245 の 30%）のまま 2.2〜2.5:1 しか無かった
/// （「コメントを書く」「メッセージ」「返信する」「写真を検索…」など）。字の線 4.5:1 に届かず、暗い所では
/// 何も書いていない黒い枠に見える。板のデザインシステム 01「placeholder 白 50%（35% は 3.0 で届かない）」。
/// **入力欄はここの `JPTextField`・`JPSecureField` だけで作る**（`TextField(` を直に書かない・`InputPlaceholderTests` が見張る）
@MainActor
enum JPInputPrompt {
    static let color = WebTheme.placeholder
    static func text(_ title: String) -> Text { Text(title).foregroundStyle(color) }
}

/// 1行・複数行の入力欄（見本の字は `JPInputPrompt`）。`TextField(title, text:, axis:)` と同じ形で置き換えられる。
/// 修飾子（`.focused`・`.onSubmit`・`.lineLimit`・`.accessibilityIdentifier` など）は中の `TextField` に効く
/// （`body` が欄1つだけの透けた部品）
struct JPTextField: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal

    init(_ title: String, text: Binding<String>, axis: Axis = .horizontal) {
        self.title = title
        self._text = text
        self.axis = axis
    }

    var body: some View {
        TextField(title, text: $text, prompt: JPInputPrompt.text(title), axis: axis)
    }
}

/// パスワードの欄（見本の字は `JPInputPrompt`）
struct JPSecureField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        SecureField(title, text: $text, prompt: JPInputPrompt.text(title))
    }
}

/// 欄の名前（`JPField` の見出しと同じ字・色）。見出しと欄を別々に置く画面が使う
struct JPFieldTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(WebTheme.muted2)
            // 読み上げは欄の名前で言う（見出しと二重に読まない）
            .accessibilityHidden(true)
    }
}

/// 幅いっぱいのカプセル（板の確定ボタン）。
///
/// **v2（2026-10-14・Components 01「高さは 50（主）と 44（副）の2種類だけ」）**:
/// 塗りのボタン（白・真鍮・赤）は 50・`.callout`（既定 16pt）semibold、
/// 線のボタン（`.outline`）は 44・15pt semibold・白 14% の縁。以前は全部 52 で、縁は白 28%。
///
/// **`webPrimaryButton` は変えない。** そちらは約44pt で、プロフィールの
/// フォローなど行の中のボタンが使っている
enum JPPillStyle: Equatable {
    /// 白 94% に墨の字（1画面に1つ）
    case primary
    /// 枠線（白 14%）に白の字（「アカウントを作る」など2番手）。高さ 44
    case outline
    /// 赤の塗りに白の字（アカウントの削除だけ）
    case danger
    /// 真鍮の塗りに墨の字（**写真の無い画面の主ボタン1つ**・デザインシステム「黒塗りの真鍮」
    /// の accent-fill #B8955A・墨で 7.11:1）。写真のある画面は `.primary`（白）
    case accent

    /// **主ボタンの色はこれで決める**（CLAUDE.md の owner の好み・v2 の板より優先）:
    /// 写真のある画面は白（ログインなど・写真の上で読める色は白だけ）、写真の無い画面は真鍮の塗り＋墨。
    /// v2 の板は「写真のある画面も真鍮」の案だったが、owner の決まりを取った（2026-10-14）
    static func main(onPhoto: Bool) -> JPPillStyle {
        onPhoto ? .primary : .accent
    }

    /// 高さ。塗りは 50、線は 44（`JPHeight`）
    var height: CGFloat {
        self == .outline ? JPHeight.secondaryButton : JPHeight.primaryButton
    }

    /// 縁の白の濃さ。線のボタンだけ v2 の line（白 14%）
    var borderOpacity: Double {
        self == .outline ? 0.14 : 0
    }

    @MainActor var fill: Color {
        switch self {
        case .primary: return WebTheme.accentBackground
        case .outline: return Color.clear
        case .danger: return WebTheme.dangerFill
        case .accent: return WebTheme.accentFill
        }
    }
}

/// 線の小ボタンの大きさ（板 Components 01）
enum JPOutlineSize: Equatable {
    /// 副ボタン: 44・15pt semibold（板 `.bo`）
    case regular
    /// 行の中の小ボタン: 見た目 36・13pt semibold・当たり 44（板「行の中の小ボタン」・プロフィールを編集）
    case inline
    /// 削除の確かめの札の2つのボタン（「削除する」と「キャンセル」）: 50・17pt semibold・字は折り返す。
    ///
    /// 2026-11-21 判断（owner「確認バナーはもう少し大きめに表示していいかも？」・札 #679）: 板の札の中の
    /// 確かめは副ボタン 44・15pt だったが、消す前の最後の問いなので主ボタンと同じ 50 にし、字は板の
    /// 系統の確認（Components「確認」・17pt）にそろえた。大きな文字では1行に切らず折り返す
    case confirm

    var height: CGFloat {
        switch self {
        case .regular: return JPHeight.secondaryButton
        case .inline: return JPHeight.inlineButton
        case .confirm: return JPHeight.primaryButton
        }
    }

    /// 字を1行で切らずに折り返すか（確かめの札だけ・大きな文字で「キャンセル」が切れない）
    var wraps: Bool { self == .confirm }

    /// 見た目の高さから 44 の当たりまでの上下の余白（片側）
    var tapSlack: CGFloat {
        max(0, (WebTheme.minTapTarget - height) * 0.5)
    }

    @MainActor var font: Font {
        switch self {
        case .regular: return JPFont.bodyEmphasis
        case .inline: return JPFont.footnote.weight(.semibold)
        case .confirm: return JPFont.confirmButton
        }
    }
}

/// 線の小ボタンの色合い（板 Components 01: 線は白 14%）
///
/// **消す操作は赤の塗りに白の太字（2026-11-21 判断・owner「一般的な削除するの色にしたい」「水平展開お願い」・札 #679）。**
/// 前は危険の線（赤の字・赤 40% の線）と、確かめの「削除する」（白の字・赤 16% の地・赤 50% の線）の2つに割れていて、
/// どちらも iOS のふつうの「削除」（赤い面に白い字）に見えなかった。塗りは板の `dangerFill`（#C8323A・白で 5.29:1）——
/// 板では「アカウント削除の確定だけ」の色だったのを、自前の消すボタン全部に広げた。危険の字の色 `danger`（#F0565A）の
/// 塗りは白で 3.39:1 しかなく、15pt の副ボタンの字（大きな字ではない）では 4.5:1 に届かないので使わない。
/// 系統の部品（確認のダイアログ・メニュー・スワイプ）は今のまま赤の字（`DestructiveButtonFillTests` が見張る）
enum JPOutlineTone: Equatable {
    /// 白の字・白 14% の線（`WebTheme.line`）
    case plain
    /// 消す操作（端末から削除・会話を削除・確かめの「削除する」）: 赤の塗り（`dangerFill`）に白の字・縁なし
    case danger

    @MainActor var text: Color {
        WebTheme.foreground
    }

    @MainActor var fill: Color {
        self == .danger ? WebTheme.dangerFill : Color.clear
    }

    @MainActor var border: Color {
        self == .danger ? Color.clear : WebTheme.line
    }
}

extension View {

    /// JPField を並べる `Form` の形（`jpFormRow` と組で使う）。**角の丸い札の形（insetGrouped）にしない。**
    ///
    /// 2026-11-25 判断（owner の実機の画面写真・パスワードを変える）: `Form` の既定は角の丸い札の形で、
    /// 節の最初の行の上の角と、最後の行の下の角を、**地を透かしていても丸く切り抜く**。
    /// 行の左右の余白を 0 にして欄を節の端まで出していたので、節の最初の欄の名前の頭
    /// （「いまのパスワード」の「い」の左の画）と、節の最後の欄の下の縁の両端が角で欠けていた。
    /// 角の無い形（grouped）にして、左右の端 16 は行の余白で取る（`JPFormLayout.sideInset`）。
    ///
    /// **一覧の左右の余白は 0 にする。** grouped でも一覧は端末の余白（大きい iPhone で 20）を左右に取り、
    /// 行の余白 16 と足して欄が端から 36 に寄った（Mac run 1802・440 幅で欄の字の左が 50 ＝ 20＋16＋欄の内側 14）
    func jpForm() -> some View {
        self
            .listStyle(.grouped)
            .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    /// `Form` の行に JPField を置くときの行の作法（板は左右 16・区切り線なし）。
    /// 左右の端は `JPFormLayout.sideInset`（画面の端 16）——`jpForm()` の角の無い形は節が画面の幅いっぱいなので、
    /// 行の余白で端を取る。**区切り線も消す**（`listRowBackground(.clear)` では消えない。節の上下の線も）
    func jpFormRow(top: CGFloat = JPFormLayout.rowGap, bottom: CGFloat = JPFormLayout.rowGap) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: JPFormLayout.sideInset,
                                      bottom: bottom, trailing: JPFormLayout.sideInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
    }

    /// - Parameter height: 高さを揃えたいときだけ渡す。**同じ場所で主ボタンと線のボタンが
    ///   入れ替わる**所（読み込み中に「やめる」へ替わる帯）は `JPHeight.primaryButton` を渡し、
    ///   入れ替わりで帯が 6pt 跳ねないようにする
    func jpPillButton(_ style: JPPillStyle = .primary, height: CGFloat? = nil) -> some View {
        self
            .jpCapsuleFace(font: style == .outline ? JPOutlineSize.regular.font : .callout.weight(.semibold),
                           text: style == .primary || style == .accent ? WebTheme.accentText : Color.white,
                           fill: style.fill,
                           border: Color.white.opacity(style.borderOpacity),
                           fullWidth: true,
                           minHeight: height ?? style.height,
                           textInset: nil)
            .contentShape(Capsule())
    }

    /// **線の小ボタン**（板 Components 01 の `.bo`・「行の中の小ボタン」・危険の線）。幅は中身に合わせる
    /// （`fullWidth` で札の幅いっぱい）。字は1行・左右 16 の内側。
    ///
    /// 旅（`TripOutlineButton`）・人のページ（`ProfileOutlinePill`）がそれぞれ同じ形を書いていたのを、
    /// `jpPillButton(.outline)` と同じ面（`jpCapsuleFace`）に寄せた（2026-10-14 判断）。
    /// `.inline` は見た目 36・**当たりは 44**（上下に余白を足して四角で押せるようにする）
    @ViewBuilder
    func jpOutlineButton(_ size: JPOutlineSize = .regular, tone: JPOutlineTone = .plain,
                         fullWidth: Bool = false) -> some View {
        let face = self.jpCapsuleFace(font: size.font, text: tone.text, fill: tone.fill, border: tone.border,
                                      fullWidth: fullWidth, minHeight: size.height, textInset: JPSpace.m,
                                      wraps: size.wraps)
        switch size {
        case .regular, .confirm:
            face.contentShape(Capsule())
        case .inline:
            face
                .padding(.vertical, size.tapSlack)
                .contentShape(Rectangle())
        }
    }

    /// 丸いボタンの面（字・地・縁・高さ）。**丸いボタンの値はここ1つを通る**——幅いっぱいのカプセル
    /// （`jpPillButton`）も線の小ボタン（`jpOutlineButton`）も同じ並びで組む（2026-10-14 判断）。
    ///
    /// - Parameter textInset: 字の左右の内側。nil なら内側なし・行も切らない（幅いっぱいのカプセルの元の形）。
    ///   値があれば字は1行（`wraps` のときだけ折り返して、上下にも内側を取る）
    func jpCapsuleFace(font: Font, text: Color, fill: Color, border: Color,
                         fullWidth: Bool, minHeight: CGFloat, textInset: CGFloat?,
                         wraps: Bool = false) -> some View {
        self
            .font(font)
            .foregroundStyle(text)
            .lineLimit(textInset == nil || wraps ? nil : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: wraps)
            .padding(.horizontal, textInset ?? 0)
            .padding(.vertical, wraps ? JPSpace.xs : 0)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: JPStroke.hairline))
    }

    /// 下に固定する帯（板: 黒55%＋ぼかし＋上に白8% の線・余白 12/16/下）。
    /// `safeAreaInset(edge: .bottom)` の中身に付ける。下の余白は安全域の上に
    /// 足す分（板の 34 は家のバーの分なので、ここでは入れない）
    func jpBottomBar() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            // 家のバーの下まで同じ色に（ぼかしも黒も安全域へ伸ばす）
            .background(Color.black.opacity(0.55), ignoresSafeAreaEdges: .bottom)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
    }
}

// MARK: - 札と行（板 43 設定・47 通報）

/// 行を束ねる札（板: 角丸16・縁 白8%）。行の間の線は `JPCardDivider`。
///
/// **v2（2026-10-14）: 地を白 7%（≒#121212）から surface-1 の #0E0E0F に沈めた**（`WebTheme.card`）。
///
/// - **黒地の画面の上だけ既定の地。** シート（#161617）の上では沈んで札に見えないので、
///   `fill: WebTheme.surface`（白 7%・シートの上で一段明るい）を渡す（通報のシート）
/// - 同じ画面に白 7% の札（`WebTheme.surface` を直に塗った所）がまだ残っている。次の段でそろえる
struct JPCard<Content: View>: View {

    /// 地。無ければ `WebTheme.card`
    var fill: Color?
    let content: Content

    init(fill: Color? = nil, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .jpCardFace(fill: fill)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
    }
}

extension View {

    /// **札の地**（板 Components の `.card`: surface-1・白 8% の縁・角 16）。`JPCard` と同じ値。
    ///
    /// 札を `VStack` で組めない所（旅行プラン・電波なしの札・今日のテーマ・ホームの上の札・バッジの棚・
    /// 撮影スポットの数え札など）が「面＋縁＋角 16」を画面ごとに直に書いていた。ここ1つに寄せる
    /// （2026-10-14 判断）。切り抜き（`clipShape`）・押せる形は札ごとに違うので呼ぶ側が足す。
    ///
    /// - Parameter fill: 地。無ければ `WebTheme.card`。シートの上・黒地に溶かす札は地だけ替える
    func jpCardFace(fill: Color? = nil) -> some View {
        self
            .background(fill ?? WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }
}

/// **削除の確かめの札**（画面の中に開く「〜を削除しますか？」と「キャンセル｜削除する」）。
/// 旅行プランの日の削除・プランの削除・端末から削除の3か所が、ここ1つを通る（画面ごとに割らない・CLAUDE.md）。
///
/// 2026-11-21 判断（owner「削除する。キャンセルする。の確認バナーはもう少し大きめに」「一般的な削除するの色にしたい」・札 #679）:
/// - 問いは 17pt semibold の白（板 Components「確認」の題と同じ。前は 13pt の灰色で、何を聞かれているか目に入りにくかった）
/// - ボタンは 50・17pt semibold（`JPOutlineSize.confirm`）。「削除する」は赤の塗りに白の字（`JPOutlineTone.danger`）、
///   キャンセルは白 14% の線に白の字
/// - 並びは iOS の確認と板の系統の確認と同じ「キャンセル｜削除する」（消す側が右）。横に入らない大きな文字では縦に積み、
///   消す側を上に置く（系統の確認の縦の並びと同じ）
/// - 札の内側は 20（前は 16・`carded` のとき）
struct JPDeleteConfirm: View {
    let question: String
    /// 問いの下の補足（消えるものの大きさなど）
    var detail: String?
    let confirmTitle: String
    /// 自前の札の面（地と縁）を付けるか。もう札の中にある所（電波なしで使う札）は false
    var carded = true
    /// 送っている間は押せない（二度押しを受けない）
    var busy = false
    var identifier: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let content = VStack(alignment: .leading, spacing: JPSpace.s) {
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                Text(question)
                    .font(JPFont.headline)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail)
                        .font(JPFont.body)
                        .lineSpacing(3)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // アクセシビリティの大きさではいつも縦に積む（Mac の run 1673 の AX XL の絵で、横に並べた「キャンセル」が
            // 「キャンセ／ル」と2行に割れていた。ViewThatFits だけでは並びの幅を広く見積もる画面がある）
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    sideBySide
                    stacked
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if carded {
            content
                .padding(JPSpace.l)
                .jpCardFace()
        } else {
            content
        }
    }

    private var sideBySide: some View {
        HStack(spacing: JPSpace.xs) {
            cancelButton
            confirmButton
        }
    }

    private var stacked: some View {
        VStack(spacing: JPSpace.xs) {
            confirmButton
            cancelButton
        }
    }

    private var confirmButton: some View {
        Button(action: onConfirm) {
            Text(confirmTitle).jpOutlineButton(.confirm, tone: .danger, fullWidth: true)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .accessibilityIdentifier(identifier.map { "\($0).confirm" } ?? "delete.confirm")
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text(Labels.Common.cancel).jpOutlineButton(.confirm, tone: .plain, fullWidth: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier.map { "\($0).cancel" } ?? "delete.cancel")
    }
}

/// 札の中の行と行の間の線（板: 白8%・1pt）
struct JPCardDivider: View {
    var body: some View {
        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
    }
}

/// 札の上の小さい見出し（板: 12px・medium・白60%）
struct JPSectionTitle: View {

    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(WebTheme.faint)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 1つだけ選ぶ行（板 47 の理由: 最小54pt・右に 22pt の丸、選ぶと白い輪と点）。
///
/// **iOS 既定のチェックマークにしない**（板は丸）。読み上げは「選択中」で言う
struct JPRadioRow: View {

    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(selected ? 1 : 0.35), lineWidth: selected ? 2 : 1.5)
                    if selected {
                        Circle().fill(Color.white).frame(width: 10, height: 10)
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 説明付きの入切の行（板: 15px の名前の下に 11px・白60% の説明、軌道は暗い真鍮）
struct JPToggleRow: View {

    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // **軌道は暗い真鍮。** 既定の tint（白）だと、入れたときに白い軌道に
        // 白いつまみが乗り、入か切かが見えない
        .tint(WebTheme.accentDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
    }
}

/// 札の中の1行の見た目（板 43: 最小54pt・左に白72% のアイコン・15px の名前・
/// 11px の説明・右に値（等幅）と矢印）。押す口は呼ぶ側（NavigationLink・Link・
/// Button）が包む——包むときは `.buttonStyle(JPRowButtonStyle())`
struct JPRowLabel: View {

    let title: String
    var systemImage: String?
    var detail: String?
    /// 右に出す値（控えの大きさなど）。等幅
    var value: String?
    /// 矢印。行き先がある行に出す（押すとその場で効く行には出さない）。
    /// 例外はアカウントの削除——板は行き先があっても矢印を出さない
    var chevron = true
    /// 危ない行（アカウントの削除）はアイコンだけ赤（板どおり、名前は白のまま）
    var iconColor: Color = WebTheme.muted2
    /// SF Symbols に無い絵（設定の Pro の行の Pro マーク・線の絵・板 43）。あれば `systemImage` より先に使う
    var icon: AnyView?
    /// 右の件数バッジ（真鍮・`CountBadge`）。無ければ出さない（マイページの旅のトランクの行・2026-11-23 札 #709）
    var badge: Int?
    /// 右の小さな絵（矢印の手前・旅のスタンプ帳の最近の3つ・2026-11-23 札 #712）。無ければ出さない
    var accessory: AnyView?

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                icon
                    .frame(width: 24)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(1)
            }
            if let badge {
                CountBadge(count: badge, maximum: 99)
            }
            if let accessory { accessory }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

/// 札の中の行を押したときの手応え（押している間だけ行の地を白6%に）。
///
/// **`.plain` では足りない。** List の行は押すと灰色になったが、`.plain` は字が
/// 少し薄くなるだけで、押せる行と表示だけの行の見分けがつかなかった
struct JPRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
    }
}


/// 写真選び（`PhotosPicker`）の見出しに置く丸いボタンの字（2026-11-25 判断・Swift 6）。
/// Xcode 27 の `PhotosPicker` は見出しの閉包をメインアクタの外で作るので、そこでは画面の部品の修飾
/// （`jpPillButton`・メインアクタ）を呼べない。見た目は `Label(...).jpPillButton(style)` と同じで、組むのを body（メインアクタ）に移しただけ
struct JPPillPickerLabel: View {
    let title: String
    let systemImage: String
    var style: JPPillStyle = .primary

    var body: some View {
        Label(title, systemImage: systemImage)
            .jpPillButton(style)
    }
}
