import SwiftUI

/// ストーリーハイライト（モック2-5）。マイページの丸い並び。
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
            }
        }
        .task(id: userId) { await load() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
            HighlightEditorView(existing: nil)
        }
    }

    private var header: some View {
        HStack {
            // 板 05c: 12px・medium・白60% の見出し
            Text(L("ストーリーハイライト", "Story highlights"))
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.faint)
            Spacer()
            // **すべて見るは、2つ以上あるときだけ。** 1つしかない画面で
            // 「すべて見る」を押すと同じものがもう一度出るだけになる
            if highlights.count > 1 {
                NavigationLink {
                    HighlightsListView(userId: userId, isMine: isMine)
                } label: {
                    HStack(spacing: 4) {
                        Text(L("すべて見る", "See all"))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
                    .frame(minHeight: 28)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var circles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
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
            .padding(.horizontal, 20)
        }
    }

    private var newButton: some View {
        Button {
            showEditor = true
        } label: {
            VStack(spacing: 6) {
                // 板: 62pt の点線の丸（白35%）
                Circle()
                    .strokeBorder(Color.white.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: 62, height: 62)
                    .overlay(Image(systemName: "plus")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white))
                Text(L("新規", "New"))
                    .font(.caption2)
                    .foregroundStyle(WebTheme.muted2)
                    .lineLimit(1)
            }
            .frame(width: 66)
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
                } else {
                    Circle().fill(WebTheme.surface)
                        .overlay(Image(systemName: "sparkles")
                            .foregroundStyle(WebTheme.faint))
                }
            }
            // 板: 62pt の枠（白25%）の内側 3pt に写真
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .padding(3)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))

            Text(highlight.displayTitle)
                .font(.caption2)
                .foregroundStyle(WebTheme.muted2)
                .lineLimit(1)
        }
        .frame(width: 66)
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
