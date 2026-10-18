import SwiftUI

/// マイページの上の、旅のトランクの入口の札（2026-10-18 owner「入口がわかりずらい」）。
///
/// **1つの部品に閉じる**（2026-10-18 判断）: 読み込み・状態・見た目はここだけが持ち、`MyPageView` は
/// 出し分け（`TrunkEntryRule.shows`）とこの部品を置く1行だけ。あとで札を「トランクの絵そのもの」に替えるとき
/// （owner「トランクをマイページに載せたい」）、マイページを触らずにこの中身を差し替える。
///
/// - 右に硬貨の枚数（**白**。数は合図ではない・件数バッジではない）と、手持ちに貼っていないラベルが
///   あるときの**真鍮の点**（未読の点と同じ 8pt・黒地の札の上）。数を読めていない間は名前と矢印だけ
/// - 札は設定・旅の記録の行と同じ地（`WebTheme.card`・白 8% の縁・角 14）。高さは 54（押せる 44 以上）
/// - 読み上げは「旅のトランク、硬貨 3枚、まだ貼っていないラベルが 2枚あります」（点の色だけで伝えない）
/// - 数は `TrunkEntryStore`（`GET /user/trunk` の `coins`・`pocket`）。**開くたびには読まない**:
///   初回・6時間ごと・トランクから戻った・投稿を閉じた（`markStale`）・アプリが前面に戻った（`force`）ときだけ
struct TrunkProfileChip: View {

    /// トランクの画面の題に出す持ち主の名前
    var ownerName: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var availability = TrunkAvailability.shared
    @ObservedObject private var entry = TrunkEntryStore.shared
    /// 下の「投稿」の画面を閉じた合図（公開の投稿で硬貨とラベルが届く）
    @ObservedObject private var tabRouter = TabRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationLink {
            TrunkView(ownerName: ownerName)
                // 戻ったら数を読み直す（画面の中で硬貨を使う・ラベルを貼る）
                .onDisappear { entry.markStale() }
        } label: {
            label
        }
        .buttonStyle(JPRowButtonStyle())
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrunkEntryText.title)
        .accessibilityValue(TrunkEntryText.accessibilityValue(entry.summary))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("mypage.trunk")
        .padding(.horizontal, ProfileV2.gutter)
        .task(id: auth.userId) { await refresh() }
        // 戻ってきた（トランクから戻った回だけ `markStale` で読む。ほかの画面から戻っても読まない）
        .onAppear { Task { await refresh() } }
        .onChange(of: tabRouter.postSheetsClosed) { _, _ in
            entry.markStale()
            Task { await refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh(force: true) } }
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: "suitcase")
                .font(.system(size: 17))
                .foregroundStyle(WebTheme.muted2)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(TrunkEntryText.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let summary = entry.summary {
                HStack(spacing: 6) {
                    TrunkCoinMark(size: 16)
                    Text(TrunkEntryText.coins(summary.coins))
                        .font(JPFont.mono(15, relativeTo: .subheadline))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                }
                if summary.hasUnstuck {
                    Circle()
                        .fill(WebTheme.accent)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func refresh(force: Bool = false) async {
        await entry.refresh(userId: auth.userId, available: availability.isAvailable,
                            service: environment.trunk, force: force)
    }
}
