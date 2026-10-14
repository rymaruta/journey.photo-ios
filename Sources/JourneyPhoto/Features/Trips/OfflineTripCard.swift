import SwiftUI
import UIKit

/// 旅行プランの日程（17b）の日付の下に置く「電波なしで使えるようにする」の札（板 72・72b・2026-10-09）。
///
/// 姿は `OfflineSaveStatus.phase` が決める: 保存前・保存中・途中で止まった（続きから保存）・保存済み・
/// 保存したあとにプランが変わった・削除の確かめ・Pro でない。
///
/// **比べる相手はサーバーの姿のプラン**（`plan`）。打っている途中の下書きでは比べない
/// （保存していない編集は、圏外の中身にも、サーバーにもまだ無い）
struct OfflineTripCard: View {

    let plan: TripPlan
    /// 名前・座標を引く材料（日程の画面が読んだもの）
    let index: [OfficialSpot]
    let places: [DerivedSpot.Place]
    /// 日程の画面が、プランの名前を引く材料を読めたか（読めないうちは保存させない——名前が鍵のままになる）
    let sourcesReady: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var offline: OfflineTripStore
    @State private var isPro: Bool?
    @State private var confirmingDelete = false
    @State private var showPaywall = false
    @State private var preparing = false
    /// Pro かを確かめられなかったときの1行（圏外で開いた・`OfflineTripAccess.Decision.unverified`）
    @State private var accessError: String?

    private var status: OfflineSaveStatus { offline.status(plan.planId) }
    private var change: OfflineTripPrint.Change {
        offline.manifest(plan.planId).map { $0.print.change(to: OfflineTripPrint(plan)) } ?? .none
    }
    private var phase: OfflineSaveStatus.Phase { status.phase(isPro: isPro, change: change) }

    var body: some View {
        Group {
            switch phase {
            case .hidden:
                EmptyView()
            case .free:
                freeCard
            default:
                card
            }
        }
        .task {
            // Pro かどうかはサーバーが決める（読めなければ nil）
            isPro = (try? await environment.profiles.myProfile())?.isPro
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .onChange(of: showPaywall) { _, shown in
            // 案内から戻ったら確かめ直す（買った直後）
            guard !shown else { return }
            Task { isPro = (try? await environment.profiles.myProfile())?.isPro }
        }
    }

    // MARK: - 札

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if confirmingDelete, let saved = savedBytes {
                deleteConfirm(bytes: saved)
            } else {
                switch phase {
                case .before:
                    before
                case .saving(let p):
                    saving(p)
                case .interrupted(let p):
                    interrupted(p)
                case .saved(let s):
                    saved(s, change: nil)
                case .stale(let s, let c):
                    saved(s, change: c)
                case .free, .hidden:
                    EmptyView()
                }
                if let error = accessError ?? status.error {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .offlineCardFace()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("電波なしで使う", "Use offline"))
    }

    /// 札の見出し（板 `.ot`: 16 の太字。電話の印は真鍮。保存済みかどうかは印の形（矢印・チェック）で言い分ける。
    /// 2026-10-14 判断: 板の注記は保存済みを緑にしていたが、画面の色は白・黒・真鍮・危険の色だけ（CLAUDE.md）。
    /// 緑は入れない）。
    /// `icon: false` は印を置かない姿（保存中・途中で止まった・削除の確かめ）
    private func header(_ title: String, saved: Bool = false, icon: Bool = true, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            if icon {
                OfflinePhoneIcon(saved: saved, color: WebTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// 1 保存前
    private var before: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("電波なしで使えるようにする", "Make available offline"))
            Text(OfflineTripText.beforeBody(stops: plan.itemCount))
                .font(JPFont.footnote)
                .lineSpacing(4)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Text(OfflineTripText.estimateLine(stops: plan.itemCount))
                .font(JPFont.meta)
                .foregroundStyle(WebTheme.text3)
            primaryButton(L("端末に保存する", "Save to this iPhone"), action: .save)
        }
    }

    /// 2 保存中
    private func saving(_ p: OfflineSaveStatus.Progress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("端末に保存しています", "Saving to this iPhone"), icon: false)
            OfflineProgressBar(done: p.done, total: p.total)
            HStack {
                Text(OfflineTripText.progressPlaces(done: p.done, total: p.total))
                Spacer()
                Text(OfflineTripText.progressBytes(bytes: p.bytes, estimate: p.estimate))
            }
            .font(JPFont.mono(13, relativeTo: .footnote))
            .foregroundStyle(WebTheme.text2)
            .accessibilityHidden(true)
            Text(L("ほかの画面に移っても続きます", "Keeps going if you leave this screen"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
            TripOutlineButton(title: L("止める", "Stop")) {
                offline.stop(plan.planId)
            }
        }
    }

    /// 途中で止まった（owner 2026-10-09: 次に開いたら「続きから保存」）。板 72b-2 の姿で、棒は止まったところ
    private func interrupted(_ p: OfflineSaveStatus.Partial) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("保存が途中で止まりました", "Saving stopped partway"), icon: false)
            // 止まったところの棒（板 7: 真鍮 50%）
            OfflineProgressBar(done: p.done, total: p.total, stalled: true)
            Text(OfflineTripText.interruptedBody(done: p.done, total: p.total))
                .font(JPFont.footnote)
                .lineSpacing(4)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            // 板 7: 主ボタンと「端末から削除」の線を横に並べる
            HStack(spacing: JPSpace.xs) {
                primaryButton(L("続きから保存", "Continue saving"), action: .resume)
                TripOutlineButton(title: L("端末から削除", "Remove from iPhone"), danger: true) {
                    offline.delete(plan.planId)
                }
            }
        }
    }

    /// 3 保存済み・4 保存したあとにプランが変わった
    private func saved(_ s: OfflineSaveStatus.Saved, change: OfflineTripPrint.Change?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("電波なしで使えます", "Available offline"), saved: true,
                   detail: OfflineTripText.savedLine(bytes: s.bytes, savedAt: s.savedAt))
            if let change, let message = OfflineTripText.staleMessage(change) {
                // プランが変わった知らせ（板 4: 真鍮 8% の帯に真鍮の字・黒地の上の合図）
                Text(message)
                    .font(JPFont.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JPSpace.s)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: JPRadius.s))
                HStack(spacing: JPSpace.xs) {
                    primaryButton(L("保存し直す", "Save again"), action: .resave)
                    TripOutlineButton(title: L("端末から削除", "Remove from iPhone"), danger: true) {
                        confirmingDelete = true
                    }
                }
            } else {
                if let manifest = offline.manifest(plan.planId) {
                    // 真鍮の文字のリンク（板 3・黒地の上の手がかり）
                    NavigationLink {
                        OfflineTripView(manifest: manifest, preview: true)
                    } label: {
                        Text(L("電波がないときの見え方を確かめる ›", "See how it looks offline ›"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: JPSpace.xs) {
                    TripOutlineButton(title: L("保存し直す", "Save again")) {
                        run(.resave)
                    }
                    TripOutlineButton(title: L("端末から削除", "Remove from iPhone"), danger: true) {
                        confirmingDelete = true
                    }
                }
            }
        }
    }

    /// 5 削除の確かめ（札の中で開く）
    private func deleteConfirm(bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("端末から削除しますか？", "Remove from this iPhone?"), icon: false)
            Text(OfflineTripText.deleteBody(bytes: bytes))
                .font(JPFont.footnote)
                .lineSpacing(4)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            // 板 5: 「削除する」は赤 16% の地・赤 50% の線・白の字。キャンセルは線
            HStack(spacing: JPSpace.xs) {
                TripOutlineButton(title: L("削除する", "Remove"), strong: true) {
                    confirmingDelete = false
                    offline.delete(plan.planId)
                    UIAccessibility.post(notification: .announcement,
                                         argument: L("端末から削除しました", "Removed from this iPhone"))
                }
                TripOutlineButton(title: Labels.Common.cancel) {
                    confirmingDelete = false
                }
            }
        }
    }

    /// 6 Pro でない（押すと Pro の案内）
    private var freeCard: some View {
        Button { showPaywall = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(L("電波なしで使えるようにする", "Make available offline"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                    // Pro の印（板 6: 真鍮の線の札・眉ラベルと同じ字）
                    Text("PRO")
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: JPRadius.s)
                            .strokeBorder(WebTheme.accent.opacity(0.6), lineWidth: JPStroke.hairline))
                }
                Text(L("作例・光の時刻・メモと周りの地図を端末に保存して、圏外でも旅を確かめられます。",
                       "Save examples, light times, notes and map images to your iPhone to check your trip with no signal."))
                    .font(JPFont.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(WebTheme.text2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Pro について見る ›", "Learn about Pro ›"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
            }
            .offlineCardFace()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("電波なしで使えるようにする · Pro の機能 · Pro について見る",
                              "Make available offline · Pro feature · Learn about Pro"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 押したとき

    private var savedBytes: Int64? {
        offline.manifest(plan.planId)?.bytes
    }

    private func run(_ action: OfflineTripAccess.Action) {
        guard !preparing else { return }
        accessError = nil
        switch OfflineTripAccess.decide(action, isPro: isPro) {
        case .paywall:
            showPaywall = true
            return
        case .proceed, .unverified:
            break
        }
        preparing = true
        let plan = plan, index = index, places = places
        let unverified = OfflineTripAccess.decide(action, isPro: isPro) == .unverified
        Task { @MainActor in
            defer { preparing = false }
            // Pro か分からなかった（開いたときに読めなかった）→ 確かめ直してから決める
            if unverified {
                isPro = (try? await environment.profiles.myProfile())?.isPro
                switch OfflineTripAccess.decide(action, isPro: isPro) {
                case .proceed: break
                case .paywall:
                    showPaywall = true
                    return
                case .unverified:
                    accessError = OfflineTripText.failureMessage(.notPro)
                    return
                }
            }
            let planned = await OfflineTripLive.plannedStops(plan: plan, environment: environment,
                                                             index: index, places: places)
            let sources = OfflineTripLive.sources(environment: environment, index: planned.index, places: places)
            offline.save(plan: plan, stops: planned.stops, sources: sources)
        }
    }

    // MARK: - ボタン

    /// 主ボタン（写真の無い画面＝真鍮の塗りに墨・`JPPillStyle.main(onPhoto: false)`）
    private func primaryButton(_ title: String, action: OfflineTripAccess.Action) -> some View {
        let ready = sourcesReady && plan.itemCount > 0 && !preparing
        return Button { run(action) } label: {
            Text(title)
                .jpPillButton(.main(onPhoto: false))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(ready ? 1 : 0.5)
    }
}

extension View {
    /// 電波なしで使う札の面（板 `.oc`: surface-1・白 8% の縁・角 16・内側 16）
    func offlineCardFace() -> some View {
        self
            .padding(JPSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jpCardFace()
    }
}
