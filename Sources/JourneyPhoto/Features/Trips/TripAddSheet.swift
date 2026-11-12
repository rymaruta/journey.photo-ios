import SwiftUI

/// どの頁からも「旅行プランに入れる」（2026-11-10 判断・札 #521・案 A）。
///
/// 撮影スポットの頁・撮影地の頁・写真の詳細の「行き先」の段から開く。
///
/// 🔴 **マイページの「行きたい場所」の行には置かない**（2026-11-10 owner「マイページはかえなくていい」・札 #519）。
/// 仕様の「行きたい場所の一覧からの入口」は、マイページの外にある入口（行きたい場所の地図 `SavedSpotsMapView` の
/// 「この N か所で旅行プランを作る」・撮影スポット／撮影地の頁の札・このシート）で足りるので、今回は作らない
/// **出発が近いプランを先に選んで開く**（`TripPlanEdit.defaultPlan`）・入れる日は入れる場所にいちばん近い場所がある日
/// （`TripPlanEdit.suggestedDay`）。押す回数は「旅行プランに入れる → 2 日目 → 入れる」の 3 回（別のプランなら +1）。
/// 今は「行きたい → マイページ → 旅行プラン → プラン → 追加… → 選ぶ → 追加 → 保存」の 8 回。
///
/// - 入れた場所は「行きたい」にも入る（写真から選ぶと同じ・`WishlistSync`）
/// - 「新しい旅行プラン」は作る流れ（`TripCreateView`）を、この場所を選んだ形で開く
/// - 送るのは今の口（`TripPlanService.update`・日程だけ）。サーバー・プランの形は変えない
///
/// 写真の無い面なので、主ボタンは真鍮の塗りに墨。選んだ印は真鍮（板 TripPlanPick）
struct TripAddSheet: View {

    let place: TripDraft.Place
    /// 「行きたい」の鍵（撮影スポットは `SPOT-<slug>`・撮影地は slug）
    let wishKey: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @StateObject private var plans = TripPlansModel()
    @State private var index: [OfficialSpot] = []
    @State private var planId: String?
    /// 入れる日（nil は「日を足す」）
    @State private var day: Int?
    @State private var chose = false
    @State private var showCreate = false
    @State private var createdPlanId: String?
    @State private var error: String?

    private var selectedPlan: TripPlan? { planId.flatMap { plans.plan($0) } }

    var body: some View {
        Group {
            if auth.userId == nil {
                SignInView(reason: L("旅行プランに入れるにはログインしてください", "Sign in to add this to a trip."))
            } else {
                content
            }
        }
        .webScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SheetCloseButton().disabled(plans.busy != nil) }
        }
        .interactiveDismissDisabled(plans.busy != nil)
        .task {
            await plans.load(environment: environment)
            let fetched = try? await environment.spots.fetchIndex()
            if let fetched { index = fetched }
            chooseDefault()
        }
        .fullScreenCover(isPresented: $showCreate, onDismiss: {
            guard let made = createdPlanId else { return }
            createdPlanId = nil
            let title = plans.plan(made)?.title ?? ""
            toasts.show(L("旅行プラン「\(title)」を作りました", "Created “\(title)”"))
            dismiss()
        }) {
            TripCreateView(plans: plans, initial: [place], startAtDates: true) { made in
                Task { await wish() }
                createdPlanId = made
                showCreate = false
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(place.name)
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                    Text(L("旅行プランに入れる", "Add to a trip"))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                }

                switch plans.status {
                case .loading:
                    JPLoadingState(kind: .rows)
                case .failed:
                    ErrorBanner(title: L("旅行プランを読み込めませんでした", "Couldn't load your trips"),
                                message: ErrorBanner.defaultMessage,
                                isBusy: plans.status == .loading) {
                        Task { await plans.load(environment: environment); chooseDefault() }
                    }
                case .loaded:
                    VStack(spacing: 0) {
                        ForEach(plans.plans) { plan in
                            planRow(plan)
                        }
                        newPlanRow
                    }
                }

                if let error {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                }
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .safeAreaInset(edge: .bottom) {
            if let plan = selectedPlan {
                Button { add(to: plan) } label: {
                    HStack(spacing: JPSpace.xs) {
                        if plans.busy != nil { ProgressView().tint(WebTheme.accentText) }
                        Text(Self.addTitle(day: day))
                    }
                    .jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .disabled(plans.busy != nil || !canAdd(plan))
                .opacity(plans.busy == nil && canAdd(plan) ? 1 : TripStyle.disabledOpacity)
                .accessibilityIdentifier("tripAdd.add")
                .jpBottomBar()
            }
        }
    }

    private func planRow(_ plan: TripPlan) -> some View {
        let on = plan.planId == planId
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            Button {
                planId = plan.planId
                day = suggestedDay(plan)
            } label: {
                HStack(spacing: JPSpace.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title)
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.foreground)
                            .lineLimit(2)
                        Text(TripStyle.planLine(start: plan.startDate, end: plan.endDate, places: plan.itemCount,
                                                finished: false))
                            .font(JPFont.meta)
                            .foregroundStyle(WebTheme.text3)
                    }
                    Spacer(minLength: JPSpace.xs)
                    TripPickMark(isOn: on)
                }
                .frame(minHeight: TripStyle.pickRowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("tripAdd.plan")

            if on {
                dayChips(plan)
                    .padding(.bottom, JPSpace.s)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    private func dayChips(_ plan: TripPlan) -> some View {
        let already = TripPlanEdit.dayContaining(place.item, in: plan.days)
        return VStack(alignment: .leading, spacing: JPSpace.xxs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JPSpace.xs) {
                    ForEach(Array(plan.days.enumerated()), id: \.offset) { di, d in
                        chip(L("\(di + 1) 日目", "Day \(di + 1)"), on: day == di,
                             disabled: d.items.count >= TripPlanService.itemsPerDayMax) { day = di }
                    }
                    if plan.days.count < TripPlanService.daysMax {
                        chip(L("日を足す", "New day"), symbol: "plus", on: day == nil, disabled: false) { day = nil }
                    }
                }
            }
            if let already {
                Text(L("このプランの \(already + 1) 日目にもう入っています", "Already on day \(already + 1) of this trip"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
        }
    }

    private func chip(_ title: String, symbol: String? = nil, on: Bool, disabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true) }
                if let symbol, !on { Image(systemName: symbol).font(.caption.weight(.bold)).accessibilityHidden(true) }
                Text(title).font(JPFont.footnote.weight(.semibold))
            }
            .foregroundStyle(on ? WebTheme.accentText : WebTheme.foreground)
            .padding(.horizontal, JPSpace.s)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(on ? WebTheme.accentFill : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : WebTheme.line, lineWidth: JPStroke.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? TripStyle.disabledOpacity : 1)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var newPlanRow: some View {
        Button {
            createdPlanId = nil
            showCreate = true
        } label: {
            HStack(spacing: JPSpace.s) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("新しい旅行プラン", "New trip"))
                        .font(JPFont.bodyEmphasis)
                    Text(L("\(place.name)から作る", "Start with \(place.name)"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(WebTheme.accent)
            .frame(minHeight: TripStyle.pickRowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tripAdd.new")
    }

    // MARK: - 決める・入れる

    private func chooseDefault() {
        guard !chose, plans.status == .loaded else { return }
        chose = true
        let today = TripPlanText.ymd(pickedIn: .current, Date())
        guard let plan = TripPlanEdit.defaultPlan(plans.plans, today: today) else { return }
        planId = plan.planId
        day = suggestedDay(plan)
    }

    private func suggestedDay(_ plan: TripPlan) -> Int? {
        let places: [DerivedSpot.Place] = []
        return TripPlanEdit.suggestedDay(plan.days, coords: place.coords) { item in
            TripDraft.place(for: item, index: index, places: places).coords
        }
    }

    private func canAdd(_ plan: TripPlan) -> Bool {
        TripPlanEdit.adding(place.item, to: plan.days, day: day) != nil
    }

    /// 🔴 **送る前に読み直し、いまのサーバーの日程に足す**（2026-11-10 確かめ役の指摘・札 #521）。
    /// 開いたときの日程に足して丸ごと送ると、その後に日程の画面が自動保存した直しを上書きして消していた
    private func add(to plan: TripPlan) {
        guard canAdd(plan) else { return }
        let chosenDay = day
        error = nil
        Task {
            guard let fresh = await plans.fetchFresh(environment: environment) else {
                error = L("通信を確かめて、もう一度お試しください。", "Check your connection and try again.")
                return
            }
            guard let next = Self.daysAdding(place.item, to: plan.planId, day: chosenDay, in: fresh) else {
                // 開いている間に日程が変わり、選んだ日に入れられなくなった（日が消えた・いっぱい）
                error = L("このプランの日程が変わりました。日を選び直してください。",
                          "This trip changed. Please choose a day again.")
                await plans.load(environment: environment)
                return
            }
            let dayNumber = (chosenDay ?? (next.count - 1)) + 1
            var patch = TripPlanService.Patch()
            patch.days = next
            guard await plans.update(plan.planId, patch, environment: environment) else {
                error = plans.errorMessage ?? L("入れられませんでした。もう一度お試しください。", "Couldn't add it. Please try again.")
                plans.clearError()
                return
            }
            // 開いている日程の画面に知らせる（版をそろえる・`TripPlanChanges`）
            TripPlanChanges.shared.changed(plan.planId)
            await wish()
            let title = plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title
            toasts.show(L("「\(title)」の \(dayNumber) 日目に入れました", "Added to day \(dayNumber) of “\(title)”"))
            dismiss()
        }
    }

    /// 入れた場所は「行きたい」にも入れる（もう入っていれば何もしない）
    private func wish() async {
        guard !wishlist.contains(wishKey) else { return }
        let outcome = await WishlistSync.set(wishKey, wanted: true, store: wishlist, service: environment.savedSpots)
        if case .failed = outcome, let notice = WishlistSync.notice(for: outcome) {
            toasts.show(notice.text, kind: notice.kind)
        }
    }

    /// いまのサーバーの日程（`fresh`）に足した日程。プランが無い・入れられない日なら nil
    nonisolated static func daysAdding(_ item: TripItem, to planId: String, day: Int?, in fresh: [TripPlan]) -> [TripDay]? {
        guard let current = fresh.first(where: { $0.planId == planId }) else { return nil }
        return TripPlanEdit.adding(item, to: current.days, day: day)
    }

    /// 「2 日目に入れる」（nil は新しい日）
    nonisolated static func addTitle(day: Int?) -> String {
        guard let day else { return L("新しい日に入れる", "Add as a new day") }
        return L("\(day + 1) 日目に入れる", "Add to day \(day + 1)")
    }
}

/// 頁の「旅行プランに入れる」を押したときに開くシート（撮影スポット・撮影地・写真の詳細で同じ形）
extension View {
    func tripAddSheet(_ target: Binding<TripAddTarget?>) -> some View {
        sheet(item: target) { t in
            NavigationStack {
                TripAddSheet(place: t.place, wishKey: t.wishKey)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct TripAddTarget: Identifiable {
    let place: TripDraft.Place
    let wishKey: String
    var id: String { place.id }
}
