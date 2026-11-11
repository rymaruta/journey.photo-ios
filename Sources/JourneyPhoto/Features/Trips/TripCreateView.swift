import SwiftUI

/// 旅行プランを**まとめて作る**流れ（2026-11-10 判断・札 #521・案 A の第 1 段）。
///
/// 「旅行プランを作る」を押したら、①行き先をまとめて選ぶ → ②日付（決めないなら日数）→ ③下書き → 保存。
/// 空のプランから始めない。日ごとの割り振りと日の中の並びは下書きで出す（`TripDraft`）。
///
/// - ① 行き先: 「行きたい場所」のタブ（撮影スポットと撮影地・押すと選ぶ／押し直すと外れる）と
///   「写真から選ぶ」のタブ（`TripPickerView`・払った場所も同じ下書きに入る）
/// - ② 日付: 暦で出発と帰着を押す。「日付を決めずに、日数だけ選ぶ」もできる（日付は後から入れられる）
/// - ③ 下書き: 題（行き先から案を出す・直せる）・並べた理由の1行・日ごとの日の出と日の入り・重なりの1行
/// - 保存は1回（題・日程・日付を1回で送る今の口 `TripPlansModel.create`）。サーバー・プランの形は変えない
///
/// 押す回数（5 か所 · 1 泊 2 日）: 今 23 回 → 12 回（作る 1・選ぶ 5・次へ 1・月送り 1・日 2・下書きを見る 1・保存 1）。
/// 入口は一覧の「旅行プランを作る」・行きたい場所の地図（②から始める）・どの頁からも「旅行プランに入れる」の「新しい旅行プラン」
struct TripCreateView: View {

    @ObservedObject var plans: TripPlansModel
    /// 保存できた（作ったプランの ID）。呼び手が閉じて日程の画面を開く
    let onSaved: (String) -> Void

    @StateObject private var model: TripCreateModel
    @State private var showDates: Bool
    @State private var showDraft = false

    /// - `initial`: はじめから選んだ場所（地図から・撮影スポットの頁から）
    /// - `startAtDates`: ②から始める（①に戻れば選んだ場所が並んでいる）
    init(plans: TripPlansModel, initial: [TripDraft.Place] = [], startAtDates: Bool = false,
         onSaved: @escaping (String) -> Void) {
        self.plans = plans
        self.onSaved = onSaved
        _model = StateObject(wrappedValue: TripCreateModel(initial: initial))
        _showDates = State(initialValue: startAtDates && !initial.isEmpty)
    }

    var body: some View {
        NavigationStack {
            TripCreatePickStep(model: model, next: { showDates = true })
                .navigationDestination(isPresented: $showDates) {
                    TripCreateDatesStep(model: model, next: { showDraft = true })
                        .navigationDestination(isPresented: $showDraft) {
                            TripCreateDraftStep(model: model, plans: plans, onSaved: onSaved)
                        }
                }
        }
        .interactiveDismissDisabled(model.saving)
        // 全画面の板の上では、アプリの下の知らせ（`RootView`）が隠れるので、ここにも置く
        .overlay(alignment: .bottom) {
            ToastOverlay().padding(.bottom, 84)
        }
    }
}

/// 作る流れの状態。**段の画面ではなくここに持つ**（戻って開き直しても、選んだ場所・日付・題を消さない）
@MainActor
final class TripCreateModel: ObservableObject {

    enum Tab: Hashable { case wishlist, photos }

    /// 選んだ場所の鍵（選んだ順。最初に選んだ場所の地域から日を始める）
    @Published private(set) var selected: [String] = []
    /// 鍵 → 場所（行きたい場所・写真から選んだ場所・はじめから渡された場所）
    @Published private(set) var known: [String: TripDraft.Place] = [:]
    @Published var tab: Tab = .wishlist
    @Published var start: String?
    @Published var end: String?
    /// 日付を決めずに日数だけ
    @Published var undated = false
    @Published var dayCount = 1
    @Published var title = ""
    @Published var error: String?
    /// 保存の最中（閉じさせない・二度押しさせない）
    @Published var saving = false

    /// 写真から選ぶ（札の山と決めごと）。タブを替えても残す
    let picker = TripPickerModel()

    init(initial: [TripDraft.Place] = []) {
        for place in initial { add(place) }
        dayCount = TripDraft.suggestedDayCount(places: initial.count)
        // 写真から「行きたい」にした札は下書きに入り、「ひとつ戻す」で外れる
        picker.onPickedChange = { [weak self] in
            Task { @MainActor in self?.syncPicker() }
        }
    }

    var picked: [TripDraft.Place] { selected.compactMap { known[$0] } }
    var count: Int { selected.count }
    var isFull: Bool { selected.count >= TripPicker.pickMax }

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    /// 選ぶ・外す。上限（`TripPicker.pickMax`）を越えては選ばない。選べたか外せたら true
    @discardableResult
    func toggle(_ place: TripDraft.Place) -> Bool {
        if selected.contains(place.id) {
            remove(place.id)
            return true
        }
        guard !isFull else { return false }
        add(place)
        return true
    }

    func add(_ place: TripDraft.Place) {
        known[place.id] = place
        guard !selected.contains(place.id), !isFull else { return }
        selected.append(place.id)
    }

    /// 外す（「行きたい」からは外さない）。写真から選んだ場所は札の決めごとからも外す
    func remove(_ id: String) {
        selected.removeAll { $0 == id }
        if case .spot(let spotId, _)? = known[id]?.item,
           picker.picked.contains(where: { $0.spotId == spotId }) {
            picker.remove(spotId)
        }
    }

    /// 札の「行きたい」を下書きに映す（足した札は足し、戻した札は外す）
    private var pickerIds: [String] = []
    private func syncPicker() {
        let now = picker.picked.map { TripDraft.place(spot: $0) }
        let ids = now.map(\.id)
        for place in now where !pickerIds.contains(place.id) { add(place) }
        for gone in pickerIds where !ids.contains(gone) { selected.removeAll { $0 == gone } }
        pickerIds = ids
    }

    /// 割り振る日数。日付を決めたら出発〜帰着（帰着がまだなら出発の1日）、決めないなら選んだ日数
    var plannedDayCount: Int? {
        undated ? dayCount : TripPicker.dayCount(start: start, end: end ?? start)
    }

    var days: [[TripDraft.Place]] { TripDraft.plan(picked, dayCount: plannedDayCount) }
    var suggestedTitle: String { TripPicker.defaultTitle(TripPicker.grouped(picked)) }

    /// 日付の段の「下書きを見る」を押せるか
    var datesReady: Bool { !selected.isEmpty && (undated || start != nil) }

    /// 送る日付。日付を決めないときは送らない。帰着がまだなら出発と同じ日（日帰り）
    var sendDates: (start: String?, end: String?) {
        undated ? (nil, nil) : (start, end ?? start)
    }

    /// 保存する（題・日程・日付を1回で）。作れたらプランの ID、作れなければ nil（`error` に理由）。
    /// 下書きの段と、DM から作る流れの日付の段（2026-11-12）が同じここを通る
    func save(plans: TripPlansModel, environment: AppEnvironment) async -> String? {
        guard !picked.isEmpty, !saving, plans.busy == nil else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sendTitle = TripPlanService.titleToSend(trimmed.isEmpty ? suggestedTitle : trimmed)
        // **押した時点の日程を送る**
        let sendDays = TripDraft.tripDays(days)
        let dates = sendDates
        saving = true
        error = nil
        defer { saving = false }
        // **題・日程・日付を1回で作る**（作ってから日程を別に送ると、2回目で落ちた回に空のプランが残る）
        guard let made = await plans.create(title: sendTitle, days: sendDays,
                                            startDate: dates.start, endDate: dates.end,
                                            environment: environment) else {
            error = plans.errorMessage
                ?? L("旅行プランを作れませんでした。もう一度お試しください。", "Couldn't create the trip. Please try again.")
            // 文はこの画面で出す（一覧の model に残すと、板を閉じたあと一覧の上に赤い行が残る）
            plans.clearError()
            return nil
        }
        return made.planId
    }

    /// 休みの組を押した（出発と帰着の2日をまとめて入れる・2026-11-12 資料 2a）
    func choose(_ pair: TripHolidays.Pair) {
        undated = false
        start = pair.start
        end = pair.end
    }
}

// MARK: - ① 行き先を選ぶ

struct TripCreatePickStep: View {

    @ObservedObject var model: TripCreateModel
    let next: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter

    @State private var index: [OfficialSpot] = []
    @State private var places: [DerivedSpot.Place] = []
    @State private var loaded = false
    @State private var failed = false

    private var choices: [TripDraft.Place] {
        TripPlanText.choices(wishlistKeys: wishlist.spotIds, places: places, index: index)
            .map { TripDraft.place(for: $0.item, index: index, places: places) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                Text(L("行き先を選ぶ", "Choose places"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
                TripCreateTabs(tab: $model.tab, wishlistCount: loaded ? choices.count : nil)
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.s)

            switch model.tab {
            case .wishlist:
                ScrollView { wishlistList.padding(.horizontal, JPSpace.gutter).padding(.bottom, JPSpace.xl) }
            case .photos:
                TripPickerView(model: model.picker)
            }
        }
        .webScreen()
        .navigationTitle(L("旅行プランを作る", "New trip"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SheetCloseButton().disabled(model.saving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: next) {
                Text(Self.nextTitle(count: model.count))
                    .jpPillButton(.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .disabled(model.count == 0)
            .opacity(model.count == 0 ? TripStyle.disabledOpacity : 1)
            .accessibilityIdentifier("tripCreate.next")
            .jpBottomBar()
        }
        .task {
            guard !loaded else { return }
            let fetchedIndex = try? await environment.spots.fetchIndex()
            let fetchedPhotos = try? await environment.gallery.fetchPhotos()
            if let fetchedIndex { index = fetchedIndex }
            if let fetchedPhotos { places = DerivedSpot.allMergedBySlug(in: hidden.snapshot.visible(fetchedPhotos)) }
            failed = fetchedIndex == nil || fetchedPhotos == nil
            loaded = true
        }
    }

    @ViewBuilder
    private var wishlistList: some View {
        let rows = choices
        if !loaded {
            JPLoadingState(kind: .rows)
        } else if rows.isEmpty && failed {
            ErrorBanner(message: L("行きたい場所を読み込めませんでした。通信を確かめて、開き直してください",
                                   "Couldn't load your saved places. Check your connection and try again."))
        } else if rows.isEmpty {
            EmptyState(title: L("行きたい場所はまだありません", "No saved places yet"),
                       message: L("写真を見て選ぶと、そのまま旅行プランの下書きになります",
                                  "Pick places by photo and they go straight into your trip."),
                       actionTitle: L("写真から選ぶ", "Pick by photo"),
                       action: { model.tab = .photos })
                .padding(.top, JPSpace.l)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("いくつでも選べます。押し直すと外れます", "Pick as many as you like. Tap again to deselect."))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.bottom, JPSpace.xs)
                ForEach(rows) { place in
                    TripChoiceRow(place: place, isOn: model.isSelected(place.id),
                                  locked: model.isFull && !model.isSelected(place.id)) {
                        if !model.toggle(place) {
                            toasts.show(L("選べるのは \(TripPicker.pickMax) か所までです",
                                          "You can pick up to \(TripPicker.pickMax) places."), kind: .failure)
                        }
                    }
                }
            }
        }
    }

    /// 「5 か所で次へ」（0 のときは「次へ」）
    nonisolated static func nextTitle(count: Int) -> String {
        guard count > 0 else { return L("次へ", "Next") }
        return L("\(count) か所で次へ", count == 1 ? "Next with 1 place" : "Next with \(count) places")
    }
}

/// 「行きたい場所 12 ｜ 写真から選ぶ」（選んでいるタブは真鍮の字と下線・owner の好み「選んでいるタブ＝真鍮」）
struct TripCreateTabs: View {
    @Binding var tab: TripCreateModel.Tab
    let wishlistCount: Int?

    var body: some View {
        HStack(spacing: JPSpace.l) {
            item(.wishlist, L("行きたい場所", "Saved places"), count: wishlistCount)
            item(.photos, L("写真から選ぶ", "By photo"), count: nil)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    private func item(_ value: TripCreateModel.Tab, _ title: String, count: Int?) -> some View {
        let on = tab == value
        return Button { tab = value } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(on ? JPFont.bodyEmphasis : JPFont.body)
                if let count {
                    Text("\(count)").font(JPFont.meta)
                }
            }
            .foregroundStyle(on ? WebTheme.accent : WebTheme.text2)
            .frame(minHeight: WebTheme.minTapTarget)
            .overlay(alignment: .bottom) {
                if on { Rectangle().fill(WebTheme.accent).frame(height: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(value == .wishlist ? "tripCreate.tab.wishlist" : "tripCreate.tab.photos")
    }
}

/// 選ぶ行（板 TripPlanPick: 48 の枠の印 → 名前（撮影スポットは明朝）・県と市 → 選んだ印）
struct TripChoiceRow: View {
    let place: TripDraft.Place
    let isOn: Bool
    let locked: Bool
    /// 2行目を差し替える（DM の会話から作る下書きの「撮影スポット · 送られた写真から」・2026-11-12）。nil は県と市
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: JPSpace.s) {
                Image(systemName: place.isSpot ? "mappin.and.ellipse" : "map")
                    .font(.system(size: 17))
                    .foregroundStyle(WebTheme.text2)
                    .frame(width: TripStyle.pickThumb, height: TripStyle.pickThumb)
                    .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.s))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(place.isSpot ? JPFont.rowTitle : JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    } else if let region = place.regionLabel {
                        Text(region)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    } else if !place.isSpot {
                        Text(L("撮影地", "Photo location"))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    }
                }
                Spacer(minLength: JPSpace.xs)
                TripPickMark(isOn: isOn)
            }
            .padding(.vertical, JPSpace.xs)
            .frame(minHeight: TripStyle.pickRowMinHeight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
        .accessibilityLabel([place.name, detail ?? place.regionLabel].compactMap { $0 }.joined(separator: L("・", ", ")))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn ? L("押すと外します", "Tap to deselect") : L("押すと選びます", "Tap to select"))
        .accessibilityIdentifier("tripCreate.choice")
    }
}

// MARK: - ② 日付

struct TripCreateDatesStep: View {

    @ObservedObject var model: TripCreateModel
    let next: () -> Void
    /// 下の主ボタンの字。nil は「下書きを見る」。DM の会話から作る流れは「旅行プランを作る」で、
    /// この段で保存まで進む（2026-11-12 判断・資料 2a の押す回数 4 回: 帯 → 日付を選ぶ → 休みの組 → 作る）
    var finishTitle: String? = nil

    @State private var month: (year: Int, month: Int) = TripCreateDatesStep.initialMonth(nil)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                Text(L("いつ行く？", "When are you going?"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)

                if model.undated {
                    undatedCard
                } else {
                    TripCalendar(month: $month, start: model.start, end: model.end,
                                 today: TripPlanText.ymd(pickedIn: .current, Date())) { day in
                        let next = TripDraft.tap(start: model.start, end: model.end, day: day)
                        model.start = next.start
                        model.end = next.end
                    }
                    holidayPairs
                    summary
                }

                Button {
                    model.undated.toggle()
                    if model.undated { model.dayCount = TripDraft.suggestedDayCount(places: model.count) }
                } label: {
                    Text(model.undated ? L("暦で日付を選ぶ", "Pick dates on the calendar")
                                       : L("日付を決めずに、日数だけ選ぶ", "Choose the number of days instead"))
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripCreate.undated")
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .navigationTitle(L("旅行プランを作る", "New trip"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { month = Self.initialMonth(model.start) }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: JPSpace.xxs) {
                if let error = model.error, finishTitle != nil {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tripCreate.error")
                }
                Button(action: next) {
                    HStack(spacing: JPSpace.xs) {
                        if model.saving { ProgressView().tint(WebTheme.accentText) }
                        Text(finishTitle ?? L("下書きを見る", "See the draft"))
                    }
                    .jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .disabled(!canGo)
                .opacity(canGo ? 1 : TripStyle.disabledOpacity)
                .accessibilityIdentifier(finishTitle == nil ? "tripCreate.toDraft" : "tripCreate.finish")
            }
            .jpBottomBar()
        }
        // 保存の最中は戻らせない（DM から作る流れはこの段で保存する）
        .navigationBarBackButtonHidden(model.saving)
    }

    private var canGo: Bool { model.datesReady && !model.saving }

    /// 休みの組（2026-11-12 資料 2a）。押すと出発と帰着の2日がまとめて入る。
    /// 選んでいる組は真鍮の字と縁（owner の好み「選んでいるもの＝真鍮」）、ほかは outline の縁に白の字
    @ViewBuilder
    private var holidayPairs: some View {
        let pairs = TripHolidays.pairs(from: TripPlanText.ymd(pickedIn: .current, Date()))
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                Text(L("休みの組を押すと2日がまとめて入ります", "Tap a weekend to fill in both days"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                HStack(spacing: JPSpace.xs) {
                    ForEach(pairs) { pair in
                        let on = model.start == pair.start && model.end == pair.end
                        Button {
                            model.choose(pair)
                            month = Self.initialMonth(pair.start)
                        } label: {
                            Text(pair.label)
                                .font(JPFont.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(on ? WebTheme.accent : WebTheme.foreground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, JPSpace.s)
                                .frame(minHeight: WebTheme.minTapTarget)
                                .overlay(Capsule().strokeBorder(on ? WebTheme.accent : WebTheme.outline,
                                                                lineWidth: JPStroke.hairline))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(TripHolidays.spoken(pair))
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("tripCreate.holiday.\(pair.start)")
                    }
                }
            }
        }
    }

    /// 期間の1行と、割り振りの1行（選んでいないときは押し方）
    private var summary: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            if let line = TripDraft.rangeLine(start: model.start, end: model.end) {
                Text(line)
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.foreground)
                Text(TripDraft.allocationNote(places: model.count, days: model.plannedDayCount ?? 1))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("出発の日を押し、続けて帰着の日を押してください", "Tap the day you leave, then the day you return."))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
            }
        }
        .padding(JPSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jpCardFace()
        .accessibilityElement(children: .combine)
    }

    private var undatedCard: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Stepper(value: $model.dayCount, in: 1...TripPlanService.daysMax) {
                Text(L("\(model.dayCount) 日", Plural.count(model.dayCount, "day")))
                    .font(JPFont.figureLarge)
                    .foregroundStyle(WebTheme.foreground)
            }
            Text(TripDraft.allocationNote(places: model.count, days: model.dayCount))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JPSpace.m)
        .jpCardFace()
    }

    nonisolated static func initialMonth(_ start: String?) -> (year: Int, month: Int) {
        if let (y, m, _) = TakenDay.ymd(start) { return (y, m) }
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
        return (c.year ?? 2026, c.month ?? 1)
    }
}

/// 1か月の暦（板の案: 日〜土・選んだ出発と帰着は真鍮の塗りに墨・間は真鍮の薄い地）。
/// 押せる日は 44pt。今日より前の日は押せない
struct TripCalendar: View {
    @Binding var month: (year: Int, month: Int)
    let start: String?
    let end: String?
    /// 今日（`YYYY-MM-DD`）。これより前は押せない
    let today: String
    let tap: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: JPSpace.xs) {
            HStack {
                arrow("chevron.left", L("前の月", "Previous month"), delta: -1)
                Spacer(minLength: 0)
                Text(L("\(String(month.year))年\(month.month)月", "\(monthTitle)"))
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                arrow("chevron.right", L("次の月", "Next month"), delta: 1)
                    .accessibilityIdentifier("tripCreate.nextMonth")
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, w in
                    Text(w)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .frame(height: 24)
                        .accessibilityHidden(true)
                }
                ForEach(Array(TripDraft.monthGrid(year: month.year, month: month.month).enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: WebTheme.minTapTarget).accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(JPSpace.s)
        .jpCardFace()
    }

    private var monthTitle: String {
        let names = ["January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December"]
        return "\(names[max(0, min(11, month.month - 1))]) \(month.year)"
    }

    private var weekdays: [String] {
        [L("日", "S"), L("月", "M"), L("火", "T"), L("水", "W"), L("木", "T"), L("金", "F"), L("土", "S")]
    }

    private func arrow(_ symbol: String, _ label: String, delta: Int) -> some View {
        Button {
            month = TripDraft.shiftMonth(year: month.year, month: month.month, by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(WebTheme.text2)
                .webTappable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func cell(_ day: String) -> some View {
        let isEnd = day == start || day == (end ?? start)
        let inside = start.map { s in day > s && day < (end ?? s) } ?? false
        let past = day < today
        let number = Int(day.suffix(2)) ?? 0
        return Button { tap(day) } label: {
            Text("\(number)")
                .font(JPFont.number(JPTypeScale.body, weight: isEnd ? .bold : .regular))
                .foregroundStyle(isEnd ? WebTheme.accentText : WebTheme.foreground)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .background {
                    if isEnd {
                        Circle().fill(WebTheme.accentFill).frame(width: 40, height: 40)
                    } else if inside {
                        Rectangle().fill(WebTheme.accent.opacity(0.18))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(past)
        .opacity(past ? TripStyle.disabledOpacity : 1)
        .accessibilityLabel(TakenDay.label(day) ?? day)
        .accessibilityAddTraits(isEnd || inside ? .isSelected : [])
        .accessibilityIdentifier("tripCreate.day.\(day)")
    }
}

// MARK: - ③ 下書き

struct TripCreateDraftStep: View {

    @ObservedObject var model: TripCreateModel
    @ObservedObject var plans: TripPlansModel
    let onSaved: (String) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @State private var index: [OfficialSpot] = []

    var body: some View {
        let days = model.days
        let dates = model.sendDates
        let numbers = TripStyle.stopNumbers(days.map(\.count))
        return ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    Text(L("下書き", "Draft"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    // 題（行き先から案を出す・直せる）
                    TextField(model.suggestedTitle, text: $model.title)
                        .font(JPFont.screenTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .submitLabel(.done)
                        .onChange(of: model.title) { old, new in
                            let kept = PostLimits.limited(old: old, new: new, limit: TripPlanService.titleMax)
                            if kept != new { model.title = kept }
                        }
                        .accessibilityLabel(L("旅行プランのタイトル", "Trip title"))
                        .accessibilityIdentifier("tripCreate.title")
                    // 並べた理由（計算していないものは「計算していません」）
                    Text(TripDraft.explanation)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = model.error {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .accessibilityIdentifier("tripCreate.error")
                }

                ForEach(Array(days.enumerated()), id: \.offset) { di, day in
                    daySection(di, day, start: dates.start, end: dates.end,
                               numbers: numbers.indices.contains(di) ? numbers[di] : [])
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .navigationTitle(L("旅行プランを作る", "New trip"))
        .navigationBarTitleDisplayMode(.inline)
        // 保存の最中は戻らせない（戻ってもう一度保存すると、作る途中のプランと重なる）
        .navigationBarBackButtonHidden(model.saving)
        .task {
            // 日の出・日の入りの時刻帯（行の `timeZone`）。取れなければ国の表で決める（`SunTimes.timeZone`）
            guard index.isEmpty else { return }
            let fetched = try? await environment.spots.fetchIndex()
            if let fetched { index = fetched }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: JPSpace.xxs) {
                Button(action: save) {
                    HStack(spacing: JPSpace.xs) {
                        if model.saving { ProgressView().tint(WebTheme.accentText) }
                        Text(L("旅行プランを保存", "Save trip"))
                    }
                    .jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : TripStyle.disabledOpacity)
                .accessibilityIdentifier("tripCreate.save")
                Text(L("保存したあとも並べ替えられます", "You can rearrange it after saving."))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .jpBottomBar()
        }
    }

    private func daySection(_ di: Int, _ day: [TripDraft.Place], start: String?, end: String?,
                            numbers: [Int]) -> some View {
        let ymd = TripPlanText.dayDate(index: di, day: TripDay(), start: start, end: end)
        let spots = day.compactMap { place -> OfficialSpot? in
            guard case .spot(let id, _) = place.item else { return nil }
            return index.first { $0.spotId == id }
        }
        let sun = TripDraft.sun(ymd: ymd, spots: spots)
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPEyebrowLine(TripPlanText.dayHeading(index: di, day: TripDay(), start: start, end: end)
                .replacingOccurrences(of: "・", with: " · "))
            if let sun, let line = TripSunText.line(sun) {
                TripDayNote(text: [line, TripPicker.regionLabel(of: day)].compactMap { $0 }.joined(separator: " · "),
                            symbol: "sun.max")
            }
            if let overlap = TripDraft.overlapNote(day.map(\.times)) {
                TripDayNote(text: overlap, symbol: "exclamationmark.circle", strong: true)
            }
            VStack(spacing: 0) {
                if day.isEmpty {
                    Text(L("まだ何も入っていません。保存したあと、日程の画面で入れられます。",
                           "Nothing planned. You can add places after saving."))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                        .frame(maxWidth: .infinity, minHeight: JPHeight.row, alignment: .leading)
                }
                ForEach(Array(day.enumerated()), id: \.element.id) { ii, place in
                    if ii > 0 { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
                    row(place, number: numbers.indices.contains(ii) ? numbers[ii] : ii + 1)
                }
            }
            .padding(.horizontal, JPSpace.m)
            .jpCardFace()
        }
    }

    private func row(_ place: TripDraft.Place, number: Int) -> some View {
        HStack(spacing: JPSpace.xs) {
            TripStopLabel(number: number, name: place.name, isSpot: place.isSpot,
                          timeChip: TripDraft.timeChip(place.times))
            if let photo = spotPhoto(place) {
                Color.clear
                    .frame(width: 44, height: 44)
                    // 44pt の枠なので縮小版（読めなければ元の画像・`SpotThumbImage`）
                    .overlay(SpotThumbImage(image: photo))
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs + 2))
                    .accessibilityHidden(true)
            }
            // **この下書きから外すだけ**（「行きたい」には残る）。保存の間は外させない
            Button {
                guard !model.saving else { return }
                model.remove(place.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text3)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .disabled(model.saving)
            .accessibilityLabel(L("「\(place.name)」をこの下書きから外す", "Remove \(place.name) from this draft"))
        }
    }

    private func spotPhoto(_ place: TripDraft.Place) -> SpotImage? {
        guard case .spot(let id, _) = place.item else { return nil }
        return index.first { $0.spotId == id }?.photo
    }

    private var canSave: Bool { !model.picked.isEmpty && !model.saving && plans.busy == nil }

    private func save() {
        guard canSave else { return }
        Task {
            if let made = await model.save(plans: plans, environment: environment) { onSaved(made) }
        }
    }
}
