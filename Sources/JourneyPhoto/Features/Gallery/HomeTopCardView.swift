import SwiftUI

/// ホームの上段の札（元は板 01・55「開く場面ごとに1枚」。いまは横にめくる並び）。
///
/// どれを出すかは `HomeTopCard.cards` が決める。**当たる札と「今日のテーマ」を
/// 横にめくる並び**にする（2026-09-28・owner「両方欲しい」）。縦に積まないのは、
/// 写真の一覧が札の数だけ下がるため（写真が主役）。次の札の端を少し見せて、
/// めくれることを分からせる。並びは 旅の札 → 季節の札（今月の見ごろ）→ 今日のテーマ → 1年前
/// （owner・2026-09-29）。季節の札はほぼ毎日当たるので、テーマは2枚目になる日が多い。
///
/// 旅行プランはログイン中だけ読む。**取れなかった回は空のまま**
/// （札が出ないだけで、ホームは壊さない）。
///
/// 読み直すのは、人が替わったとき・`reloadToken` が変わったとき（引き下げ更新・
/// 前面に戻った・メニューのシートを閉じた）・札から旅行プランを開いて戻ったときだけ。
/// **ホームに戻るたびには取りに行かない**（Lambda の同時実行はアカウント全体で10）
struct HomeTopCardView: View {

    /// 今日のテーマの札の背景に使う写真（`DailyThemeCard` に渡す）
    let themePhotos: [Photo]
    /// 自分の写真（一冊・1年前の判定と、今日のテーマの参加の判定に使う）
    let myPhotos: [Photo]
    /// 自分の写真をこの人のぶんとして読めたか（読めるまでは常連の並び・`HomeTopCard.Audience.of`）
    var myPhotosKnown = false
    /// 変わったら旅行プランを読み直す（`GalleryView` が渡す）
    var reloadToken: Int = 0
    /// 「いまの季節のスポット」の段の中身を、写真の一覧の中（`GalleryView`）へ渡す口（#417 ④・2026-10-30）。
    /// 段の中身（索引・今日の一問・日・上の札に出ている場所）はこの画面が持っているので、決めるのはここのまま。
    /// 描くのは「おすすめ」の写真の大1→2→2 の後ろ（`GalleryView.feedSection`）
    @Binding var seasonShelf: HomeSeasonShelfSlot?
    /// ホームの縦の送りで、この札が見えている上端より上へ流れ切っているか（2026-10-31 #426）。
    /// ホームの外側を `VStack` にしたので、流れ出ても `onDisappear` が来ない。main（外側が `LazyVStack`）では
    /// 流れ出ると `onDisappear`、戻ると `onAppear` が来ていた——その扱い（見えていない間は差し替えを後回し・戻ったら
    /// 前面の確定を待って `landHomeCards`）を、この値の変わり目で続ける
    var scrolledAway: Bool = false

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// 「行きたい」の鍵（「行きたい場所のこの季節」の札）
    @EnvironmentObject private var wishlist: WishlistStore
    /// 見頃のお知らせを予約してよいか（受け取る設定・端末の許可）
    @EnvironmentObject private var push: PushCenter
    @EnvironmentObject private var connectivity: Connectivity

    @State private var plans: [TripPlan] = []
    /// `plans` が誰のものか。**人が替わったら、取れるまで前の人のプランを出さない**
    @State private var plansOwner: String?
    /// 取り直した旅行プラン。**差し替えは見えている間だけ**（今日の一問の `pendingQuiz` と同じ形）
    /// ——旅行プランを開いたまま前面に戻ると、裏で札の並びが変わって開いていた画面が閉じていた
    @State private var pendingPlans: [TripPlan]?
    /// 最後に取れた条件（人と `reloadToken`）。同じなら取り直さない
    @State private var loadedKey: String?
    /// 札から旅行プランを開いた。戻ってきたら読み直す（そこで変えたかもしれない）
    @State private var reloadPlansOnReturn = false
    /// 札から開いた旅行プランから戻った回数。**読み込みの入口を `.task` 1つにまとめる**
    /// ——`onAppear` で別の `Task` を立てると、戻った瞬間の `.task` と2本同時に取りに行った
    @State private var returnReloads = 0
    @State private var openedBooks: Set<String> = []
    /// 「行きたい」の鍵の写し。**ホームに戻ったとき・人が替わったときだけ読み直す**——
    /// `wishlist.spotIds` をそのまま札に使うと、札から開いたスポットの画面で「行きたい」を
    /// 押した瞬間に札が差し替わり、押した元のリンクが裏で消えて**開いた画面が閉じる・
    /// 別のスポットに替わる**（一冊の札で踏んだのと同じ形・311fb3b のレビュー）
    @State private var wishedKeys: Set<String> = []
    /// 撮影スポットの索引（「この季節の撮影スポット」の札）。**取れなかった回は空のまま**
    /// ——札が出ないだけ。索引は静的な JSON（Lambda を通らない）で、サービスが
    /// 60秒の控えと端末の控えを持つ。**一度取れたら画面が生きている間は取り直さない**
    @State private var spots: [OfficialSpot] = []
    /// `spots` を書き換えた回数（段の中身を `seasonShelf` へ渡し直す合図。1,400件の配列を毎回比べない）
    @State private var spotsRevision = 0
    /// 重い計算の控え（写真の候補の並び・季節の段・詳細を取りに行く場所。材料が変わったときだけ計算し直す・
    /// `HomeTopCardMemo`・2026-11-14 札 #594）。中身を書き換えても画面は描き直さない（入れ物は同じ）
    @State private var memo = HomeTopCardMemo()
    /// 今日の一問（取れなかった日は nil のまま＝札を出さない）。サービスが日付ごとに覚えるので、
    /// 札から開いた画面は取り直さない
    @State private var quiz: DailyQuiz?
    /// 取り直した今日の一問。**差し替えはホームに戻ったとき（`onAppear`）だけ**——札の並びを
    /// 読み込みの最中に変えると、札から開いていた問題の画面が閉じる（押した元のリンクが消える・
    /// 一冊の札と同じ形・f3bcf5a のレビュー）
    @State private var pendingQuiz: DailyQuiz?
    /// ホームがいま見えているか（`onAppear`〜`onDisappear`）。**見えている間は札をその場で差し替え、
    /// 札から開いた画面が前に出ている間だけ後回しにする**——ホームのまま前面に戻る回（いちばん多い）は
    /// `onAppear` が来ないので、後回しだけにすると昨日の札が残り続けた（4621e39 のレビュー）
    @State private var isShown = false
    /// 戻るスワイプ途中の `onAppear` で札を差し替えない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?
    /// 今日の一問に答えたか（札の2行目を変える）。ホームに戻ったときに読み直す
    @State private var quizAnswered = false
    /// 今日の一問が決着したか（取れた・取れなかった）。**決着するまで「いまの季節のスポット」の段を出さない**
    /// （`HomeSpotShelf.visibleShelf`）。差し替えと同じく、見えている間に移す（`pendingQuizSettled`）
    @State private var quizSettled = false
    @State private var pendingQuizSettled = false
    /// 札と段の「今日」。🔴 **`Date()` をその場で読まない**（2026-10-18・スポットを日替わりにしたとき）。
    /// 札・段は毎日 0 時に替わるので、その場で読むと、札から開いた撮影スポットの画面が前に出ている間に
    /// 日をまたいだあと、何かで描き直した瞬間に押した元のリンクが消えて**開いていた画面が閉じる**
    /// （一冊の札・今日の一問と同じ形）。進めるのはホームが見えているときだけ（`advanceDay`）:
    /// 前面が確定したとき（`landHomeCards`）・アプリが前面に戻ったとき（`scenePhase` が `.active`）・
    /// 今日の一問を読み直したとき（早抜けの回も）・ホームのまま 0 時を過ぎたとき（`waitForNextDay`）。
    /// 🔴 **一問の読み直しだけに頼らない**——一問は日本時間で替わるので、日本の外では前面に戻っても
    /// 一問が「もう今日の分」で早抜けし、札が昨日のまま残った（96e499b7 のレビュー）
    @State private var cardsNow = Date()
    /// 撮影スポットを払う全画面（入口は札の1枚目・`SpotSwipeView`・2026-11-11）
    @State private var showSwipe = false
    /// 一度でも払う画面を開いたか（入口の一行を「行きたい n か所 · 続きから」にする）。閉じたときに読み直す
    @State private var swipeStarted = SpotSwipeProgress().started
    @Environment(\.scenePhase) private var scenePhase
    /// 端末の写真の一冊（①現像の「現像前の旅」を探す・2026-11-12 札 #543）。読むのは店（起動・ログインで後ろで読む）
    @ObservedObject private var deviceTrips = DeviceTripShelfStore.shared
    /// ①現像の送り終わりを見張る（1枚も上がらず札を開き直したら、札を出し直す・2026-11-12 確かめ役）
    @ObservedObject private var developPosting = DevelopPostCenter.shared
    /// 現像の画面を開いている旅
    @State private var developing: LibraryTrip?
    /// 現像の「題・公開範囲を変える」で選んだ写真（画面が閉じきってから投稿の画面へ渡す）
    @State private var developEdit: (trip: LibraryTrip, ids: [String], published: Bool)?
    /// 現像の控え（払った途中・閉じた旅）を読み直す合図（画面を閉じたら上げる）
    @State private var developRevision = 0
    /// 札から消した・抜けた旅行プランと、ホームに出さない印（2026-11-12・`TripPlanRemovalQueue`）
    @ObservedObject private var removal = TripPlanRemovalQueue.shared
    /// 「仲間全員から削除」の確かめ（他人に影響する操作だけ聞く・`HomeTripCardMenu`）
    @State private var confirmingEveryone: TripPlan?

    private let opened = OpenedTripBooks()
    private let developStore = DevelopProgressStore()

    var body: some View {
        let _ = PerfChangeLog.note(Self.self)   // なぜ評価し直したか（UI テストのときだけ・札 #594 の下調べ）
        let _ = PerfRecorder.shared.hit("home.topCard.body")   // 評価の回数（UI テストのときだけ・札 #594）
        // 「いまの季節のスポット」の段は、2026-10-03 から札の並びの下に置いていたが、**#417 ④（2026-10-30 owner 採用）で
        // 「おすすめ」の写真の大1→2→2 の後ろへ移した**（札の「AUTUMN SPOT」との2段続きが解け、切り替えが1画面目に上がる）。
        // 中身はここで決めて `seasonShelf` で渡す（札の並びは**1回だけ計算して**、札と段の両方に使う）
        let choices = self.choices
        content(choices)
            // UI テストのときだけ: 札の小さい行（出典）の幅と札の背を、札の外の見えない要素に出す（`TopCardProbe`・2026-11-14）
            .overlayPreferenceValue(TopCardProbeKey.self) { values in
                LayoutProbe(identifier: "home.topCard.probe", value: values.joined(separator: " | "))
            }
            .fullScreenCover(isPresented: $showSwipe, onDismiss: { swipeStarted = SpotSwipeProgress().started }) {
                SpotSwipeView()
            }
            .onChange(of: shelfKey(choices), initial: true) { _, _ in
                seasonShelf = visibleShelf(choices).map { HomeSeasonShelfSlot(shelf: $0, spots: spots) }
                PerfRecorder.shared.mark("home.seasonShelf.set")   // 起動直後の停止の切り分け（UI テストのときだけ・2026-11-07）
            }
            .task(id: "\(auth.userId ?? "-")#\(reloadToken)#\(returnReloads)") { await load() }
            .task { await loadSpots() }
            // 札・段・当日の行に出るスポットの詳細（写真・季節の文）。分けた置き場の索引だけの行のときだけ読む
            // （`SpotDetailNeeds`・2026-10-07）。重ねたら鍵が空になって止まる
            .task(id: SpotDetailNeeds.key(detailNeeds(choices))) { await loadDetails(choices) }
            // 日が進んだら今日の一問も取り直す（ホームのまま 0 時を過ぎた回）
            .task(id: "\(reloadToken)#\(cardsDay)") { await loadQuiz() }
            // ホームのまま 0 時を過ぎたら札と段を今日へ（`advanceDay`・壁時計で確かめ直す）
            .task(id: cardsDay) { await waitForNextDay() }
            // 前面に戻ったら、一問の読み直しを待たずに日を確かめる（ホームが見えているときだけ）
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isShown { advanceDay() }
                // 札から消した旅行プラン: 裏に回ったら6秒を待たずに送る・前面に戻ったら送れなかった分を送り直す
                if phase == .background { removal.commitNow() }
                if phase == .active { resumeRemovals() }
            }
            // 電波が戻ったら、圏外で送れなかった削除を送り直す
            .onChange(of: connectivity.isOffline) { _, offline in
                if !offline { resumeRemovals() }
            }
            .confirmationDialog(HomeTripCardMenu.confirmTitle(confirmingEveryone.map(planTitle) ?? ""),
                                isPresented: Binding(get: { confirmingEveryone != nil },
                                                     set: { if !$0 { confirmingEveryone = nil } }),
                                titleVisibility: .visible) {
                Button(HomeTripCardMenu.confirmButton, role: .destructive) {
                    if let plan = confirmingEveryone { remove(plan, .deleteForEveryone) }
                    confirmingEveryone = nil
                }
                Button(Labels.Common.cancel, role: .cancel) { confirmingEveryone = nil }
            } message: {
                Text(HomeTripCardMenu.confirmMessage)
            }
            // ホームに戻ってきたら、開いた一冊の印を読み直す（札を下げる）。
            // 札から旅行プランを開いていたら、プランも読み直す（`.task` の鍵を変えて）
            //
            // 🔴 **開いた印を読み直すのはここと人が替わったときだけ。** 読み込み（`load`）で
            // 読み直すと、一冊を読んでいる最中に前面へ戻った合図で札が差し替わり、
            // 押した元のリンクが消えて一冊の画面が閉じることがある
            .onAppear { cameIntoView() }
            .onDisappear { wentOutOfView() }
            // 送って流れ出た・戻った（`scrolledAway`）も、画面に出た・出なくなったと同じに扱う
            .onChange(of: scrolledAway) { _, away in
                if away { wentOutOfView() } else { cameIntoView() }
            }
            // 起動直後は許可の読み込みが索引より遅いことがある（初めは「許可なし」）。分かったときに入れ直す
            .onChange(of: push.isAuthorized) { _, _ in scheduleSeasonReminder() }
            .onChange(of: push.isEnabled) { _, _ in scheduleSeasonReminder() }
            .onChange(of: auth.userId) { _, userId in
                openedBooks = opened.ids(for: userId)
                wishedKeys = wishlist.spotIds
                removal.userChanged()
                removal.loadHidden(userId: userId, today: cardsDay)
            }
            // ①現像の画面（2026-11-12 札 #543）。閉じたら札を読み直し、「題・公開範囲を変える」なら今の投稿の画面へ
            .fullScreenCover(item: $developing, onDismiss: {
                developRevision += 1
                guard let edit = developEdit else { return }
                developEdit = nil
                DevelopPhotos.openUploadScreen(ids: edit.ids, trip: edit.trip, published: edit.published)
            }) { trip in
                DevelopView(trip: trip, name: developName(trip)) { ids, published in developEdit = (trip, ids, published) }
            }
    }

    // MARK: - ①現像前の旅（2026-11-12 札 #543）

    /// 端末の写真の一冊（見本の通信では同梱の見本・`DevelopPreview`）
    private var deviceBooks: [LibraryTrip] {
        let preview = DevelopPreview.trips(now: cardsNow)
        if !preview.isEmpty { return preview }
        return deviceTrips.books(posted: LibraryTrips.postedShots(of: myPhotos), isMine: auth.userId != nil)
    }

    private func developName(_ trip: LibraryTrip) -> String? {
        DevelopPreview.names(now: cardsNow)[trip.id] ?? deviceTrips.names[trip.id]
    }

    /// ホームに出す「現像前の旅」の札（`DevelopTrips.candidate`）。`developRevision` で閉じた旅を読み直す
    private var developChoice: HomeTopCard.Choice? {
        _ = developRevision
        _ = developPosting.isPosting
        guard auth.userId != nil else { return nil }
        guard let trip = DevelopTrips.candidate(books: deviceBooks, now: cardsNow,
                                                closed: developStore.closed(for: auth.userId)) else { return nil }
        return .develop(trip: trip, name: developName(trip))
    }

    /// 札の2行目。途中で閉じた旅は「続きから 4 / 10、」
    private func developLine(_ trip: LibraryTrip, name: String?) -> String {
        let frames = DevelopTrips.frames(of: trip)
        if let saved = developStore.progress(trip.id, for: auth.userId), !saved.decisions.isEmpty {
            let done = min(frames.count, DevelopTrips.nextIndex(frames, decisions: saved.decisions))
            return DevelopTrips.resumePrefix(done: done, total: frames.count)
                + DeviceTrips.title(of: trip, name: name)
        }
        return DevelopTrips.cardLine(trip, name: name)
    }

    /// 札のあいだ
    private static let spacing: CGFloat = JPSpace.xs
    /// 左右の余白（1枚の日の札と同じ）
    private static let margin: CGFloat = JPSpace.gutter
    /// 画面の右端に見せる次の札の幅（めくれることの合図）
    private static let peek: CGFloat = JPSpace.xl

    /// 今日の札の並び（`HomeTopCard.cards` から、その人に出す**最大3枚**・`HomeTopCard.arrange`・2026-11-12）。
    /// 段（`spotShelf`）も同じ並びを見て、札に出ている場所を除く。今日の一問は探すの段へ移したので札に出さない
    /// （問題は読み続ける——段から一問の選択肢の場所を除くため・`HomeSpotShelf.visibleShelf`）。
    /// 撮影スポットを払う入口（`HomeTopCard.withSwipe`・2026-11-11）も候補に入れ、何枚目に出すかは人ごとの表
    /// （`HomeTopCard.priority`・`order` の `spotSwipe`・第10章）で決める（1.1.84 のまとめ）
    private var choices: [HomeTopCard.Choice] {
        // 時間を測る（UI テストのときだけ・`PerfTimeline.measure`・札 #594 の下調べ。無効ならそのまま計算する）
        PerfTimeline.shared.measure("home.topCard.choices") { computeChoices() }
    }

    private func computeChoices() -> [HomeTopCard.Choice] {
        let all = HomeTopCard.withSwipe(
            HomeTopCard.cards(now: cardsNow,
                              // ホームに出さない旅・札から消した旅行プランは渡さない（2026-11-12・`HomeHiddenTrips`）
                              plans: HomeHiddenTrips.visible(plansOwner == auth.userId ? plans : [],
                                                             hidden: removal.hiddenTrips, excluding: removal.removedIds),
                              myPhotos: myPhotos, openedBookDays: openedBooks, spots: spots,
                              wishlist: wishedKeys, quiz: quiz, develop: developChoice),
            spots: spots, today: HomeTopCard.today(cardsNow, in: .current),
            pool: memo.coverPool(spots: spots, revision: spotsRevision))
        let audience = HomeTopCard.Audience.of(signedIn: auth.userId != nil,
                                               myPhotos: myPhotosKnown ? myPhotos : nil)
        return HomeTopCard.arrange(all, audience: audience)
    }

    /// 「いまの季節のスポット」の段の中身。**索引が取れていない・候補が無い日・今日の一問が決着する前は nil**
    /// （空き地を作らない・`HomeSpotShelf.visibleShelf`）。上の札に出ている場所と今日の一問の選択肢は除く。
    /// 並びが変わるのは、札と同じく索引が取れたとき・ホームに戻ったとき（行きたい場所）・
    /// 見えている間（今日の一問）だけ——段から開いた画面が前に出ている間に札が消えて閉じることはない
    private func visibleShelf(_ choices: [HomeTopCard.Choice]) -> HomeSpotShelf.Shelf? {
        PerfTimeline.shared.measure("home.topCard.visibleShelf") {   // 時間を測る（UI テストのときだけ・札 #594）
            memo.visibleShelf(shelfMemoKey(choices)) {
                HomeSpotShelf.visibleShelf(today: HomeTopCard.today(cardsNow, in: .current), spots: spots,
                                           choices: choices, quiz: quiz, quizSettled: quizSettled)
            }
        }
    }

    /// 季節の段と詳細の控えの鍵（`visibleShelf` の材料。索引は書き換えの番号で見る）
    private func shelfMemoKey(_ choices: [HomeTopCard.Choice]) -> HomeTopCardMemo.ShelfKey {
        HomeTopCardMemo.ShelfKey(today: HomeTopCard.today(cardsNow, in: .current), spotsRevision: spotsRevision,
                                 choices: choices, quiz: quiz, quizSettled: quizSettled)
    }

    /// 段を渡し直す合図（段の中身と、索引の書き換え）
    private func shelfKey(_ choices: [HomeTopCard.Choice]) -> HomeSeasonShelfKey {
        HomeSeasonShelfKey(shelf: visibleShelf(choices), spotsRevision: spotsRevision)
    }

    @ViewBuilder
    private func content(_ choices: [HomeTopCard.Choice]) -> some View {
        if choices.count == 1, let only = choices.first {
            // 1枚の日はいまと同じ（左右 16 の余白で画面いっぱい）
            card(for: only, inCarousel: false)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(choices, id: \.slot) { choice in
                        card(for: choice, inCarousel: true)
                            // 渡る幅は左右の余白を除いたもの。**右の余白は中身を切らない**ので
                            // 次の札はその 16 の上にも見える——見せ幅から余白ぶんを戻して引く
                            // （引き忘れると 24 ではなく 40 見えていた）
                            .containerRelativeFrame(.horizontal) { width, _ in
                                max(width - Self.spacing - (Self.peek - Self.margin), 0)
                            }
                    }
                }
                // 1枚ずつ止まる目印は**並びに直接**付ける（Apple の例と同じ。間に別の
                // 修飾を挟むと子に届くかが仕様から読めない）
                .scrollTargetLayout()
                // **背を揃える。** いちばん高い札（今日のテーマの「参加する」・季節の札の案内の2行）に
                // 合わせ、めくるたびに下の一覧が上下しないようにする
                .fixedSize(horizontal: false, vertical: true)
            }
            // 1枚ずつ止まり、札の左端は余白 16 の位置（1枚の日の札と同じ）。
            // **最後の札だけは右端に寄せて止まる**——流せるのは中身の
            // 右端までなので、左に1枚前の札の端が見える（横の並びの普通の止まり方）
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
        }
    }

    /// 札1枚。`inCarousel` のときは外の余白を持たず、並びの高さいっぱいに伸びる
    @ViewBuilder
    private func card(for choice: HomeTopCard.Choice, inCarousel: Bool) -> some View {
        switch choice {
        case .departure(let plan, let daysUntil):
            NavigationLink {
                TripPlansView()
                    .onAppear { reloadPlansOnReturn = true }
            } label: {
                card(eyebrow: "TRIP PLAN", eyebrowLabel: L("旅行プラン", "Trip plan"),
                     title: planTitle(plan),
                     line: daysUntil == 0
                        ? L("今日から\u{2002}1日目", "Starts today\u{2002}Day 1")
                        : L("出発まで \(daysUntil) 日", daysUntil == 1 ? "1 day to go" : "\(daysUntil) days to go"),
                     // 前日と当日は、予定した撮影スポットの光の時刻（当日モード・`TripLight`）
                     detail: tripLight(plan) ?? (plan.itemCount > 0 ? TripPlanText.placeCount(plan.itemCount) : nil),
                     backdrop: nil, detailTruncation: .tail, reservesMenu: true, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
            .tripCardMenu(menuItems(for: plan), label: HomeTripCardMenu.menuLabel, inCarousel: inCarousel) { item in
                choose(item, plan)
            }
        case .onTrip(let plan, let dayNumber):
            Button {
                MissionRouter.shared.post()
            } label: {
                card(eyebrow: "ON TRIP", eyebrowLabel: L("旅の最中", "On a trip"),
                     title: planTitle(plan),
                     line: L("\(dayNumber)日目\u{2002}写真を投稿する", "Day \(dayNumber)\u{2002}Post a photo"),
                     detail: tripLight(plan),
                     backdrop: nil,
                     // 押すと投稿画面が開く（別の画面へ進む「›」ではない）
                     trailingSymbol: "plus", detailTruncation: .tail, reservesMenu: true, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
            .tripCardMenu(menuItems(for: plan), label: HomeTripCardMenu.menuLabel, inCarousel: inCarousel) { item in
                choose(item, plan)
            }
        case .bookReady(let trip):
            NavigationLink {
                TripBookView(trip: trip, isPublic: LikedPhotos.fromPublicFeed(themePhotos))
                    // **開いたら札を下げる**（何度も同じ知らせを出さない）。
                    // 🔴 **ここでは印を残すだけ**——いま札を差し替えると、押した元の
                    // リンクが裏で消え、開いたばかりの一冊が勝手に閉じることがある。
                    // 差し替えはホームに戻ってきたとき（`body` の `onAppear`）
                    .onAppear { opened.mark(HomeTopCard.bookKey(trip), for: auth.userId) }
            } label: {
                card(eyebrow: "TRIP BOOK", eyebrowLabel: L("旅の一冊", "Trip book"),
                     title: L("旅の一冊ができました", "Your trip book is ready"),
                     line: "\(TripBook.title(of: trip))\u{2002}\(TripBook.daysLabel(trip.days))\u{2002}"
                        + PhotoMapViewModel.photoCountLabel(trip.photos.count),
                     detail: nil,
                     backdrop: trip.cover, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .develop(let trip, let name):
            // ①現像前の旅（2026-11-12 札 #543）。左の写真の代わりに、色を抜いたフィルムの3コマ
            Button {
                developing = trip
            } label: {
                // 2026-11-12（説明なしで分かる 項目6）: 題は中身の名前「まだ載せていない旅」、3行目はどこから見つけたか
                card(eyebrow: DevelopTrips.cardEyebrow, eyebrowLabel: DevelopTrips.cardEyebrowSpoken,
                     title: DevelopTrips.cardTitle,
                     line: developLine(trip, name: name),
                     // 一部の写真だけ許可: 「選んで許可した写真の中から見つけました」（章「状態」）
                     detail: DevelopTrips.cardDetail(limited: deviceTrips.status == .limited
                                                     || PreviewSession.developLimited),
                     backdrop: nil, film: Array(DevelopTrips.frames(of: trip).prefix(3)), inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.develop")
        case .oneYearAgo(let photo, let byUploadDate):
            NavigationLink {
                // 1年前の札は自分の写真（`HomeTopCard.oneYearAgo(myPhotos:)`）。個別ページが
                // 在るのは公開一覧（`themePhotos`＝ホームの一覧）に載っているときだけ（`PhotoLink`）
                PhotoDetailView(photo: photo, fromPublicFeed: LikedPhotos.fromPublicFeed(themePhotos)(photo),
                                context: [photo])
            } label: {
                card(eyebrow: "ONE YEAR AGO", eyebrowLabel: L("1年前", "A year ago"),
                     title: byUploadDate ? L("1年前に投稿", "Posted a year ago")
                                         : L("1年前の今ごろ", "A year ago"),
                     line: yearAgoLine(photo),
                     detail: nil,
                     backdrop: photo, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .inSeason(let spot, let season, let guide):
            NavigationLink {
                OfficialSpotView(spot: spot, spots: spots, photos: themePhotos)
            } label: {
                // 見出しは**季節の名前**（「秋の撮影スポット」）。「いま見頃」とは言わない
                card(eyebrow: "\(season.uppercased()) SPOT",
                     eyebrowLabel: HomeTopCard.seasonEyebrow(season),
                     title: spot.name,
                     line: guide,
                     // **写真を出すなら作者とライセンスも出す**（CC BY・CC BY-SA の条件。
                     // 薄い背景でも写真は写真）。出典の頭は切らない（`TopCardCredit`・2026-11-14 判断）
                     detail: Self.spotDetail(spot), credit: Self.spotCredit(spot),
                     backdrop: nil, backdropURL: spot.photo?.url, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .wishlistSeason(let spot, let season, let guide):
            NavigationLink {
                OfficialSpotView(spot: spot, spots: spots, photos: themePhotos)
            } label: {
                card(eyebrow: "WISHLIST",
                     eyebrowLabel: HomeTopCard.wishlistEyebrow(season),
                     title: spot.name,
                     line: guide,
                     // 写真を出すなら作者とライセンスも出す（季節の札と同じ）
                     detail: Self.spotDetail(spot), credit: Self.spotCredit(spot),
                     backdrop: nil, backdropURL: spot.photo?.url, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .swipe(let cover):
            // 押すと全画面の払う画面。**札の上で払う操作は置かない**（札の並びは横にめくるので、指を取り合う）。
            // 未ログインでも開ける（払った「行きたい」は端末に入り、ログインで引き継ぐ）
            Button {
                showSwipe = true
            } label: {
                card(eyebrow: "WHERE TO NEXT", eyebrowLabel: SpotSwipe.eyebrowLabel,
                     title: SpotSwipe.cardTitle,
                     line: SpotSwipe.cardLine(started: swipeStarted, wishCount: wishlist.spotIds.count,
                                              signedIn: auth.userId != nil),
                     // 写真を出すなら作者とライセンスも出す（季節の札と同じ）
                     detail: nil, credit: cover.flatMap(Self.spotCredit),
                     backdrop: nil, backdropURL: cover?.photo?.url, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.spotSwipe")
        case .theme:
            DailyThemeCard(photos: themePhotos, myPhotos: myPhotos, inCarousel: inCarousel)
        case .quiz(let quiz):
            NavigationLink {
                DailyQuizView(photos: themePhotos)
            } label: {
                card(eyebrow: "DAILY QUIZ", eyebrowLabel: L("今日の一問", "Today's question"),
                     title: L("この写真はどこ？", "Where is this?"),
                     line: quizAnswered
                        ? L("答えました、明日また新しい写真", "Answered, a new photo tomorrow")
                        : L("4つの中から撮影地を当てる", "Guess the spot from four choices"),
                     // 写真を出すなら作者とライセンスも出す（季節の札と同じ）
                     detail: nil, credit: TopCardCredit(photo: quiz.photo),
                     backdrop: nil, backdropURL: quiz.photo.url, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 札1枚（今日のテーマの札と同じ地・角・余白）

    private func card(eyebrow: String, eyebrowLabel: String, title: String, line: String,
                      detail: String?, credit: TopCardCredit? = nil, backdrop: Photo?, backdropURL: URL? = nil,
                      film: [String] = [],
                      trailingSymbol: String = "chevron.right", detailTruncation: Text.TruncationMode = .middle,
                      reservesMenu: Bool = false, inCarousel: Bool) -> some View {
        // 札の面は探すの「今日の一問」の段と同じ部品（`TopCardFace`・2026-11-12 に切り出した）。
        // ①現像前の旅の札は左の写真の代わりにフィルムの3コマ（`film`・札 #543。1.1.84 のまとめで面に移した）。
        // 旅行プランの札は右上の「⋯」の分を空ける（`reservesMenu`・1.1.84 のまとめで面に移した）
        TopCardFace(eyebrow: eyebrow, eyebrowLabel: eyebrowLabel, title: title, line: line, detail: detail,
                    credit: credit, backdrop: backdrop, backdropURL: backdropURL, film: film, trailingSymbol: trailingSymbol,
                    detailTruncation: detailTruncation, reservesMenu: reservesMenu, inCarousel: inCarousel)
    }

    /// 旅行プランの札で、右上の「⋯」の当たり（44）に眉と題が潜らないよう空ける幅
    /// （当たり 44 から、札の右の余白 12・「›」の列・その間 8 で既に空いている分を除いた分）
    nonisolated static let menuReserve: CGFloat = 20

    /// 札の背（板の 116）。字を大きくする設定ではそれより伸びる
    nonisolated static let cardHeight: CGFloat = 116
    /// 札の字の行の上限（#417 ③: 題・一行・出典とも1行）
    nonisolated static let lineLimit = 1
    /// 札の左の写真の幅（板の 112）
    nonisolated static let photoWidth: CGFloat = 112

    /// スポットの札の小さい行のうち、**写真の無い札**の分（地域だけ）。写真があれば出典の行（`spotCredit`）を出し、
    /// こちらは使わない（`TopCardFace` は `credit` を先に見る）。どちらも無ければ出さない（空の行が並んでいた）
    private static func spotDetail(_ spot: OfficialSpot) -> String? {
        spot.photo == nil ? spot.regionLabel : nil
    }

    /// スポットの札の写真の出典（地域つき）。**2026-11-14 判断**: 前は「地域　写真: … / ライセンス」の1本の字を
    /// 真ん中で切っていて、ちょうど出典の頭（「写真: 作者」）が消えていた。いまは地域から削り、出典の頭を必ず残す
    /// （`TopCardCredit`・`TopCardFace.creditLine`）
    nonisolated static func spotCredit(_ spot: OfficialSpot) -> TopCardCredit? {
        spot.photo.map { TopCardCredit(spot: spot, photo: $0) }
    }

    /// 当日モードの小さい行（今日か明日の撮影スポットの光の時刻）。当たらなければ nil
    private func tripLight(_ plan: TripPlan) -> String? {
        guard let today = HomeTopCard.today(cardsNow, in: .current),
              let entry = TripLight.entry(plan: plan, today: today, spots: spots) else { return nil }
        return TripLight.line(entry)
    }

    // MARK: - 旅行プランの札の「⋯」（2026-11-12）

    private func menuItems(for plan: TripPlan) -> [HomeTripCardMenu.Item] {
        HomeTripCardMenu.items(for: HomeTripCardMenu.role(of: plan, me: auth.userId))
    }

    /// メニューで選んだ。出さない・削除・抜けるは聞かずにすぐ（元に戻すを6秒）。仲間全員から削除だけ確かめる
    private func choose(_ item: HomeTripCardMenu.Item, _ plan: TripPlan) {
        guard let userId = auth.userId else { return }
        switch item {
        case .hideFromHome:
            removal.hide(plan, title: planTitle(plan), userId: userId)
        case .delete, .deleteForEveryone, .leave:
            if item.needsConfirm { confirmingEveryone = plan } else { remove(plan, item) }
        }
    }

    private func remove(_ plan: TripPlan, _ item: HomeTripCardMenu.Item) {
        guard let userId = auth.userId else { return }
        removal.remove(planId: plan.planId, title: planTitle(plan), item: item, userId: userId, send: sendRemoval)
    }

    /// 送る口。**押した人と今の人が違えば送らない**（書き残しのまま・その人が戻ったら送る）
    private var sendRemoval: TripPlanRemovalQueue.Send {
        let trips = environment.trips
        let auth = self.auth
        return { job in
            guard auth.userId == job.userId else { throw TripPlanRemovalQueue.NotNow() }
            _ = try await trips.delete(planId: job.planId)
        }
    }

    private func resumeRemovals() {
        removal.resume(userId: auth.userId, send: sendRemoval)
    }

    private func planTitle(_ plan: TripPlan) -> String {
        let title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L("旅行プラン", "Trip plan") : title
    }

    /// 撮影地があれば撮影地、無ければ題。どちらも無ければ一言だけ
    private func yearAgoLine(_ photo: Photo) -> String {
        let place = LocationMatch.display(photo.location)
        if !place.isEmpty { return place }
        let title = photo.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L("あの日の1枚", "A photo from that day") : title
    }

    // MARK: - 読み込み

    /// 撮影スポットの索引。**取れたら二度と取りに行かない**（画面が生きている間）。
    /// 取れなかった回は空のまま（札が出ないだけ）
    private func loadSpots() async {
        guard spots.isEmpty else { return }
        let fetched = try? await environment.spots.fetchIndex()
        guard !Task.isCancelled, let fetched else { return }
        spots = fetched
        spotsRevision &+= 1
        PerfRecorder.shared.mark("home.spots.loaded")
        scheduleSeasonReminder()
    }

    /// 札・段・当日の行に出る、まだ索引だけのスポット
    private func detailNeeds(_ choices: [HomeTopCard.Choice]) -> [OfficialSpot] {
        // 時間を測る（UI テストのときだけ・札 #594 の下調べ）
        PerfTimeline.shared.measure("home.topCard.detailNeeds") {
            memo.detailNeeds(shelfMemoKey(choices)) { computeDetailNeeds(choices) }
        }
    }

    private func computeDetailNeeds(_ choices: [HomeTopCard.Choice]) -> [OfficialSpot] {
        guard !spots.isEmpty else { return [] }
        return SpotDetailNeeds.home(choices: choices, shelf: visibleShelf(choices), spots: spots)
    }

    /// 出すスポットの詳細を重ねる（`OfficialSpotService.withDetails`）。取れなければ索引のまま（写真・文が出ないだけ）
    private func loadDetails(_ choices: [HomeTopCard.Choice]) async {
        let needs = detailNeeds(choices)
        guard !needs.isEmpty else { return }
        let merged = await environment.spots.withDetails(spots, for: needs)
        guard !Task.isCancelled else { return }
        spots = merged
        spotsRevision &+= 1
        PerfRecorder.shared.mark("home.details.merged")
    }

    /// 前面が確定したときだけ、一冊の印・行きたい・取り直した札を入れる
    /// 画面に出た（ホームに戻った・送って戻った）
    private func cameIntoView() {
        switch front.appear() {
        case .first:
            landHomeCards()
        case .returning:
            // スワイプ途中で一冊の印や行きたいを読むと、開いている画面が閉じる
            frontSettle?.cancel()
            frontSettle = Task {
                try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                guard !Task.isCancelled, front.confirm() else { return }
                landHomeCards()
            }
        }
    }

    /// 画面から出た（上に別の画面を積んだ・送って流れ出た）
    private func wentOutOfView() {
        frontSettle?.cancel()
        frontSettle = nil
        front.disappear()
        isShown = false
    }

    private func landHomeCards() {
        openedBooks = opened.ids(for: auth.userId)
        wishedKeys = wishlist.spotIds
        removal.loadHidden(userId: auth.userId, today: cardsDay)
        resumeRemovals()
        isShown = true
        applyPendingQuiz()
        applyPendingPlans()
        scheduleSeasonReminder()
        if reloadPlansOnReturn {
            reloadPlansOnReturn = false
            returnReloads &+= 1
        }
    }

    /// 見頃のお知らせ（次の季節の始まりに1件だけ・端末の中だけ・`SeasonReminder`）を入れ替える。
    /// 索引が取れたとき・ホームに戻ったとき（「行きたい」を変えたかもしれない）に呼ぶ。
    /// 索引が取れていない間は触らない（空の索引で前の予約を消さない）
    private func scheduleSeasonReminder() {
        guard !spots.isEmpty else { return }
        let plan = SeasonReminder.plan(now: Date(), spots: spots, wishlist: wishlist.spotIds, calendar: SeasonReminder.calendar)
        let allowed = auth.userId != nil && push.isEnabled && push.isAuthorized
        Task { await SeasonReminderScheduler.shared.reschedule(plan, allowed: allowed) }
    }

    /// 今日の一問。**取れなかった日は札を出さない**（404・圏外とも）。静的な JSON なので
    /// Lambda の同時実行には乗らない
    private func loadQuiz() async {
        let date = DailyQuiz.today()
        if quiz?.date == date {
            // 一問は日本時間で替わる。**早抜けでも札と段の日は確かめる**（日本の外では端末の 0 時が別）
            if isShown { advanceDay() }
            quizSettled = true
            return
        }
        let result = try? await environment.quiz.fetch(date: date)
        // 止められた回は決着にしない（次の `.task` が取り直す）
        guard !Task.isCancelled else { return }
        if case .ready(let fetched)? = result {
            pendingQuiz = fetched
        }
        pendingQuizSettled = true
        // 見えていればその場で整える（取れなければ昨日の札を下げる）。**見えていない＝札から開いた
        // 画面が前に出ている間は触らない**——今日の一問の札・答えと同じスポットの季節の札が
        // 消えると、押した元のリンクが消えて開いている画面が閉じる
        if isShown { applyPendingQuiz() }
    }

    /// 札と段の日（`cardsNow` の端末の暦の日）。変わったら今日の一問と 0 時の待ちを掛け直す
    private var cardsDay: String { TripPlanText.ymd(pickedIn: .current, cardsNow) }

    /// 札と段の「今日」を今へ進める（**ホームが見えているときだけ呼ぶ**）。日が替わって今日の一問がまだ
    /// 昨日のものなら、一問が決着するまで段を下げる（`quizSettled`・昨日の選択肢で除いた段を一瞬出さない）
    private func advanceDay() {
        let now = Date()
        guard HomeDailySpots.shouldAdvance(shown: cardsNow, now: now, in: .current) else { return }
        cardsNow = now
        if let current = quiz, current.date != DailyQuiz.today(now) { quizSettled = false }
    }

    /// ホームのまま日をまたぐのを待つ。次の 0 時（端末の暦）か最大15分ごとに起き、**壁時計で日を確かめ直す**
    /// （`HomeDailySpots.secondsUntilRecheck`）——端末が眠っている間は待ちが進まない見込みで、時計や時刻帯が
    /// 変わることもある。日が変わっていてホームが見えていれば進める（`cardsDay` が変わり、この待ちは掛け直される）。
    /// 見えていなければ待ち続ける（戻ったときの `landHomeCards` が進める）。止められたら抜ける
    private func waitForNextDay() async {
        while !Task.isCancelled {
            let seconds = HomeDailySpots.secondsUntilRecheck(now: Date(), in: .current)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if isShown, HomeDailySpots.shouldAdvance(shown: cardsNow, now: Date(), in: .current) {
                advanceDay()
                return
            }
        }
    }

    /// 今日の一問の札を整える（ホームが見えているときだけ呼ぶ）: 取り直したものがあれば差し替え、
    /// **昨日の札は下げる**（0時をまたいだ・取り直しに失敗した）。答えたかも読み直す。
    /// 先に札と段の日を今日へ進める（`advanceDay`）
    private func applyPendingQuiz() {
        advanceDay()
        if let pendingQuiz {
            quiz = pendingQuiz
            self.pendingQuiz = nil
        } else if let current = quiz, current.date != DailyQuiz.today() {
            quiz = nil
        }
        quizAnswered = quiz.map { QuizAnswers().chosen(for: $0) != nil } ?? false
        if pendingQuizSettled {
            quizSettled = true
            pendingQuizSettled = false
        }
    }

    private func load() async {
        let userId = auth.userId
        // 🔴 **人が替わったら、まず前の人のプランを捨てる**（取れなかった回に残さない）
        if plansOwner != userId {
            plans = []
            plansOwner = nil
            pendingPlans = nil
            loadedKey = nil
        }
        guard userId != nil else { return }
        let key = "\(userId ?? "-")#\(reloadToken)#\(returnReloads)"
        guard loadedKey != key else { return }
        // ⚠️ `if let x = try? await …` は構文検査（tree-sitter）が読めない。2文に割る
        let fetched = try? await environment.trips.list()
        // **画面を離れて止められた・待っている間に人が替わった回は書かない**
        guard !Task.isCancelled, auth.userId == userId else { return }
        guard let fetched else { return }
        pendingPlans = fetched
        plansOwner = userId
        loadedKey = key
        // 見えていればその場で差し替える。**札から開いた画面が前に出ている間は触らない**
        // （`loadQuiz` と同じ）——戻ったとき（`onAppear`）に移す
        if isShown { applyPendingPlans() }
    }

    /// 取り直した旅行プランを札に移す（ホームが見えているときだけ呼ぶ）
    private func applyPendingPlans() {
        if let pendingPlans {
            plans = pendingPlans
            self.pendingPlans = nil
        }
    }
}

// MARK: - 旅行プランの札の「⋯」と長押し（2026-11-12）

extension View {
    /// 旅行プランの札に、右上の「⋯」（当たり 44・黒い札の上なので「›」と同じ text-2 の字）と、同じ中身の長押しのメニュー
    /// （系統のコンテキストメニュー）を付ける。「⋯」は札のリンクの**外**に重ねる（リンクの中にボタンを入れると、押した所で
    /// どちらが動くかが決まらない）。1枚の日の札は左右に 16 の余白を持つので、その分だけ内へ寄せる
    func tripCardMenu(_ items: [HomeTripCardMenu.Item], label: String, inCarousel: Bool,
                      choose: @escaping (HomeTripCardMenu.Item) -> Void) -> some View {
        self
            .contextMenu { TripCardMenuItems(items: items, choose: choose) }
            .overlay(alignment: .topTrailing) {
                Menu {
                    TripCardMenuItems(items: items, choose: choose)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.text2)
                        // 字の右端を下の「›」の右端（札の右の余白 12）にそろえ、当たりは札の右上の 44 角
                        .padding(.trailing, JPSpace.s)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(label)
                .accessibilityIdentifier("home.tripMenu")
                .padding(.trailing, inCarousel ? 0 : JPSpace.gutter)
            }
    }
}

/// 「⋯」と長押しで同じ中身（`HomeTripCardMenu.items`）
private struct TripCardMenuItems: View {
    let items: [HomeTripCardMenu.Item]
    let choose: (HomeTripCardMenu.Item) -> Void

    var body: some View {
        ForEach(items, id: \.self) { item in
            Button(role: item.isDestructive ? .destructive : nil) {
                choose(item)
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
            .accessibilityIdentifier(item.identifier)
        }
    }
}
