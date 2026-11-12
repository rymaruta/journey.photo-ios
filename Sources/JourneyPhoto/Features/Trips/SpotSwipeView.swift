import SwiftUI

/// 撮影スポットを払う全画面（2026-11-11 owner の要望「撮影スポットを払う」の①・`SpotSwipe`）。
///
/// 入口はホームの上の札の1枚目（`HomeTopCardView`）。中身は旅行プランの作る流れと同じ
/// `TripPickerView`（右＝行きたい・左＝見送る・ボタン・読み上げの操作・ひとつ戻す）。
/// 変わるのは次の3つだけ:
///
///  - **未ログインでも開ける。** 払った「行きたい」は `WishlistSync` → `WishlistStore`（未ログインは端末の
///    共有の鍵・ログインした回にその人へ引き継いで次の同期で送る）。新しい置き場は作らない
///  - **足元**: 「行きたい n か所」と、未ログインは「地図で見る」（押すとログインの板 `SignInSheet`）、
///    ログイン中は「旅行プランにする」（今の作る流れ `TripCreateView` に、この回に選んだ場所を渡す）
///  - **挟む札**: 5枚払って「行きたい」が1つ以上なら、山の中に1枚（`SpotSwipe.showsPause`）。
///    窓で止めない・左へ払えば続く・次は10枚あと。ログインの板を閉じたら、この画面のまま
///
/// 閉じるときに確かめは出さない（払った分は「行きたい」と `SpotSwipeProgress` に残り、次はホームの札から続き）。
struct SpotSwipeView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore

    /// 札の山と決めごと（この画面が生きている間）
    @StateObject private var model = TripPickerModel()
    /// 旅行プランにする流れ（`TripCreateView`）と、作ったプランの画面に渡す一覧
    @StateObject private var plans = TripPlansModel()
    /// 開いた時点で、前に払った札の鍵（山から除く）。開いている間は変えない（山を作り直さない）
    @State private var baseSeen: Set<String>
    /// 挟んだ札を払って続けたときの枚数（次に挟むのは10枚あと）
    @State private var continuedAt: Int?
    @State private var signIn: SignInRequest?
    @State private var showCreate = false
    /// 作る流れで保存したプラン。**板が閉じ切ってから積む**（`SavedSpotsMapView` と同じ）
    @State private var pendingPlanId: String?
    @State private var createdPlanId: String?

    private let progress: SpotSwipeProgress

    init(progress: SpotSwipeProgress = SpotSwipeProgress()) {
        self.progress = progress
        _baseSeen = State(initialValue: progress.seen)
    }

    private var signedIn: Bool { auth.userId != nil }

    var body: some View {
        NavigationStack {
            TripPickerView(model: model, alsoExclude: baseSeen, pause: pause,
                           finishedLine: L("また開くと、続きから払えます。", "Open again later to keep swiping."),
                           countsWants: true)
                .webScreen()
                .navigationTitle(L("行きたい場所を探す", "Find places to go"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
                }
                .safeAreaInset(edge: .bottom) { footer }
                .navigationDestination(item: $createdPlanId) { planId in
                    TripPlanDetailView(planId: planId, model: plans)
                }
        }
        .sheet(item: $signIn) { request in
            SignInSheet(reason: request.reason)
        }
        .fullScreenCover(isPresented: $showCreate, onDismiss: {
            guard let planId = pendingPlanId else { return }
            pendingPlanId = nil
            createdPlanId = planId
        }) {
            let initial = model.picked.map { TripDraft.place(spot: $0) }
            TripCreateView(plans: plans, initial: initial, startAtDates: !initial.isEmpty) { planId in
                pendingPlanId = planId
                showCreate = false
            }
        }
        // 全画面の上では、アプリの下の知らせ（`RootView`）が隠れるので、ここにも置く
        .overlay(alignment: .bottom) {
            ToastOverlay().padding(.bottom, 140)
        }
        .onAppear { progress.markStarted() }
        // 払った札を端末に残す（次に開いたとき、同じ札を出さない）。「ひとつ戻す」で戻した札は外す
        .onChange(of: model.decisions.map(\.spot.slug)) { old, new in
            if new.count > old.count {
                progress.addSeen(new.dropFirst(old.count).map { SavedSpotKey.official($0) })
            } else if let gone = old.last, new.count < old.count {
                progress.removeSeen(SavedSpotKey.official(gone))
            }
        }
        // 前に見た札を除いて山が空だった（全部見た）——最初から
        .onChange(of: model.restarted) { _, restarted in
            if restarted { progress.resetSeen() }
        }
    }

    /// 挟む札（出す回だけ）
    private var pause: TripPickerPause? {
        let wants = model.picked.count
        guard SpotSwipe.showsPause(decisions: model.decisions.count, wants: wants, continuedAt: continuedAt) else {
            return nil
        }
        return TripPickerPause(title: SpotSwipe.pauseTitle(wants: wants),
                               line: SpotSwipe.pauseLine(signedIn: signedIn),
                               actionTitle: SpotSwipe.actionTitle(signedIn: signedIn),
                               action: mainAction,
                               onContinue: { continuedAt = model.decisions.count })
    }

    /// 未ログインはログインの板、ログイン中は旅行プランにする流れ
    private func mainAction() {
        if signedIn {
            pendingPlanId = nil
            showCreate = true
        } else {
            signIn = SignInRequest(reason: SpotSwipe.signInReason)
        }
    }

    /// 足元: 「行きたい n か所」と「地図で見る」／「旅行プランにする」（黒地の上の文字ボタンなので真鍮）
    private var footer: some View {
        HStack(spacing: JPSpace.s) {
            Text(SpotSwipe.footerCount(wishlist.spotIds.count))
                .font(JPFont.footnote.monospacedDigit())
                .foregroundStyle(WebTheme.text2)
            Spacer(minLength: 0)
            Button(action: mainAction) {
                HStack(spacing: JPSpace.xxs) {
                    Text(SpotSwipe.footerAction(signedIn: signedIn))
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(auth.isResolving)
            .accessibilityIdentifier("spotSwipe.footerAction")
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.top, JPSpace.xs)
        .background(WebTheme.background)
    }
}
