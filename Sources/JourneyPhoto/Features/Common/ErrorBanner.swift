import SwiftUI

/// エラーを出す共通の見た目。**技術的な文言をそのまま出さない**。
///
/// **v2（2026-10-14・Components 06「4つの状態」）**: どの画面でも同じ並び——
/// 何が起きたか（明朝 20 の見出し・任意）→ どうなっているか（15 の text-2）→ 押せる一手（「もう一度」）。
/// 三角の印は残す（2026-10-14 判断: 見出しの無い呼び方が多く、印が無いと空の状態と見分けがつかない）。
/// 印は text-3 の灰——赤（`danger`）にしない。読めないのは人の誤りではない
struct ErrorBanner: View {
    var title: String?
    let message: String
    var retry: (() -> Void)?
    /// 読み直している最中（「もう一度試す」を止める。続けて押すと古い答えが新しい答えを上書きする）
    var isBusy = false

    init(title: String? = nil, message: String, isBusy: Bool = false, retry: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.isBusy = isBusy
        self.retry = retry
    }

    var body: some View {
        StateLayout {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(WebTheme.faint)
                .accessibilityHidden(true)
            if let title { StateTitle(text: title) }
            StateMessage(text: message)
            if let retry {
                RetryButton(isBusy: isBusy, action: retry)
                    .padding(.top, JPSpace.xs)
            }
        }
    }
}

/// **空の状態**（「まだありません」）の見た目。`ErrorBanner` と同じ置き方・同じ文字色で、
/// **警告の三角を出さない**——0件は失敗ではない（2026-10-02 の調査: 「まだありません」にも
/// 三角が出ていて、何か壊れたように読めた）。読めなかった回は `ErrorBanner` を使う。
///
/// **v2（2026-10-14）**: 何が無いか（明朝 20 の見出し・任意）→ どうすれば埋まるか（15 の text-2）→
/// 押せる一手（任意）。一手は**写真の無い画面の主ボタン＝真鍮の塗り＋墨**（`JPPillStyle.main(onPhoto: false)`・
/// CLAUDE.md の owner の好み。v2 の板は白の案）
struct EmptyState: View {
    var title: String?
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// 一手のボタンの道しるべ（UI テストが名指しで探す。ホームの `home.emptyAction`）。
    /// 2026-10-14 判断: 画面ごとに空の状態を書き直さず、この部品に名前だけ渡せるようにした
    var actionIdentifier: String?

    init(title: String? = nil, message: String, actionTitle: String? = nil,
         actionIdentifier: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionIdentifier = actionIdentifier
        self.action = action
    }

    var body: some View {
        StateLayout {
            if let title { StateTitle(text: title) }
            StateMessage(text: message)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(actionIdentifier ?? "")
                .padding(.top, JPSpace.xs)
            }
        }
    }
}

/// 状態の表示の並べ方（中央・間 12・外の余白 24）。`EmptyState`・`ErrorBanner` が同じ形で出す
private struct StateLayout<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: JPSpace.s) { content }
            .padding(JPSpace.xl)
            .frame(maxWidth: .infinity)
    }
}

/// 状態の見出し（明朝 20・白・2 行まで）
private struct StateTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(JPFont.stateTitle)
            .foregroundStyle(WebTheme.text)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 状態の説明（本文 15・text-2・切り詰めず折り返す）
private struct StateMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(JPFont.body)
            .foregroundStyle(WebTheme.muted2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 「もう一度試す」。**押せる所は 44pt**。
///
/// **v2（2026-10-14・Components 01 の副ボタン）**: 見た目も 44・透明の地に白 14% の線・15pt semibold。
/// `compact`（行の中・地図の札の中）は見た目 30 の白 12% の札のまま、当たりだけ 44。
///
/// `.buttonStyle(.bordered)` の外に `frame(minHeight: 44)` を付けても当たりは広がらない
/// （ボタンの外の余白は押せない・2026-10-02 のレビュー）。ラベルの中で広げる
/// （`webTappable` と同じ考え）。**読み直している間は押せない**（`isBusy`）
struct RetryButton: View {
    var isBusy = false
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                // 見た目の札の外まで当たりを広げる（見た目は変えない）
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.4 : 1)
    }

    @ViewBuilder
    private var label: some View {
        if compact {
            Text(Labels.Common.retry)
                .font(Font.caption.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, JPSpace.s)
                .frame(minHeight: 30)
                .background(Color.white.opacity(0.12), in: Capsule())
        } else {
            Text(Labels.Common.retry)
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, JPSpace.l)
                .frame(minHeight: JPHeight.secondaryButton)
                .overlay(Capsule().strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
        }
    }
}

/// **読み込み中**（v2 Components 06 の LOADING）。中身と同じ形の灰色の骨格を置く。
///
/// - **0.3 秒より早く読めたら骨格は出さない**（ちらつかせない・板の決まり）
/// - 光の流れ（きらめき）は付けない——「視差効果を減らす」の人に止める手間が要らない、灰色のまま
/// - 読み上げは「読み込み中」1つ（骨格の一つずつを読ませない）
///
/// `kind`——`grid`: 写真の格子（3 列・すき間 2）＋2 行の字。`rows`: 字の行だけ（一覧・札）
struct JPLoadingState: View {
    enum Kind { case grid, rows }

    var kind: Kind = .grid

    /// 骨格を出すまで待つ時間
    nonisolated static let revealDelay: Duration = .milliseconds(300)
    /// 骨格の灰（板の `#121213 → #1C1C1E`。光は流さないので中の値1つ）
    nonisolated static let boneGray: UInt32 = 0x1C1C1E

    @State private var revealed = false

    var body: some View {
        Group {
            if revealed {
                skeleton
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("読み込み中", "Loading"))
        .task {
            try? await Task.sleep(for: Self.revealDelay)
            revealed = true
        }
    }

    @ViewBuilder
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if kind == .grid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle().fill(bone).aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                bar(widthRatio: 0.7, height: 14)
                bar(widthRatio: 0.45, height: 12)
            }
            .padding(.horizontal, kind == .grid ? JPSpace.gutter : 0)
        }
        .padding(.vertical, JPSpace.m)
    }

    private var bone: Color {
        Color(red: Double((Self.boneGray >> 16) & 0xFF) / 255,
              green: Double((Self.boneGray >> 8) & 0xFF) / 255,
              blue: Double(Self.boneGray & 0xFF) / 255)
    }

    private func bar(widthRatio: CGFloat, height: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: JPRadius.xs)
                .fill(bone)
                .frame(width: proxy.size.width * widthRatio, height: height)
        }
        .frame(height: height)
    }
}
