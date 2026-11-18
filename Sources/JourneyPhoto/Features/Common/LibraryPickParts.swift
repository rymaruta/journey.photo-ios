import SwiftUI
import UIKit

/// 写真の一覧の段の部品（投稿とストーリーで同じもの・2026-11-18 判断・案 B1）。
///
/// 見出しの行（左にガラスの丸の「閉じる」、真ん中に題、右に「アルバム」「選択」）、許可を増やす1行、
/// 一覧の上の入口のチップ。どちらの画面もここから組む（写しを作らない）

/// 一覧の段の見出しの行（案 B1: 左のガラスの丸 44・真ん中 SF 600 17・右の「選択」13 600）
struct LibraryPickHeader: View {

    let title: String
    let onClose: () -> Void
    /// 「選択」を入れているか（入れている間は「キャンセル」と出し、字を真鍮にする）
    let selecting: Bool
    let onToggleSelect: () -> Void
    /// アルバム（PHPicker・検索と古い写真）。nil なら出さない（許可の無い段は埋め込みの写真選びがその役）
    var onAlbums: (() -> Void)? = nil
    /// 読み込み中は「選択」「アルバム」を押せない
    var busy: Bool = false
    /// 識別子の頭（`post.library` / `story.library`）
    var idPrefix: String
    /// 「選択」の読み上げの補足
    var selectHint: String

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(WebTheme.text)
                .lineLimit(1)
                .padding(.horizontal, 110)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .jpGlass(in: Circle())
                        // 角の物は当たりを角の側へ広げる（見た目はそのまま・`CornerTapArea`）
                        .cornerTapArea(.topLeading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
                .accessibilityIdentifier("\(idPrefix).close")
                Spacer(minLength: 0)
                if let onAlbums {
                    Button(action: onAlbums) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WebTheme.foreground)
                            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || selecting)
                    .opacity(busy || selecting ? 0.4 : 1)
                    .accessibilityLabel(L("アルバムから選ぶ", "Choose from albums"))
                    .accessibilityIdentifier("\(idPrefix).albums")
                }
                Button(action: onToggleSelect) {
                    Text(selecting ? Labels.Common.cancel : L("選択", "Select"))
                        .font(JPFont.footnote.weight(.semibold))
                        // 入れている間は真鍮（黒地の上の合図・形も「キャンセル」に変わる）
                        .foregroundStyle(selecting ? WebTheme.accent : WebTheme.foreground)
                        .padding(.horizontal, 8)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityHint(selecting ? "" : selectHint)
                .accessibilityIdentifier("\(idPrefix).select")
            }
        }
        .frame(minHeight: CreateFlowRules.headerHeight)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

/// 許可を増やす1行（一部だけ許可・許可が無い）。決まりは `StoryLibraryRules`
enum LibraryAccessRows {

    /// 一部だけ許可した人の1行（左に説明、右に真鍮の「写真を増やす」）
    @MainActor
    static func limited(idPrefix: String, onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(StoryLibraryRules.limitedNote)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onAdd) {
                Text(StoryLibraryRules.limitedAction)
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(idPrefix).addAllowed")
        }
        .padding(.horizontal, 16)
    }

    /// 許可の無い人の1行（埋め込みの写真選びの上・押すと許可のダイアログか設定）
    @MainActor
    static func offer(_ offer: StoryLibraryRules.AccessOffer, idPrefix: String,
                      onAsk: @escaping () -> Void, onSettings: @escaping () -> Void) -> some View {
        Button {
            switch offer {
            case .ask: onAsk()
            case .openSettings: onSettings()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .font(.footnote.weight(.semibold))
                Text(StoryLibraryRules.offerTitle(offer))
                    .font(JPFont.footnote.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(WebTheme.accent)
            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(StoryLibraryRules.offerHint(offer))
        .accessibilityIdentifier("\(idPrefix).allow")
    }
}

/// 一覧の上の入口のチップ（「旅の写真からまとめて」「下書き n」・前の選ぶシートの行から移した）。
/// チップは見た目 34・当たり 44（DesignSystem 03）
struct LibraryEntryChips: View {

    let entries: [CreateFlowRules.Entry]
    let onTrip: () -> Void
    let onDrafts: () -> Void

    var body: some View {
        if !entries.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JPSpace.xs) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        chip(entry)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func chip(_ entry: CreateFlowRules.Entry) -> some View {
        switch entry {
        case .trip:
            Button(action: onTrip) {
                chipLabel(symbol: "suitcase", title: L("旅の写真からまとめて", "From a trip in your photos"), count: nil)
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("撮影日と場所から旅を見つけます。", "Finds trips by when and where you shot."))
            .accessibilityIdentifier("post.choice.trip")
        case .drafts(let count):
            Button(action: onDrafts) {
                chipLabel(symbol: "square.and.pencil", title: DraftsText.title, count: count)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DraftsText.entryAccessibility(count))
            .accessibilityIdentifier("post.choice.drafts")
        }
    }

    private func chipLabel(symbol: String, title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(JPFont.footnote)
                .lineLimit(1)
            if let count {
                // 件数は真鍮のバッジ（黒地の上の合図・前の「下書き n ›」と同じ）
                CountBadge(count: count)
            }
        }
        .foregroundStyle(WebTheme.chipText)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: 1))
        .padding(.vertical, 5)
        .contentShape(Capsule())
    }
}

/// 一覧の下の「投稿 | ストーリー」（案 B1: ガラスのカプセル 220×48・選んでいる側 #2C2C2E・字 13 600）
struct CreateModeSwitcher: View {

    let mode: CreateFlowRules.Mode
    let onSelect: (CreateFlowRules.Mode) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CreateFlowRules.Mode.allCases) { item in
                Button { onSelect(item) } label: {
                    Text(CreateFlowRules.segmentTitle(item))
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(item == mode ? WebTheme.text : WebTheme.text2)
                        .frame(maxWidth: .infinity, minHeight: CreateFlowRules.capsuleHeight - 2 * CreateFlowRules.capsuleInset)
                        .background {
                            if item == mode {
                                Capsule().fill(WebTheme.surface8)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == mode ? .isSelected : [])
                .accessibilityIdentifier(CreateFlowRules.segmentIdentifier(item))
            }
        }
        .padding(CreateFlowRules.capsuleInset)
        .frame(width: CreateFlowRules.capsuleWidth, height: CreateFlowRules.capsuleHeight)
        .jpGlass(in: Capsule())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("投稿とストーリーの切り替え", "Post or story"))
    }
}

/// 投稿の入口（下の「投稿」）の中で開いた画面か。中なら一覧の段に「旅の写真から」「構図」の入口を出し、
/// 一覧を見ている間を知らせる（`CreateFlow.libraryShown`）。外（テーマ・観光スポット・下書きから開いた投稿の画面）では nil
struct CreateFlowKey: EnvironmentKey {
    static let defaultValue: CreateFlow? = nil
}

extension EnvironmentValues {
    var createFlow: CreateFlow? {
        get { self[CreateFlowKey.self] }
        set { self[CreateFlowKey.self] = newValue }
    }
}

/// 投稿の入口の状態（いまの切り替え・一覧を見ているか・選んだ入口）
@MainActor
final class CreateFlow: ObservableObject {

    @Published var mode: CreateFlowRules.Mode
    /// 中の画面が一覧の段を出しているか（出している間だけ切り替えを出し、払って替えられる）
    @Published var libraryShown = true
    /// 選んだ入口（旅の写真から・構図・下書き）。入口の画面を閉じきってから呼び手が開く
    private(set) var chosen: PostEntry?
    /// 写真を投稿した・ストーリーを作り始めた（閉じたあとにマイページ・ホームを読み直す）
    var used = false

    init(mode: CreateFlowRules.Mode = .post) {
        self.mode = mode
    }

    /// 入口を選んだ（画面は呼び手が閉じる）
    func choose(_ entry: PostEntry) {
        chosen = entry
    }

    /// 閉じきったあとに1回だけ取り出す
    func takeChosen() -> PostEntry? {
        defer { chosen = nil }
        return chosen
    }

    /// 中の画面が一覧の段を出した・離れた
    func noteLibrary(_ shown: Bool) {
        if libraryShown != shown { libraryShown = shown }
        if !shown { used = true }
    }
}

/// **下の「投稿」で開く画面**（案 B1）。投稿の画面（`UploadView`）とストーリーの作る画面（`StoryComposerView`）を
/// 下の切り替えで入れ替える。どちらも最初の段は同じ写真の一覧（`LibraryGrid`）。
///
/// 一覧を見ている間だけ、下にガラスの「投稿 | ストーリー」を出し、一覧を左右に払っても替わる
/// （欄を書く・作る段では出さない・払っても替えない——書きかけを払っただけで失わない）
struct CreateFlowView: View {

    @StateObject private var flow: CreateFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mode: CreateFlowRules.Mode = .post, flow: CreateFlow? = nil) {
        _flow = StateObject(wrappedValue: flow ?? CreateFlow(mode: mode))
    }

    var body: some View {
        // UI テストのときだけ: body の評価を数える（`PerfTimeline`）
        let _ = PerfTimeline.shared.count("body.createFlow")
        ZStack {
            Color.black.ignoresSafeArea()
            switch flow.mode {
            case .post:
                NavigationStack {
                    // 上がった写真をマイページ・ホームに先に並べる（`TabRouter.notePosted`・下の「投稿」から開いたとき）
                    UploadView(onSaved: { TabRouter.shared.notePosted($0) })
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            case .story:
                NavigationStack {
                    StoryComposerView()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .environment(\.createFlow, flow)
        // 一覧を見ている間だけ下に切り替え。中の画面の下の物（「次へ（N枚）」）はこの上に乗る
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if CreateFlowRules.showsSwitcher(libraryShown: flow.libraryShown) {
                CreateModeSwitcher(mode: flow.mode) { select($0) }
                    .padding(.top, 8)
                    .padding(.bottom, CreateFlowRules.capsuleBottomGap)
                    .frame(maxWidth: .infinity)
            }
        }
        // 一覧を左右に払っても替わる（一覧の段だけ。作る段では中の指の操作だけを通す）
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard flow.libraryShown,
                          let next = CreateFlowRules.swiped(from: flow.mode, dx: value.translation.width,
                                                            dy: value.translation.height) else { return }
                    select(next)
                },
            including: flow.libraryShown ? .all : .subviews
        )
    }

    private func select(_ mode: CreateFlowRules.Mode) {
        guard mode != flow.mode else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            flow.mode = mode
            // 替えた先も一覧から始まる（中の画面が離れたら知らせ直す）
            flow.libraryShown = true
        }
    }
}
