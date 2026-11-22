import SwiftUI

// MARK: - 一覧の上の「AI で作る」（札 #621・磨き直しの案「打つより押す」）

/// 旅行プランの一覧のいちばん上。札を1回押すと、すぐ日程の画面が開いて1日目から埋まる。
/// 札は行きたい場所と季節の案内から決まった手順で出す（AI は使わない・回数0）。
/// 「自分で頼む」は行き先・日数・好みの3つの札を埋めた形で開く。「＋ 自分で選んで作る」は今の作る流れ
struct TripAIEntrySection: View {
    let suggestions: [TripAISuggestion]
    let usage: TripAIService.Usage?
    let start: (TripAIAsk) -> Void
    let ask: () -> Void
    let pickYourself: () -> Void
    /// 札の下に、日程をサーバーへ送ることの知らせを出すか（`AskServerNotice.shows`・2026-11-22 判断）
    var serverNotice: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPEyebrowLine(L("AI で作る", "Make with AI"))
            if let usage, usage.remaining <= TripAILimits.warnAt, !(usage.tier != "free" && !usage.countsDevice) {
                Text(TripAIText.remainingLine(remaining: usage.remaining, resetsOn: usage.resetsOn))
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, JPSpace.s)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                    .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("tripAI.remaining")
            }
            ForEach(suggestions) { s in
                Button { start(s.ask) } label: { card(s) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(s.title)、\(s.subtitle)。AI で作る", "\(s.title), \(s.subtitle). Make with AI"))
                    .accessibilityIdentifier("tripAI.suggestion")
            }
            // 札を押すとすぐ組み始める（確かめを挟まない）ので、送る前に見える札の下に1回だけ出す
            if serverNotice, !suggestions.isEmpty { AskServerNoticeText(id: "tripAI.entry.serverNotice") }
            Button(action: ask) {
                Label(L("自分で頼む", "Ask in your own words"), systemImage: "sparkles")
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tripAI.ask")
            Button(action: pickYourself) {
                Label(L("自分で選んで作る", "Pick places yourself"), systemImage: "plus")
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trips.create")
        }
    }

    /// 札（写真3枚の束・題は明朝 17・下に1行・右に真鍮の「作る」）
    private func card(_ s: TripAISuggestion) -> some View {
        HStack(spacing: JPSpace.s) {
            photos(s.photoSpots)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(JPFont.rowTitle).foregroundStyle(WebTheme.foreground)
                Text(s.subtitle).font(JPFont.caption).foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(L("作る", "Make"))
                .font(JPFont.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.accentText)
                .padding(.horizontal, JPSpace.s)
                .frame(minHeight: 36)
                .background(WebTheme.accentFill, in: Capsule())
        }
        .padding(10)
        .frame(minHeight: 72)
        .jpCardFace()
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.l))
    }

    private func photos(_ spots: [OfficialSpot]) -> some View {
        let side: CGFloat = 52
        return HStack(spacing: 1) {
            thumb(spots.first).frame(width: side / 2, height: side)
            VStack(spacing: 1) {
                thumb(spots.dropFirst().first).frame(width: side / 2, height: side / 2)
                thumb(spots.dropFirst(2).first).frame(width: side / 2, height: side / 2)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func thumb(_ spot: OfficialSpot?) -> some View {
        if let image = spot?.photo {
            SpotThumbImage(image: image)
        } else {
            Rectangle().fill(WebTheme.surface3)
        }
    }
}

// MARK: - 自分で頼む

/// 行き先・日数・好みの3つの札（埋まった形で開く）＋足したいときだけの1行。読めなかった札は真鍮で光らせ、1回で選べる
struct TripAIAskSheet: View {
    @State var ask: TripAIAsk
    let placeChoices: [(label: String, prefecture: String)]
    /// 打った文をサーバーへ送る人か（`AskServerNotice.shows`。呼ぶ側が同じ条件で決める）
    let serverNotice: Bool
    let start: (TripAIAsk) -> Void
    let index: [OfficialSpot]
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Slot?

    enum Slot { case place, days, preference }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JPSpace.s) {
                    HStack(spacing: JPSpace.xs) {
                        slot(.place, L("行き先", "Place"), ask.hasPlace ? ask.place : nil)
                        slot(.days, L("日数", "Days"), ask.days.map(TripAIAsk.daysLabel))
                        slot(.preference, L("好み", "Mood"), ask.preference ?? L("なし", "None"))
                    }
                    if let editing { chooser(editing) }
                    HStack(spacing: JPSpace.xs) {
                        JPTextField(TripAIText.placeholder, text: $ask.extra)
                            // 打った時点で 200 字に切る（`TripAILimits.maxRequest`）
                            .onChange(of: ask.extra) { _, new in ask.extra = TripAILimits.clipped(new) }
                            .submitLabel(.done)
                            .onSubmit(readExtra)
                            .accessibilityIdentifier("tripAI.extra")
                    }
                    .jpFieldBox()
                    // 2026-11-22 判断: 「どこで組むか」の1行（iPhone・雲の印、置き場の地域）はやめ、サーバーへ送る人にだけ
                    // 旅行プラン用の知らせ（`AskText.tripServerNotice`）を、送る前（「この内容で作る」の上）に出す
                    if serverNotice { AskServerNoticeText(id: "tripAI.serverNotice") }
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.top, JPSpace.xs)
            }
            .webScreen()
            .navigationTitle(L("自分で頼む", "Ask in your own words"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { SheetCloseButton() } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    readExtra()
                    guard ask.isComplete else {
                        editing = ask.hasPlace ? .days : .place
                        return
                    }
                    dismiss()
                    start(ask)
                } label: {
                    Text(L("この内容で作る", "Make it")).jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripAI.askStart")
                .jpBottomBar()
            }
            .onAppear { if !ask.hasPlace { editing = .place } else if ask.days == nil { editing = .days } }
        }
    }

    /// 足した1行から、行き先・日数・好みを読み直す（読めた札だけ替える）
    private func readExtra() {
        let read = TripAIAsk.reading(ask.extra, spots: index)
        if read.hasPlace { ask.place = read.place; ask.prefectures = read.prefectures; ask.cities = read.cities; ask.mustSpotIds = [] }
        if let d = read.days { ask.days = d }
        if let p = read.preference { ask.preference = p }
    }

    private func slot(_ s: Slot, _ title: String, _ value: String?) -> some View {
        let need = value == nil
        return Button { editing = editing == s ? nil : s } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(JPFont.eyebrow).foregroundStyle(WebTheme.text3)
                Text(value ?? L("選んでください", "Choose"))
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(need ? WebTheme.accent : WebTheme.foreground)
                    .lineLimit(1)
            }
            .padding(.horizontal, JPSpace.s)
            .frame(minWidth: 84, minHeight: 48, alignment: .leading)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(need ? WebTheme.accent : WebTheme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)、\(value ?? L("選んでください", "Choose"))")
        .accessibilityIdentifier("tripAI.slot.\(s)")
    }

    private func chooser(_ s: Slot) -> some View {
        let options: [(String, () -> Void)]
        switch s {
        case .place:
            options = placeChoices.map { c in (c.label, {
                ask.place = c.label
                ask.prefectures = [c.prefecture]
                ask.cities = []
                ask.mustSpotIds = []
                editing = ask.days == nil ? .days : nil
            }) }
        case .days:
            options = TripAIAsk.dayChoices.map { d in (TripAIAsk.daysLabel(d), { ask.days = d; editing = nil }) }
        case .preference:
            options = [(L("なし", "None"), { ask.preference = nil; editing = nil })]
                + TripAIPreference.words.map { w in (w, { ask.preference = w; editing = nil }) }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JPSpace.xs) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                    Button(action: o.1) {
                        Text(o.0)
                            .jpOutlineButton(.inline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tripAI.choice")
                }
            }
        }
    }
}

// MARK: - 作っている日程の画面（待たせない）

/// 押したらすぐ開く日程の画面。1日目から順に、できた日の札を埋める（まだの日は骨組み）。
/// 画面を離れても作り続け、できたら保存して上の帯で知らせる（`TripAIJobs`）。保存できたら今の日程の画面に替わる
struct TripAIBuildingView: View {
    @ObservedObject var job: TripAIJobs.Job
    @ObservedObject var runner: TripAIRunner
    @ObservedObject var plans: TripPlansModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var loadedPlanId: String?
    @State private var showPro = false

    init(job: TripAIJobs.Job, plans: TripPlansModel) {
        self.job = job
        self.runner = job.runner
        self.plans = plans
    }

    var body: some View {
        Group {
            if case .saved(let planId) = job.state, loadedPlanId == planId, plans.plan(planId) != nil {
                TripPlanDetailView(planId: planId, model: plans)
            } else {
                building
            }
        }
        .onAppear { TripAIJobs.shared.watching = job.id }
        .onDisappear { if TripAIJobs.shared.watching == job.id { TripAIJobs.shared.watching = nil } }
        .task(id: job.state) {
            guard case .saved(let planId) = job.state else { return }
            await plans.load(environment: environment)
            TripAIJobs.shared.markSeen(planId)
            loadedPlanId = planId
        }
        .fullScreenCover(isPresented: $showPro) { PaywallView(origin: .tripAI) }
    }

    private var building: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(job.title)
                        .font(JPFont.screenTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    // 作れなかったときは下の札が言うので、ここでは言わない（同じ言葉を2回出さない）
                    if !isFailed {
                        Text(statusLine)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text2)
                            .accessibilityIdentifier("tripAI.status")
                    }
                }
                if case .failed(let failure) = job.state {
                    ErrorBanner(title: L("作れませんでした", "Couldn't make it"),
                                message: Self.failureMessage(failure),
                                retry: { TripAIJobs.shared.retry(job) })
                        .accessibilityIdentifier("tripAI.failed")
                } else {
                    days
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd)
        }
        .webScreen()
        .navigationTitle(L("旅行プラン", "Trip plans"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // 保存に入ったら「やめる」を隠す（保存したプランを残さないため・止められた回は消す）
            if job.state == .building, !job.saving {
                Button {
                    TripAIJobs.shared.cancel(job)
                    dismiss()
                } label: {
                    Text(L("やめる", "Stop")).jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripAI.stop")
                .jpBottomBar()
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = job.state { return true }
        return false
    }

    /// 何をしているかの一言（実際の手順どおり）
    private var statusLine: String {
        switch job.state {
        case .failed: return L("作れませんでした", "Couldn't make it")
        case .saved: return L("保存しました", "Saved")
        case .building:
            switch runner.step {
            case .collecting, .ordering:
                return L("\(job.ask.place)の観光スポットから選んでいます", "Choosing from spots in \(job.ask.place)")
            case .measuring:
                return L("移動の目安を測っています", "Checking travel times")
            case .done:
                return L("保存しています", "Saving")
            }
        }
    }

    private var days: some View {
        let ready = runner.readyDays
        let total = max(runner.expectedDays, ready.count, 1)
        return ForEach(0..<total, id: \.self) { d in
            VStack(alignment: .leading, spacing: 0) {
                JPEyebrowLine(L("\(d + 1)日目", "Day \(d + 1)"))
                    .padding(.bottom, JPSpace.xxs)
                if d < ready.count {
                    ForEach(Array(ready[d].enumerated()), id: \.element.spotId) { i, spot in
                        row(number: ready.prefix(d).map(\.count).reduce(0, +) + i + 1, spot: spot)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                } else {
                    JPLoadingState(kind: .rows)
                        .accessibilityLabel(L("\(d + 1)日目を作っています", "Making day \(d + 1)"))
                }
            }
            .animation(.easeOut(duration: 0.3), value: ready.count)
        }
    }

    private func row(number: Int, spot: OfficialSpot) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(JPFont.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(WebTheme.accent)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: 1.4))
            Group {
                if let image = spot.photo { SpotThumbImage(image: image) } else { Rectangle().fill(WebTheme.surface3) }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name).font(JPFont.rowTitle).foregroundStyle(WebTheme.foreground)
                if let hint = spot.timeKeys.compactMap(SpotBodyText.timeLabel).first {
                    Text(hint).font(JPFont.caption).foregroundStyle(WebTheme.text2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
        .accessibilityIdentifier("tripAI.readyRow")
    }

    nonisolated static func failureMessage(_ f: TripAIJobs.Failure) -> String {
        switch f {
        case .offline: return L("電波が届いていません。つながったら「もう一度」を押してください", "No signal. Tap Retry once you're online.")
        case .noCandidates: return L("行き先の観光スポットが見つかりませんでした", "No spots were found for this place.")
        case .save(let m): return m
        }
    }
}

// MARK: - 上の帯（できた・作れなかった）

enum TripAIBannerLayout {
    /// 上の札（ナビゲーションバー 44 と少しの間）の下に出す。戻るのガラスの丸をふさがない（65u で 8 秒かぶさっていた）
    static let belowNavigationBar: CGFloat = 52
}

/// アプリのいちばん上の帯（板 Components 06 の知らせの形: ガラス・上から 0.24 秒）。通知の許可は求めない
struct TripAIBannerView: View {
    @ObservedObject var jobs = TripAIJobs.shared

    var body: some View {
        if let b = jobs.banner {
            Button { jobs.tapBanner() } label: {
                HStack(spacing: JPSpace.xs) {
                    // ガラスの地の上なので白（真鍮は黒地の上だけ・2026-10-02 の地図の札と同じ決まり）。失敗は危険の色
                    Circle().fill(b.failed ? WebTheme.danger : WebTheme.foreground).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(b.text)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text(b.action)
                        .jpOutlineButton(.inline)
                }
                .padding(.leading, JPSpace.s)
                .padding(.trailing, 6)
                .frame(minHeight: 52)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WebTheme.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, JPSpace.s)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("tripAI.banner")
            .task(id: b.id) {
                // 8秒で消す（押せば開く・やり直す）
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if jobs.banner?.id == b.id { withAnimation(.easeOut(duration: 0.24)) { jobs.banner = nil } }
            }
        }
    }
}

/// 帯から開く日程（一覧を読んでから詳細を出す。`TripPlanOpenView` と同じ形・日程のタブ）
struct TripAIOpenView: View {
    let planId: String
    @StateObject private var model = TripPlansModel()
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if model.plan(planId) != nil {
                TripPlanDetailView(planId: planId, model: model)
            } else if model.status == .failed {
                ErrorBanner(title: Labels.Common.loadFailed, message: L("通信を確かめて、もう一度お試しください。", "Check your connection and try again.")) {
                    Task { await model.load(environment: environment) }
                }
            } else if model.status == .loaded {
                ErrorBanner(message: L("プランが見つかりません", "Trip not found"))
            } else {
                JPLoadingState(kind: .rows).padding(.horizontal, JPSpace.gutter)
            }
        }
        .webScreen()
        .task { await model.load(environment: environment) }
        .toolbar { ToolbarItem(placement: .cancellationAction) { SheetCloseButton() } }
    }
}
