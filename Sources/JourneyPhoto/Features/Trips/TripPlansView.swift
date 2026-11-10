import SwiftUI

/// 旅行プランの一覧（キャンバス「17 旅行プラン」／ Web の `/trips`）。
///
/// 行きたい場所を「いつ・どの順で回るか」に並べる。**本人だけ**の画面で、
/// 入口はマイページ（Web も本人のプロフィールにだけ出す）。
///
/// **「まだ」「聞けなかった」「0件」を混ぜない**（Web の `TripsClient` と同じ）。
/// 通信に失敗しただけの人に「まだプランはありません」と言い切らない。
struct TripPlansView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    /// 一覧が読めないとき（圏外）に、端末に保存した旅を出す（板 72c）
    @EnvironmentObject private var offline: OfflineTripStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var wishlist: WishlistStore
    @StateObject private var model = TripPlansModel()
    /// 作った直後に、そのプランを開く（Web の `onCreate` と同じ）
    @State private var openedPlanId: String?
    @State private var showOpened = false
    /// 旅行プランを作る流れ（全画面の板・`TripCreateView`・2026-11-10 札 #521）
    @State private var showCreate = false
    /// 作る流れで保存したプラン。**板が閉じ切ってから開く**（閉じている途中に積むと捨てられる）
    @State private var createdPlanId: String?
    /// 自分の旅の一冊（帰着済みの札の「旅の一冊を見る」・板 TripPlans F30）。読めなければ空（札に出さないだけ）
    @State private var myTrips: [TripBook.Trip] = []

    var body: some View {
        Group {
            if auth.isResolving {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.userId == nil {
                SignInView(reason: L("旅行プランを作るにはログインしてください", "Sign in to plan a trip."))
            } else {
                content
            }
        }
        .webScreen()
        .navigationTitle(L("旅行プラン", "Trip plans"))
        .navigationBarTitleDisplayMode(.inline)
        // 題は画面の中の明朝の大見出しに出す（v2 の板 TripPlans）。上のバーには出さない
        // （同じ語を2度並べない）。戻るの「‹ 旅行プラン」には `navigationTitle` が要るので残す
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
        .onChange(of: auth.userId) { _, _ in model.forget() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 大見出し（v2 の板 TripPlans: 明朝の題 → 件数）。件数は**聞けたときだけ**（`listSubtitle`）
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(L("旅行プラン", "Trip plans"))
                        .font(JPFont.screenTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.subtitle(plans: model.status == .loaded ? model.plans.count : nil,
                                       wishlist: wishlist.spotIds.count))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                }

                if model.status == .failed {
                    failedNotice
                }
                // **サーバーの言い分をそのまま出す**（上限の 403 と混雑を潰さない）
                if let error = model.errorMessage {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                }

                // 作る口は、一覧が取れていなくても出す——新しく作るのに一覧は要らない。
                // **主ボタンは1つ**（2026-11-10 札 #521: 題から・写真から・地図からの3つの作りを1つの流れに）
                createButton

                planList
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd)
        }
        .task { await model.load(environment: environment) }
        .task(id: auth.userId) { await loadMyTrips() }
        .refreshable { await model.load(environment: environment) }
        // 一覧が取れたら、プランが無くなった旅の途中のもの（保存を止めたあとにプランを消した）を片づける
        .onChange(of: model.status == .loaded ? model.plans.map(\.planId) : nil) { _, ids in
            if let ids { offline.removeOrphanPartials(keeping: Set(ids)) }
        }
        .navigationDestination(isPresented: $showOpened) {
            if let planId = openedPlanId {
                TripPlanDetailView(planId: planId, model: model)
            }
        }
        .fullScreenCover(isPresented: $showCreate, onDismiss: {
            // 板の中の保存は一覧の失敗の文を消す（`write` が始めに消す）。保存せずに閉じた回は
            // 取り直して、一覧の本当の状態をもう一度出す。**保存してプランを開く回は取り直さない**
            guard let planId = createdPlanId else {
                Task { await model.load(environment: environment) }
                return
            }
            createdPlanId = nil
            openedPlanId = planId
            showOpened = true
        }) {
            TripCreateView(plans: model) { planId in
                guard showCreate else { return }
                createdPlanId = planId
                showCreate = false
            }
        }
    }

    /// 「旅行プランを作る」（写真の無い画面の主ボタン＝真鍮の塗り＋墨・1画面に1つ）
    private var createButton: some View {
        Button {
            createdPlanId = nil
            showCreate = true
        } label: {
            Label(L("旅行プランを作る", "Plan a trip"), systemImage: "plus")
                .jpPillButton(.main(onPhoto: false))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("行きたい場所をまとめて選び、日付を入れると、日ごとに並べた下書きができます",
                             "Pick places, set dates, and get a day-by-day draft."))
        .accessibilityIdentifier("trips.create")
    }

    /// 自分の旅の一冊（マイページの「旅の記録」と同じ棚・`TripBook.shelfTrips`）
    private func loadMyTrips() async {
        guard auth.userId != nil, let photos = try? await environment.photos.myPhotos() else {
            if auth.userId == nil { myTrips = [] }
            return
        }
        myTrips = TripBook.shelfTrips(from: photos)
    }

    /// 「旅行プラン 2 件 · 行きたい場所 12 か所」。行きたい場所が無ければ件数だけ
    nonisolated static func subtitle(plans: Int?, wishlist: Int) -> String {
        let head = TripPlanText.listSubtitle(count: plans)
        guard plans != nil, wishlist > 0 else { return head }
        return L("\(head) · 行きたい場所 \(wishlist) か所", "\(head) · \(Plural.count(wishlist, "saved place"))")
    }

    /// 読めなかった（v2 Components 06: 灰の印 → 何が起きたか → 「もう一度」）。**赤にしない**——
    /// 読めないのは人の誤りではない
    private var failedNotice: some View {
        ErrorBanner(message: L("旅行プランを読み込めませんでした。", "Couldn't load your trips."),
                    isBusy: model.status == .loading) {
            Task { await model.load(environment: environment) }
        }
    }

    @ViewBuilder
    private var planList: some View {
        switch model.status {
        case .loading:
            JPLoadingState(kind: .rows)
        case .failed:
            // 上の1行が事情と再試行を出している。**端末に保存した旅があれば、それを出す**
            // （圏外で一覧が読めなくても、保存した旅は開ける・板 72c）
            if !offline.saved.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    JPEyebrowLine(L("電波なしで使える旅 · \(offline.saved.count) 件",
                                    "Offline trips · \(offline.saved.count)"))
                    LazyVStack(spacing: 10) {
                        ForEach(offline.saved) { manifest in
                            NavigationLink {
                                OfflineTripView(manifest: manifest, preview: !connectivity.isOffline)
                            } label: {
                                offlineCard(manifest)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        case .loaded:
            if model.plans.isEmpty {
                // 空の状態（v2 Components 06: 明朝の見出し → どうすれば埋まるか）
                EmptyState(title: L("旅行プランはまだありません", "No trips yet"),
                           message: L("「旅行プランを作る」で行きたい場所をまとめて選ぶと、日ごとに並べた下書きができます。",
                                      "Tap Plan a trip, pick places, and get a day-by-day draft."))
                    .padding(.top, JPSpace.xl)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.plans) { plan in
                        planCard(plan)
                    }
                }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WebTheme.text3)
            .accessibilityHidden(true)
    }

    /// 端末に保存した旅の札（一覧の札と同じ面）
    private func offlineCard(_ manifest: OfflineTripManifest) -> some View {
        HStack(spacing: 14) {
            OfflinePhoneIcon(saved: true, side: 22)
                .frame(width: TripStyle.planThumb, height: TripStyle.planThumb)
                .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
            VStack(alignment: .leading, spacing: 3) {
                Text(manifest.title.isEmpty ? L("無題のプラン", "Untitled trip") : manifest.title)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                Text(OfflineTripText.savedRow(manifest))
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
            }
            Spacer(minLength: JPSpace.xs)
            chevron
        }
        .tripPlanCard()
        .accessibilityElement(children: .combine)
    }

    /// プランの札。**帰着済みで、期間の重なる旅の一冊があれば「旅の一冊を見る」を札の下に**（板 TripPlans F30）
    @ViewBuilder
    private func planCard(_ plan: TripPlan) -> some View {
        let today = TripPlanText.ymd(pickedIn: .current, Date())
        let finished = TripStyle.isFinished(end: plan.endDate ?? plan.startDate, today: today)
        let book = finished ? TripPlanText.book(for: plan, in: myTrips) : nil
        let link = NavigationLink {
            TripPlanDetailView(planId: plan.planId, model: model)
        } label: {
            card(plan, face: book == nil)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trips.plan")
        if let book {
            VStack(spacing: 0) {
                link
                NavigationLink {
                    TripBookView(trip: book, isMine: true)
                } label: {
                    HStack(spacing: 6) {
                        Text(L("旅の一冊を見る", "See the trip book"))
                            .font(JPFont.bodyEmphasis)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .overlay(alignment: .top) {
                        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                    }
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trips.plan.book")
            }
            .jpCardFace()
        } else {
            link
        }
    }

    /// プランの札（v2 の板 TripPlans: 左に 64 の枠・眉「出発まで 3 日」（近いときだけ）・明朝の題・
    /// 「期間 · N か所」。帰ってきたプランは題を灰にして「帰着済み」）
    private func card(_ plan: TripPlan, face: Bool = true) -> some View {
        let today = TripPlanText.ymd(pickedIn: .current, Date())
        let finished = TripStyle.isFinished(end: plan.endDate ?? plan.startDate, today: today)
        let eyebrow = finished ? nil : TripStyle.departureEyebrow(start: plan.startDate, today: today)
        return HStack(spacing: 14) {
            // 旗の印（板の写真の無いプランの枠）。プランの一覧は場所の写真を持たない
            Image(systemName: "flag")
                .font(.title3)
                .foregroundStyle(finished ? WebTheme.text3 : WebTheme.accent)
                .frame(width: TripStyle.planThumb, height: TripStyle.planThumb)
                .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow {
                    Text(eyebrow)
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                }
                Text(plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(finished ? WebTheme.text2 : WebTheme.foreground)
                    .lineLimit(2)
                Text(TripStyle.planLine(start: plan.startDate, end: plan.endDate,
                                        places: plan.itemCount, finished: finished))
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
            }
            Spacer(minLength: JPSpace.xs)
            chevron
        }
        .tripPlanCard(face: face)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// 旅行プランの札の面（v2 の板 TripPlans の `.pl`: surface-1・白 8% の縁・角 16・内側 14）
    /// `face: false` は札の面を外側に任せる（「旅の一冊を見る」と同じ札に収めるとき）
    @ViewBuilder
    func tripPlanCard(face: Bool = true) -> some View {
        let inner = self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        if face {
            inner.jpCardFace().contentShape(Rectangle())
        } else {
            inner.contentShape(Rectangle())
        }
    }
}

/// 一覧と書き込み。**書き込みの応答（書いたあとの一覧）をそのまま映す**
/// ——自分で足し引きすると、断られた回に嘘の状態が残る（Web の `useTripPlans`）。
@MainActor
final class TripPlansModel: ObservableObject {

    enum Status: Equatable { case loading, loaded, failed }

    @Published private(set) var plans: [TripPlan] = []
    @Published private(set) var status: Status = .loading
    /// いま書き込み中のプラン（新規は `"new"`）。**連打を止める**
    @Published private(set) var busy: String?
    /// 直近の失敗の言い分（サーバーの文言）。成功すると消える
    @Published var errorMessage: String?

    func plan(_ planId: String) -> TripPlan? { plans.first { $0.planId == planId } }

    /// 人が替わった回数。**走っている書き込みの答えを、次の人の画面に書かない**
    private var era = 0

    /// 人が替わった。**前の人のプランを残さない**（`AlbumsViewModel.forget` と同じ理由）。
    /// 走っている読み込みの答えは数で、書き込みの答えは `era` で捨てる
    func forget() {
        era += 1
        writes += 1
        loadRuns += 1
        settledRun = loadRuns
        plans = []
        status = .loading
        busy = nil
        errorMessage = nil
    }

    /// 前の画面の失敗の文を消す（**一覧と詳細で1つを共有している**ので、
    /// プランAの失敗をプランBを開いたときに出さない）
    func clearError() { errorMessage = nil }

    /// 書き込みが成功した回数。**書き込みより前に始めた読み込みの答えは捨てる**
    /// ——作る・直す・消すの間に始めた引き下げ更新が後から返ると、書き込みの応答で
    /// 映した一覧を古い姿で上書きし、作ったプランが消えていた（直した日程も戻った）。
    /// 読み込み同士は、**自分より後に始めた読み込みが既に成功していたときだけ**捨てる
    /// （後から始めて先に失敗した方のせいで、先に始めた方の成功を捨てない。
    ///  後から始めて先に成功した方の後で、古い方の失敗の赤い行を出さない）
    private var writes = 0
    private var loadRuns = 0
    /// 成功を書いた読み込みのうち、いちばん後に始めたもの
    private var settledRun = 0

    func load(environment: AppEnvironment) async {
        let started = writes
        loadRuns += 1
        let run = loadRuns
        // 取り直している間も、取れていた一覧は出したまま（引き下げ更新で消さない）
        if status != .loaded { status = .loading }
        do {
            let list = try await environment.trips.list()
            guard started == writes, run > settledRun else { return }
            settledRun = run
            plans = list
            status = .loaded
            // **取れたら前の失敗の文を消す。** 残すと、成功したあとも赤い行が出続ける
            errorMessage = nil
        } catch {
            // **打ち切りは失敗ではない。** 画面を離れると `.task` が打ち切られる
            // （`APIClient` は `CancellationError` で上げてくる）
            if Task.isCancelled { return }
            guard started == writes, run > settledRun else { return }
            if status == .loaded {
                // 取れていた一覧は残し、取り直せなかったことだけ言う
                errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
            } else {
                // 「読み込めませんでした。再試行」の1行が出るので、赤い行を重ねない
                status = .failed
            }
        }
    }

    /// 作る。**作れたプラン**を返す（増えた ID で見る——応答の先頭とは限らない、とは考えない）
    func create(title: String, days: [TripDay]? = nil, startDate: String? = nil, endDate: String? = nil,
                environment: AppEnvironment) async -> TripPlan? {
        let before = Set(plans.map(\.planId))
        guard let list = await write("new", L("作成に失敗しました", "Couldn't create"), {
            try await environment.trips.create(title: title, days: days, startDate: startDate, endDate: endDate)
        }) else { return nil }
        return Self.created(in: list, before: before, title: title)
    }

    /// 作ったプランを応答から選ぶ。
    ///
    /// 🔴 **増えた ID だけでは決めない。** 最初の読み込みに失敗していると
    /// 手元の一覧は空で、既にある別のプランまで「増えた」に入り、それが
    /// 開いていた（別の端末で作った分が手元に無いときも同じ）。
    /// 増えた中から**題が同じもの**を、その中で**いちばん新しいもの**を採る
    static func created(in list: [TripPlan], before: Set<String>, title: String) -> TripPlan? {
        let fresh = list.filter { !before.contains($0.planId) }
        let sameTitle = fresh.filter { $0.title == title }
        let pool = sameTitle.isEmpty ? fresh : sameTitle
        return pool.max { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
    }

    /// 送る前の読み直し（自動保存・`TripAutosave.conflicted`）。**一覧には映さない**——映すと、
    /// 日程の画面が手元の下書きをサーバーの姿で合わせ直してしまう。読めなければ nil
    func fetchFresh(environment: AppEnvironment) async -> [TripPlan]? {
        try? await environment.trips.list()
    }

    func update(_ planId: String, _ patch: TripPlanService.Patch, environment: AppEnvironment) async -> Bool {
        await write(planId, L("保存に失敗しました", "Couldn't save"), {
            try await environment.trips.update(planId: planId, patch)
        }) != nil
    }

    func remove(_ planId: String, environment: AppEnvironment) async -> Bool {
        await write(planId, L("削除に失敗しました", "Couldn't delete"), {
            try await environment.trips.delete(planId: planId)
        }) != nil
    }

    private func write(_ key: String, _ fallback: String,
                       _ call: () async throws -> [TripPlan]) async -> [TripPlan]? {
        guard busy == nil else { return nil }
        let myEra = era
        busy = key
        errorMessage = nil
        // 人が替わった後に返った前の人の書き込みは、次の人の「送っている最中」を外さない
        defer { if myEra == era { busy = nil } }
        do {
            let list = try await call()
            // **人が替わっていたら何も書かない**（前の人のプランを次の人の画面に出さず、
            // `writes` を進めて次の人の読み込みを捨てさせもしない）
            guard myEra == era else { return nil }
            // 成功した回だけ進める（断られた回に最初の読み込みを捨てると「読み込み中」のまま残る）
            writes += 1
            plans = list
            status = .loaded
            return list
        } catch {
            guard myEra == era else { return nil }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? fallback
            return nil
        }
    }
}
