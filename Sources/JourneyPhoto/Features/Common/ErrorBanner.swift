import SwiftUI

/// エラーを出す共通の見た目。**技術的な文言をそのまま出さない**。
///
/// **v2（2026-10-14・Components 06「4つの状態」）**: どの画面でも同じ並び——
/// 何が起きたか（明朝 20 の見出し）→ どうなっているか（15 の text-2）→ 押せる一手（「もう一度」）。
///
/// **2026-11-12 判断（デザインの案 第2章「画面の状態とそろえ」・1.1.83）**: 印は三角をやめ、
/// **丸に「!」の線画 44・#6E6E6E**（`JPStateIcon.failed`）。見出しは**必ず出す**——呼ぶ所40のうち10しか
/// 見出しを渡しておらず、画面ごとに形が違った。渡さない呼び手は「読み込めませんでした」を見出しにし、
/// 説明が見出しと同じ言葉なら、どうなっているかの決まった一文に替える（`resolvedText`）。
/// 印は赤（`danger`）にしない。読めないのは人の誤りではない
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

    /// 見出しを渡さない回の説明（見出しと同じ言葉を2度並べない）
    static var defaultMessage: String {
        L("通信が途切れたようです。電波の届く所でもう一度お試しください",
          "The connection seems to have dropped. Try again where you have a signal.")
    }

    /// 出す見出しと説明。**見出しは必ずある**（2026-11-12 判断）
    nonisolated static func resolvedText(title: String?, message: String,
                                         fallbackTitle: String, fallbackMessage: String) -> (title: String, message: String) {
        let shownTitle = title ?? fallbackTitle
        let shownMessage = message == shownTitle ? fallbackMessage : message
        return (shownTitle, shownMessage)
    }

    var body: some View {
        let text = Self.resolvedText(title: title, message: message,
                                     fallbackTitle: Labels.Common.loadFailed, fallbackMessage: Self.defaultMessage)
        StateLayout {
            JPStateIcon(symbol: JPStateIcon.failed)
            StateTitle(text: text.title)
            StateMessage(text: text.message)
            if let retry {
                RetryButton(isBusy: isBusy, action: retry)
                    .padding(.top, JPSpace.xs)
            }
        }
    }
}

/// 状態の印（線画・44・#6E6E6E）。**形だけで伝える**——色で失敗・空を分けない（2026-11-12 判断・第2章）。
/// 失敗は丸に「!」、空は線画の写真（画面ごとに人・ベル・ピン・アルバム・ハートに替えてよい）、電波なしは消えた電波
struct JPStateIcon: View {
    let symbol: String

    /// 印の箱の大きさ（板の 44）
    nonisolated static let size: CGFloat = 44
    /// 印の灰（板の #6E6E6E。飾りなので読み上げから外し、字の 4.5:1 は要らない）
    nonisolated static let gray: UInt32 = 0x6E6E6E
    /// 失敗（丸に「!」）
    nonisolated static let failed = "exclamationmark.circle"
    /// 空の既定（線画の写真）
    nonisolated static let empty = "photo"
    /// 電波なし（消えた電波）
    nonisolated static let offline = "wifi.slash"

    var body: some View {
        Image(systemName: symbol)
            // 線画に寄せる（板は線 0.65/24 ≒ 1.2pt）。ultraLight の印を箱 44 に収める
            .font(.system(size: 36, weight: .ultraLight))
            .frame(width: Self.size, height: Self.size)
            .foregroundStyle(Self.color)
            .accessibilityHidden(true)
    }

    static var color: Color {
        Color(red: Double((gray >> 16) & 0xFF) / 255, green: Double((gray >> 8) & 0xFF) / 255,
              blue: Double(gray & 0xFF) / 255)
    }
}

/// **空の状態**（「まだありません」）の見た目。`ErrorBanner` と同じ置き方・同じ文字色で、
/// **警告の三角を出さない**——0件は失敗ではない（2026-10-02 の調査: 「まだありません」にも
/// 三角が出ていて、何か壊れたように読めた）。読めなかった回は `ErrorBanner` を使う。
///
/// **v2（2026-10-14）**: 何が無いか（明朝 20 の見出し・任意）→ どうすれば埋まるか（15 の text-2）→
/// 押せる一手（任意）。一手は**写真の無い画面の主ボタン＝真鍮の塗り＋墨**（`JPPillStyle.main(onPhoto: false)`・
/// CLAUDE.md の owner の好み。v2 の板は白の案）
///
/// **2026-11-12 判断（第2章）**: 先頭に線画の印（`JPStateIcon`・既定は写真）を置く。今は印が無く、
/// 字だけの空が失敗や途中の画面に見えた。画面に合う印は `icon` で渡す（人・ベル・ピンなど）。
/// 狭い段の中で印を置かない所だけ `icon: nil`
struct EmptyState: View {
    var icon: String?
    var title: String?
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// 一手のボタンの道しるべ（UI テストが名指しで探す。ホームの `home.emptyAction`）。
    /// 2026-10-14 判断: 画面ごとに空の状態を書き直さず、この部品に名前だけ渡せるようにした
    var actionIdentifier: String?

    init(icon: String? = JPStateIcon.empty, title: String? = nil, message: String, actionTitle: String? = nil,
         actionIdentifier: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionIdentifier = actionIdentifier
        self.action = action
    }

    var body: some View {
        StateLayout {
            if let icon { JPStateIcon(symbol: icon) }
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

/// **状態の帯**（2026-11-12 判断・デザインの案 第2章「画面の状態とそろえ」の5つ目の部品）。
///
/// 画面全体が読めないときは中央の状態（`ErrorBanner`・`EmptyState`）、**一部だけ読めない・電波が無いときは
/// 上に帯を出して画面は閉じない**（板 v2 Main の「電波なし」）。並びは どの画面も同じ——
/// 印 20 → 見出し（15 semibold）と説明（12 の text-3）→ 右に白い小ボタン「もう一度」（見た目 36・当たり 44）。
///
/// 皮は2つ: 黒地の上は札（`card`・surface-1・角 16・白 8% の縁）、地図や写真の上はガラス（`glass`・角 22）
struct JPStateBand: View {
    enum Kind: Equatable {
        /// 電波が届いていない（消えた電波の印）
        case offline
        /// 一部だけ読めなかった・節が読めなかった（丸に「!」）
        case partial
        /// 空（画面に合う印を渡す。地図の「この範囲にはまだ写真がありません」など）
        case empty(symbol: String)

        var symbol: String {
            switch self {
            case .offline: return JPStateIcon.offline
            case .partial: return JPStateIcon.failed
            case .empty(let symbol): return symbol
            }
        }
    }

    enum Skin: Equatable { case card, glass }

    let kind: Kind
    let title: String
    var message: String?
    var skin: Skin = .card
    /// 右の小ボタンの字（既定は「もう一度」）
    var actionTitle: String?
    var isBusy = false
    var actionIdentifier: String?
    var action: (() -> Void)?

    /// 札の角（板の 16）・ガラスの角（22）
    nonisolated static let cardCorner: CGFloat = 16
    nonisolated static let glassCorner: CGFloat = 22

    /// 電波が無いときの見出し（どの画面も同じ言葉）
    static var offlineTitle: String { L("電波が届いていません", "No connection") }
    /// 右の小ボタンの既定の字
    static var retryTitle: String { L("もう一度", "Retry") }

    var body: some View {
        HStack(spacing: JPSpace.s) {
            Image(systemName: kind.symbol)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 20, height: 20)
                .foregroundStyle(skin == .glass ? WebTheme.foreground : WebTheme.text2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(JPFont.caption)
                        // ガラスの上は透過の白（地図が透けるので不透明の灰にしない）
                        .foregroundStyle(skin == .glass ? WebTheme.muted2 : WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let action {
                Button(action: action) {
                    Text(actionTitle ?? Self.retryTitle)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .lineLimit(1)
                        .padding(.horizontal, JPSpace.m)
                        .frame(minHeight: JPHeight.inlineButton)
                        .background(Color.white.opacity(0.94), in: Capsule())
                        // 見た目は 36、当たりは 44（ラベルの中で広げる）
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .opacity(isBusy ? 0.4 : 1)
                .accessibilityIdentifier(actionIdentifier ?? "")
                .fixedSize()
            }
        }
        .padding(.leading, JPSpace.m)
        .padding(.trailing, 14)
        .padding(.vertical, action == nil ? 14 : 4)
        .background { skinBackground }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var skinBackground: some View {
        switch skin {
        case .card:
            RoundedRectangle(cornerRadius: Self.cardCorner)
                .fill(WebTheme.card)
                .overlay(RoundedRectangle(cornerRadius: Self.cardCorner)
                    .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        case .glass:
            Color.clear.jpGlass(in: RoundedRectangle(cornerRadius: Self.glassCorner))
        }
    }
}

/// **読み込み中**（v2 Components 06 の LOADING）。中身と同じ形の灰色の骨格を置く。
///
/// - **0.3 秒より早く読めたら骨格は出さない**（ちらつかせない・板の決まり）
/// - 光の流れ（きらめき）は付けない——「視差効果を減らす」の人に止める手間が要らない、灰色のまま
/// - 読み上げは「読み込み中」1つ（骨格の一つずつを読ませない）
///
/// `kind`——`grid`: 写真の格子（3 列・すき間 2）＋2 行の字。`rows`: 字の行だけ（一覧・札）。
/// `people`: 丸い顔（48）＋2 行の字の行を6つ（メッセージの受信箱・2026-11-10 札 #505 の画面案「読み込み中」）。
/// `bubbles`: 左右に振った吹き出しの形（会話・同じ画面案）。
///
/// **2026-11-12 判断（第2章）**: 2本の線だけの骨格と回る輪をやめ、**中身と同じ形の灰**にする。足した形:
/// `photoGrid`（格子だけ・枚数）・`personRows`（人の行 44・右に札か小さな写真）・`places`（場所の行 56）・
/// `cards`（横に並ぶ写真の札）・`comments`（コメント）・`albums`（アルバムの札）・`profile`（人のページの頭）
struct JPLoadingState: View {
    enum Kind: Equatable {
        case grid, rows, people, bubbles
        /// 写真の格子だけ（3 列・すき間 2・正方形）
        case photoGrid(count: Int)
        /// 人の行（顔 44・2 行の字・行 72）。右に何を置くか
        case personRows(trailing: PersonTrailing)
        /// 場所の行（写真 56・角 10・2 行の字・行 76）
        case places
        /// 横に並ぶ写真の札（探すの撮影スポットの段）
        case cards(width: CGFloat, height: CGFloat)
        /// コメント（顔 32・2 行の字）
        case comments
        /// アルバムの札（写真 64・2 行の字）
        case albums
        /// 人のページの頭（顔 88・名前・数）。下の札の行と格子は画面がそのまま出す（格子は `photoGrid`）
        case profile
    }

    /// 人の行の右の形
    enum PersonTrailing: Equatable {
        case none
        /// フォローの札（84×36）
        case pill
        /// 小さな写真（44・角 6・お知らせ）
        case thumb
    }

    var kind: Kind = .grid

    /// 骨格を出すまで待つ時間
    nonisolated static let revealDelay: Duration = .milliseconds(300)
    /// 骨格の灰（板の `#121213 → #1C1C1E`。光は流さないので中の値1つ）。土台の面の段 `surface4`
    nonisolated static let boneGray: UInt32 = BrandPalette.surface4

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

    /// 顔の行の字の幅（画面案の骨格の長さをそのまま・行ごとに替えて「同じ行の繰り返し」に見せない）
    nonisolated static let peopleBars: [(name: CGFloat, line: CGFloat)] = [
        (110, 190), (133, 227), (156, 264), (119, 211), (142, 248), (165, 195),
    ]
    /// 吹き出しの骨格（自分の側か・幅・高さ）
    nonisolated static let bubbleBones: [(mine: Bool, width: CGFloat, height: CGFloat)] = [
        (false, 200, 40), (false, 150, 40), (true, 220, 62), (false, 180, 40), (true, 120, 40),
    ]
    /// 人の行の字の幅（第2章の模型の長さ・8 行）
    nonisolated static let personBars: [(name: CGFloat, line: CGFloat)] = [
        (110, 190), (133, 190), (156, 170), (119, 190), (142, 190), (165, 190), (120, 180), (140, 190),
    ]
    /// コメントの骨格の字の幅
    nonisolated static let commentBars: [(name: CGFloat, line: CGFloat)] = [(90, 240), (70, 180)]

    @ViewBuilder
    private var skeleton: some View {
        switch kind {
        case .people:
            VStack(spacing: 0) {
                ForEach(Array(Self.peopleBars.enumerated()), id: \.offset) { _, bars in
                    HStack(spacing: JPSpace.s) {
                        Circle().fill(bone).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: JPSpace.xs) {
                            RoundedRectangle(cornerRadius: JPRadius.xs).fill(bone).frame(width: bars.name, height: 14)
                            RoundedRectangle(cornerRadius: JPRadius.xs).fill(bone).frame(width: bars.line, height: 12)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 72)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                    }
                }
            }
        case .bubbles:
            VStack(spacing: JPSpace.xs) {
                ForEach(Array(Self.bubbleBones.enumerated()), id: \.offset) { _, b in
                    HStack {
                        if b.mine { Spacer(minLength: 0) }
                        RoundedRectangle(cornerRadius: 20).fill(bone).frame(width: b.width, height: b.height)
                        if !b.mine { Spacer(minLength: 0) }
                    }
                }
            }
            .padding(.vertical, JPSpace.m)
        case .grid, .rows:
            gridOrRows
        case .photoGrid(let count):
            photoGrid(count)
        case .personRows(let trailing):
            personRows(trailing)
        case .places:
            places
        case .cards(let width, let height):
            cards(width: width, height: height)
        case .comments:
            comments
        case .albums:
            albums
        case .profile:
            profile
        }
    }

    @ViewBuilder
    private var gridOrRows: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if kind == .grid {
                photoGrid(6)
            }
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                bar(widthRatio: 0.7, height: 14)
                bar(widthRatio: 0.45, height: 12)
            }
            .padding(.horizontal, kind == .grid ? JPSpace.gutter : 0)
        }
        .padding(.vertical, JPSpace.m)
    }

    /// 写真の格子（3 列・すき間 2・正方形・角なし）
    private func photoGrid(_ count: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                Rectangle().fill(bone).aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private func personRows(_ trailing: PersonTrailing) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.personBars.enumerated()), id: \.offset) { _, bars in
                HStack(spacing: JPSpace.s) {
                    Circle().fill(bone).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: JPSpace.xs) {
                        block(bars.name, 14)
                        block(bars.line, 12)
                    }
                    Spacer(minLength: 0)
                    personTrailing(trailing)
                }
                .frame(minHeight: 72)
                .overlay(alignment: .bottom) { hairline }
            }
        }
    }

    @ViewBuilder
    private func personTrailing(_ trailing: PersonTrailing) -> some View {
        switch trailing {
        case .none:
            EmptyView()
        case .pill:
            Capsule().fill(bone).frame(width: 84, height: JPHeight.inlineButton)
        case .thumb:
            RoundedRectangle(cornerRadius: JPRadius.xs).fill(bone).frame(width: 44, height: 44)
        }
    }

    private var places: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                HStack(spacing: JPSpace.s) {
                    RoundedRectangle(cornerRadius: JPRadius.s).fill(bone).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: JPSpace.xs) {
                        block(CGFloat(150 - i * 9), 15)
                        block(CGFloat(110 + i * 7), 12)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 76)
                .overlay(alignment: .bottom) { hairline }
            }
        }
    }

    private func cards(width: CGFloat, height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: JPSpace.xs) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    RoundedRectangle(cornerRadius: JPRadius.m).fill(bone).frame(width: width, height: height)
                    block(min(100, width * 0.65), 15)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: JPSpace.m) {
            ForEach(Array(Self.commentBars.enumerated()), id: \.offset) { _, bars in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(bone).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: JPSpace.xs) {
                        block(bars.name, 13)
                        block(bars.line, 12)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, JPSpace.xs)
    }

    private var albums: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: JPSpace.s) {
                    RoundedRectangle(cornerRadius: JPRadius.s).fill(bone).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: JPSpace.xs) {
                        block(140, 16)
                        block(90, 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.l)
                    .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            }
        }
        .padding(.vertical, JPSpace.s)
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: JPSpace.m) {
                Circle().fill(bone).frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 10) {
                    block(120, 22)
                    block(150, 12)
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            HStack(spacing: JPSpace.xl) {
                block(90, 20)
                block(90, 20)
            }
            .padding(.horizontal, JPSpace.gutter)
        }
        .padding(.vertical, JPSpace.xs)
    }

    private var bone: Color { WebTheme.surface4 }

    private var hairline: some View {
        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
    }

    private func block(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: JPRadius.xs).fill(bone).frame(width: width, height: height)
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
