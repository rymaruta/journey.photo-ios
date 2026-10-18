import SwiftUI
import UIKit

/// マイページの上の、旅のトランクの入口の札（2026-10-18 owner「入口がわかりずらい」）。
///
/// **1つの部品に閉じる**（2026-10-18 判断）: 読み込み・状態・見た目はここだけが持ち、`MyPageView` は
/// 出し分け（`TrunkEntryRule.shows`）とこの部品を置く1行だけ。あとで札を「トランクの絵そのもの」に替えるとき
/// （owner「トランクをマイページに載せたい」）、マイページを触らずにこの中身を差し替える。
///
/// - 右に硬貨の枚数（**白**。数は合図ではない・件数バッジではない）。手持ちに貼っていないラベルが
///   あるときは**名前のすぐ右に真鍮の点**（未読の点と同じ 8pt・黒地の札の上）。2026-10-18 見直し: 硬貨の印
///   （真鍮の丸）の隣だと見分けにくいので、点は名前の側に離した。数を読めていない間は名前と矢印だけ
/// - **A′ 絵入りの1行**（2026-10-18 板「旅のトランク」EntryOptions・MyPageEntry）: 左に自分のトランクの絵
///   （48×40・`TrunkEntryThumb`。型・付けた部品・貼ったラベル・古び方がそのまま見える）、題の下に型の名前
///   （12pt・text-2）。札は設定・旅の記録の行と同じ地（`WebTheme.card`・白 8% の縁・角 14）。高さは 56
/// - 読み上げは「旅のトランク、革の旅行鞄、硬貨 3枚、まだ貼っていないラベルが 2枚あります」（点の色だけで伝えない）
/// - 数は `TrunkEntryStore`（`GET /user/trunk` の `coins`・`pocket`）。**開くたびには読まない**:
///   初回・6時間ごと・この札からトランクへ行って戻った・公開の写真を投稿した（`markStale`）ときだけ。
///   アプリが裏から戻ったときは、マイページの口の確かめ（`TrunkAvailability.refresh(force:)`）の1回で数も入る。
///   **札が画面に出ていない間は読まない**（別のタブで投稿したら、マイページに来たときに読む）
/// - 旅の記録のタブの行からトランクへ行って戻った回は、ここでは拾えない（その行は `MyPageView` のまま・
///   トランクの画面の側に戻りの合図が無い）。次に裏から戻ったとき・6時間後に読む
struct TrunkProfileChip: View {

    /// トランクの画面の題に出す持ち主の名前
    var ownerName: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var availability = TrunkAvailability.shared
    @ObservedObject private var entry = TrunkEntryStore.shared
    /// 下の「投稿」の画面を閉じた合図（公開の投稿で硬貨とラベルが届く）
    @ObservedObject private var tabRouter = TabRouter.shared
    /// 画面に出ているか（出ていない間は読まない）
    @State private var isOnScreen = false

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
        // 押せる1つのボタンのまま、名前と値を付ける（`.ignore` で包むと VoiceOver の2回叩きで開けない）
        .accessibilityLabel(TrunkEntryText.title)
        .accessibilityValue(TrunkEntryText.accessibilityValue(entry.summary, model: TrunkEntryText.modelName(entry.state)))
        .accessibilityIdentifier("mypage.trunk")
        .padding(.horizontal, ProfileV2.gutter)
        .task(id: auth.userId) { await refresh() }
        // 戻ってきた（トランクから戻った回だけ `markStale` で読む。ほかの画面から戻っても読まない）
        .onAppear {
            isOnScreen = true
            Task { await refresh() }
        }
        .onDisappear { isOnScreen = false }
        // 公開の写真を投稿したときだけ（取り消し・ストーリー・下書き・公開範囲を絞った写真では読まない）
        .onChange(of: tabRouter.postSheetsClosed) { _, _ in
            guard TrunkEntryRule.postedPublic(tabRouter.lastPosted) else { return }
            entry.markStale()
            if isOnScreen { Task { await refresh() } }
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            // 自分のトランクの絵（読めるまでは鞄の印）
            Group {
                if let state = entry.state {
                    TrunkEntryThumb(state: state, ownerName: ownerName)
                } else {
                    Image(systemName: "suitcase")
                        .font(.system(size: 17))
                        .foregroundStyle(WebTheme.muted2)
                }
            }
            .frame(width: TrunkEntryThumb.size.width, height: TrunkEntryThumb.size.height)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(TrunkEntryText.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                    if entry.summary?.hasUnstuck == true {
                        Circle()
                            .fill(WebTheme.accent)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                if let model = TrunkEntryText.modelName(entry.state) {
                    Text(model)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let summary = entry.summary {
                HStack(spacing: 6) {
                    TrunkCoinMark(size: 16)
                    Text(TrunkEntryText.coins(summary.coins))
                        .font(JPFont.mono(15, relativeTo: .subheadline))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func refresh() async {
        await entry.refresh(userId: auth.userId, available: availability.isAvailable, service: environment.trunk)
    }
}

/// 札の左の小さなトランクの絵（48×40・2026-10-18 A′）。
///
/// 描き方はトランクの画面と同じ `TrunkBoxView`（胴だけ・`bodyOnly`）を、回す画面の絵（`TrunkTextures`）と同じく
/// **1枚の絵にしてから**縮めて出す。小さく描くので、影・ぼかし・重なりの重い描き方を毎回の描画でしない。
/// 絵を作るのは画面に出ている間だけ（`.task`）で、中身（型・投稿の数・貼ったラベル・部品）が変わったときだけ作り直す
struct TrunkEntryThumb: View {

    let state: TrunkState
    var ownerName: String?

    static let size = CGSize(width: 48, height: 40)

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private struct Key: Equatable {
        let state: TrunkState
        let ownerName: String?
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .task(id: Key(state: state, ownerName: ownerName)) {
            image = TrunkEntryThumbs.image(state: state, ownerName: ownerName, scale: displayScale)
        }
    }
}

/// 作った絵の控え（最後の1枚だけ。マイページと設定から戻るたびに作り直さない）
@MainActor
enum TrunkEntryThumbs {

    private static var last: (state: TrunkState, ownerName: String?, scale: CGFloat, image: UIImage)?

    static func image(state: TrunkState, ownerName: String?, scale: CGFloat) -> UIImage? {
        if let last, last.state == state, last.ownerName == ownerName, last.scale == scale { return last.image }
        let box = TrunkBoxView(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                               ownerName: ownerName, bodyOnly: true, parts: state.equipped)
        let renderer = ImageRenderer(content: box)
        // 横 360 の胴を 48pt に（端末の倍率ぶん細かく）
        renderer.scale = max(1, scale) * TrunkEntryThumb.size.width / TrunkLooks.bodyWidth
        guard let made = renderer.uiImage else { return nil }
        last = (state, ownerName, scale, made)
        return made
    }
}
