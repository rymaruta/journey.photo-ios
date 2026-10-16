import SwiftUI

/// ストーリーハイライト（モック2-5）。マイページと人のページ（板 31）の丸い並び。
///
/// **読み直すのは `userId` が変わったときだけ**（`.task(id:)`）。人のページは
/// フォローの状態で見えるものが変わるので、呼ぶ側が `.id(...)` に状態を含めて
/// 作り直す（`ProfileLine.highlightsKey`）。
///
/// **見られるのは本人とフォロワーだけ。** 追っていない人にはサーバーが
/// 0件を返すので、この行は**黙って消える**（「見られません」とは言わない
/// ——在ることも教えない、というサーバーの判断に画面を揃える）。
struct HighlightsRow: View {

    /// 誰のページか
    let userId: String
    /// 自分のページか。**新規と編集はここだけ**
    let isMine: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    @State private var highlights: [Highlight] = []
    @State private var loaded = false
    @State private var showEditor = false

    var body: some View {
        // **入れ物は必ず1つ置く。** 中身の有無で枝を分けて、それぞれに
        // `.task` を付けていたので、読み終わった瞬間に枝が入れ替わり
        // **同じ取得が2回**走っていた（無限にはならないが、開くたびに
        // 往復が1つ余る）。見張りは1本ずつ、が `getStories` の戒めと同じ。
        VStack(alignment: .leading, spacing: 8) {
            // **取れる前は何も出さない。** 空と「まだ読んでいない」を分ける
            // ——先に「まだありません」を出すと、読み終わった瞬間に入れ替わる
            if ProfileSections.showsHighlights(loaded: loaded, isMine: isMine,
                                               count: highlights.count) {
                header
                circles
            } else {
                // 読み終わる前も中身を1つ置き、`.task` を必ず走らせる（StoriesRow の 1.1.5 と同じ守り・2026-10-16）
                StoriesRow.loadingAnchor
            }
        }
        .task(id: userId) { await load() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
            HighlightEditorView(existing: nil)
        }
    }

    private var header: some View {
        HStack {
            // 板 v2 MyPage: 13px・semibold・text-2 の見出し
            Text(L("ストーリーハイライト", "Story highlights"))
                .font(JPFont.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.text2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // **すべて見るは、2つ以上あるときだけ。** 1つしかない画面で
            // 「すべて見る」を押すと同じものがもう一度出るだけになる
            if highlights.count > 1 {
                NavigationLink {
                    HighlightsListView(userId: userId, isMine: isMine)
                } label: {
                    HStack(spacing: 4) {
                        Text(L("すべて見る", "See all"))
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    // 押せる高さは 44pt。並びの高さは 28pt のまま（上下 8pt ずつはみ出す）
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -8)
                }
            }
        }
        .padding(.horizontal, ProfileV2.gutter)
    }

    /// 板 v2: 丸 64（白 22% の 1pt の縁の内側 3pt に写真）・間 14・名前 12 の text-2
    nonisolated static let ringSide: CGFloat = 64
    nonisolated static let ringSpacing: CGFloat = 14

    private var circles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Self.ringSpacing) {
                if isMine { newButton }
                ForEach(highlights) { highlight in
                    NavigationLink {
                        HighlightPlayerView(userId: userId, highlight: highlight, isMine: isMine)
                    } label: {
                        circle(highlight)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ProfileV2.gutter)
        }
    }

    private var newButton: some View {
        Button {
            showEditor = true
        } label: {
            VStack(spacing: 6) {
                // 板 v2: 64pt の点線の丸（白 22%）
                Circle()
                    .strokeBorder(Color.white.opacity(0.22),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: Self.ringSide, height: Self.ringSide)
                    .overlay(Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white))
                Text(L("新規", "New"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(1)
            }
            .frame(width: Self.ringSide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("ハイライトを作る", "Create a highlight"))
    }

    private func circle(_ highlight: Highlight) -> some View {
        VStack(spacing: 6) {
            // **表紙が無い輪がある。** 中のストーリーが全部消えた形
            // （アーカイブから外した）。丸ごと隠さず、絵だけ伏せる
            Group {
                if let url = highlight.coverURL {
                    RemoteImage(url: url)
                } else if highlight.cover?.isVideo == true {
                    // 表紙が動画（絵として読めない）。空の輪（✦）と見分ける
                    Circle().fill(WebTheme.card)
                        .overlay(Image(systemName: "play.circle")
                            .foregroundStyle(WebTheme.faint))
                } else {
                    Circle().fill(WebTheme.card)
                        .overlay(Image(systemName: "sparkles")
                            .foregroundStyle(WebTheme.faint))
                }
            }
            // 板 v2: 64pt の枠（縁 1pt・白 22%）の内側 3pt に写真（56pt）
            .frame(width: Self.ringSide - 8, height: Self.ringSide - 8)
            .clipShape(Circle())
            .padding(4)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: JPStroke.hairline))

            Text(highlight.displayTitle)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .lineLimit(1)
        }
        .frame(width: Self.ringSide)
        .contentShape(Rectangle())
    }

    private func load() async {
        // **取れなかった回に、在るものを消さない。** 失敗は静かに飲む
        // （この行はページの飾りで、赤い1行を出すほどのものではない）
        // ⚠️ `if let x = try? await …` は構文検査（tree-sitter）が読めない。
        // 2文に割る（`Tools/verify.sh` の最初の関門）
        let list = try? await environment.highlights.list(userId: userId)
        if let list { highlights = list }
        loaded = true
    }
}
