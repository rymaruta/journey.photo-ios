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
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("電波なしで使う", "Use offline"))
    }

    private func header(_ title: String, saved: Bool = false, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            OfflinePhoneIcon(saved: saved)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(JPFont.mono(12))
                        .foregroundStyle(WebTheme.faint)
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
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(WebTheme.muted2)
                .fixedSize(horizontal: false, vertical: true)
            Text(OfflineTripText.estimateLine(stops: plan.itemCount))
                .font(JPFont.mono(12))
                .foregroundStyle(WebTheme.faint)
            primaryButton(L("端末に保存する", "Save to this iPhone"), action: .save)
        }
    }

    /// 2 保存中
    private func saving(_ p: OfflineSaveStatus.Progress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("端末に保存しています", "Saving to this iPhone"))
            OfflineProgressBar(done: p.done, total: p.total)
            HStack {
                Text(OfflineTripText.progressPlaces(done: p.done, total: p.total))
                Spacer()
                Text(OfflineTripText.progressBytes(bytes: p.bytes, estimate: p.estimate))
            }
            .font(JPFont.mono(12))
            .foregroundStyle(WebTheme.muted2)
            .accessibilityHidden(true)
            Text(L("ほかの画面に移っても続きます", "Keeps going if you leave this screen"))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
            outlineButton(L("止める", "Stop"), color: WebTheme.foreground) {
                offline.stop(plan.planId)
            }
        }
    }

    /// 途中で止まった（owner 2026-10-09: 次に開いたら「続きから保存」）。板 72b-2 の姿で、棒は止まったところ
    private func interrupted(_ p: OfflineSaveStatus.Partial) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("保存が途中で止まりました", "Saving stopped partway"))
            OfflineProgressBar(done: p.done, total: p.total)
            Text(OfflineTripText.interruptedBody(done: p.done, total: p.total))
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
                .fixedSize(horizontal: false, vertical: true)
            primaryButton(L("続きから保存", "Continue saving"), action: .resume)
            outlineButton(L("端末から削除", "Remove from iPhone"), color: WebTheme.danger) {
                offline.delete(plan.planId)
            }
        }
    }

    /// 3 保存済み・4 保存したあとにプランが変わった
    private func saved(_ s: OfflineSaveStatus.Saved, change: OfflineTripPrint.Change?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("電波なしで使えます", "Available offline"), saved: true,
                   detail: OfflineTripText.savedLine(bytes: s.bytes, savedAt: s.savedAt))
            if let change, let message = OfflineTripText.staleMessage(change) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(WebTheme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                primaryButton(L("保存し直す", "Save again"), action: .resave)
                Button {
                    confirmingDelete = true
                } label: {
                    Text(L("端末から削除", "Remove from iPhone"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                if let manifest = offline.manifest(plan.planId) {
                    VStack(spacing: 0) {
                        JPCardDivider()
                        NavigationLink {
                            OfflineTripView(manifest: manifest, preview: true)
                        } label: {
                            HStack(spacing: 6) {
                                Text(L("電波がないときの見え方を確かめる", "See how it looks offline"))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.accent)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    outlineButton(L("保存し直す", "Save again"), color: WebTheme.foreground) {
                        run(.resave)
                    }
                    outlineButton(L("端末から削除", "Remove from iPhone"), color: WebTheme.danger) {
                        confirmingDelete = true
                    }
                }
            }
        }
    }

    /// 5 削除の確かめ（札の中で開く）
    private func deleteConfirm(bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("端末から削除しますか？", "Remove from this iPhone?"), saved: true)
            Text(OfflineTripText.deleteBody(bytes: bytes))
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                outlineButton(L("削除する", "Remove"), color: WebTheme.danger, bold: true) {
                    confirmingDelete = false
                    offline.delete(plan.planId)
                    UIAccessibility.post(notification: .announcement,
                                         argument: L("端末から削除しました", "Removed from this iPhone"))
                }
                outlineButton(Labels.Common.cancel, color: WebTheme.foreground) {
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
                    OfflinePhoneIcon(color: WebTheme.muted2)
                    Text(L("電波なしで使えるようにする", "Make available offline"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                    Text("PRO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WebTheme.accent, lineWidth: 1))
                }
                Text(L("作例・光の時刻・メモと周りの地図を端末に保存して、圏外でも旅を確かめられます。",
                       "Save examples, light times, notes and map images to your iPhone to check your trip with no signal."))
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.muted2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    JPCardDivider()
                    HStack(spacing: 6) {
                        Text(L("Pro について見る", "Learn about Pro"))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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

    /// 主ボタン（写真の無い画面＝真鍮の塗りに墨・デザインシステム）
    private func primaryButton(_ title: String, action: OfflineTripAccess.Action) -> some View {
        let ready = sourcesReady && plan.itemCount > 0 && !preparing
        return Button { run(action) } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .background(WebTheme.accentFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(ready ? 1 : 0.5)
    }

    private func outlineButton(_ title: String, color: Color, bold: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(bold ? .footnote.weight(.semibold) : .footnote)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 保存の進み（板: 高さ 6・白 12% の地に真鍮）
struct OfflineProgressBar: View {
    let done: Int
    let total: Int

    var body: some View {
        let fraction = total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(WebTheme.accent).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(L("端末への保存", "Saving to this iPhone"))
        .accessibilityValue(OfflineTripText.progressAccessibility(done: done, total: total))
    }
}
