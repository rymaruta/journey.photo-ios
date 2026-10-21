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
    let content: Content

    init(_ title: String, multiline: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.multiline = multiline
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JPFieldTitle(title)
            content
                .font(.subheadline)
                .accessibilityLabel(title)
                .jpFieldBox(multiline: multiline)
        }
    }
}

extension View {
    /// 入力欄の枠（`JPField` の中身と同じ形: 地 白 6%・縁・角 12・高さ 48）。
    /// **欄の名前の見出しを別に置く画面**（投稿の「撮影地」は候補の行が欄の下に続く）でも同じ枠を使う
    /// （2026-10-21・撮影地の欄だけ枠が無く、押せる欄に見えなかった・全画面の点検 run 609）
    func jpFieldBox(multiline: Bool = false) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, multiline ? 12 : 0)
            .frame(maxWidth: .infinity, minHeight: multiline ? 88 : 48,
                   alignment: multiline ? .topLeading : .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.outline, lineWidth: 1))
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

    var height: CGFloat {
        self == .regular ? JPHeight.secondaryButton : JPHeight.inlineButton
    }

    /// 見た目の高さから 44 の当たりまでの上下の余白（片側）
    var tapSlack: CGFloat {
        max(0, (WebTheme.minTapTarget - height) * 0.5)
    }

    @MainActor var font: Font {
        self == .regular ? JPFont.bodyEmphasis : JPFont.footnote.weight(.semibold)
    }
}

/// 線の小ボタンの色合い（板 Components 01: 線は白 14%・危険は #F0565A の字と 40% の縁）
enum JPOutlineTone: Equatable {
    /// 白の字・白 14% の線（`WebTheme.line`）
    case plain
    /// 赤の字・赤 40% の線（端末から削除）
    case danger
    /// 削除の確かめの「削除する」: 白の字・赤 16% の地・赤 50% の線
    case strong

    /// 危険の線の赤の濃さ（板 40%）と、確かめの「削除する」の地（16%）・線（50%）
    nonisolated static let dangerLineOpacity = 0.4
    nonisolated static let strongFillOpacity = 0.16
    nonisolated static let strongLineOpacity = 0.5

    @MainActor var text: Color {
        self == .danger ? WebTheme.danger : WebTheme.foreground
    }

    @MainActor var fill: Color {
        self == .strong ? WebTheme.danger.opacity(Self.strongFillOpacity) : Color.clear
    }

    @MainActor var border: Color {
        switch self {
        case .plain: return WebTheme.line
        case .danger: return WebTheme.danger.opacity(Self.dangerLineOpacity)
        case .strong: return WebTheme.danger.opacity(Self.strongLineOpacity)
        }
    }
}

extension View {

    /// `Form` の行に JPField を置くときの行の作法（板は左右 16・区切り線なし）。
    /// **行の内側の余白を消す**——消さないと、同じ画面の札より欄が左右 20pt 狭く、
    /// 端が揃わない。**区切り線も消す**（`listRowBackground(.clear)` では消えない）
    func jpFormRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
                                      fullWidth: fullWidth, minHeight: size.height, textInset: JPSpace.m)
        switch size {
        case .regular:
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
    ///   値があれば字は1行
    func jpCapsuleFace(font: Font, text: Color, fill: Color, border: Color,
                         fullWidth: Bool, minHeight: CGFloat, textInset: CGFloat?) -> some View {
        self
            .font(font)
            .foregroundStyle(text)
            .lineLimit(textInset == nil ? nil : 1)
            .padding(.horizontal, textInset ?? 0)
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
