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
    @StateObject private var model = TripPlansModel()
    @State private var newTitle = ""
    /// 作った直後に、そのプランを開く（Web の `onCreate` と同じ）
    @State private var openedPlanId: String?
    @State private var showOpened = false

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
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(TripPlanText.listSubtitle(count: model.status == .loaded ? model.plans.count : nil))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)

                if model.status == .failed {
                    failedNotice
                }
                // **サーバーの言い分をそのまま出す**（上限の 403 と混雑を潰さない）
                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, 4)
                }

                // 作る口は、一覧が取れていなくても出す——新しく作るのに一覧は要らない
                createRow

                planList
            }
            .padding(16)
        }
        .task { await model.load(environment: environment) }
        .refreshable { await model.load(environment: environment) }
        .navigationDestination(isPresented: $showOpened) {
            if let planId = openedPlanId {
                TripPlanDetailView(planId: planId, model: model)
            }
        }
    }

    private var failedNotice: some View {
        HStack(spacing: 8) {
            Text(L("旅行プランを読み込めませんでした。", "Couldn't load your trips."))
                .font(.footnote)
                .foregroundStyle(WebTheme.danger)
            Button(L("再試行", "Retry")) {
                Task { await model.load(environment: environment) }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WebTheme.foreground)
            .webTappable()
        }
        .padding(.horizontal, 4)
    }

    private var trimmedTitle: String { newTitle.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var createRow: some View {
        HStack(spacing: 8) {
            TextField(L("例: 冬のフィンランド", "e.g. Finland in winter"), text: $newTitle)
                .font(.body)
                .foregroundStyle(WebTheme.foreground)
                .submitLabel(.done)
                .onSubmit { create() }
                .accessibilityLabel(L("旅行プランのタイトル", "Trip title"))
                .padding(.horizontal, 14)
                .frame(minHeight: WebTheme.minTapTarget)
                .background(WebTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            // **写真の無い画面の主ボタン1つ＝真鍮の塗り＋墨の字**（デザインシステムの決まり）
            Button(L("作る", "New")) { create() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.accentText)
                .padding(.horizontal, 16)
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                .background(WebTheme.accentFill, in: Capsule())
                .opacity(canCreate ? 1 : 0.5)
                .disabled(!canCreate)
                .buttonStyle(.plain)
        }
    }

    private var canCreate: Bool { !trimmedTitle.isEmpty && model.busy == nil }

    private func create() {
        guard canCreate else { return }
        let title = String(trimmedTitle.prefix(TripPlanService.titleMax))
        Task {
            if let made = await model.create(title: title, environment: environment) {
                newTitle = ""
                openedPlanId = made.planId
                showOpened = true
            }
        }
    }

    @ViewBuilder
    private var planList: some View {
        switch model.status {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
        case .failed:
            // 上の1行が事情と再試行を出しているので、ここは黙る
            EmptyView()
        case .loaded:
            if model.plans.isEmpty {
                VStack(spacing: 8) {
                    Text(L("旅行プランはまだありません。", "No trips yet."))
                        .font(.callout)
                        .foregroundStyle(WebTheme.muted2)
                    Text(L("上でタイトルを付けて作ると、行きたい場所を並べられます。",
                           "Name a trip above, then add places you want to go."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.plans) { plan in
                        NavigationLink {
                            TripPlanDetailView(planId: plan.planId, model: model)
                        } label: {
                            card(plan)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trips.plan")
                    }
                }
            }
        }
    }

    private func card(_ plan: TripPlan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                if let period = TripPlanText.period(start: plan.startDate, end: plan.endDate) {
                    Text(period)
                        .font(JPFont.mono(11))
                        .foregroundStyle(WebTheme.muted)
                }
            }
            Spacer(minLength: 8)
            Text(TripPlanText.placeCount(plan.itemCount))
                .font(JPFont.mono(13))
                .foregroundStyle(WebTheme.faint)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
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

    func load(environment: AppEnvironment) async {
        // 取り直している間も、取れていた一覧は出したまま（引き下げ更新で消さない）
        if status != .loaded { status = .loading }
        do {
            plans = try await environment.trips.list()
            status = .loaded
        } catch {
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
    func create(title: String, environment: AppEnvironment) async -> TripPlan? {
        let before = Set(plans.map(\.planId))
        guard let list = await write("new", L("作成に失敗しました", "Couldn't create"), {
            try await environment.trips.create(title: title)
        }) else { return nil }
        return list.first { !before.contains($0.planId) }
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
        busy = key
        errorMessage = nil
        defer { busy = nil }
        do {
            let list = try await call()
            plans = list
            status = .loaded
            return list
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? fallback
            return nil
        }
    }
}
