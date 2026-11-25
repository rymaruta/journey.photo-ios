import SwiftUI
import UIKit

/// 旅行プランの日程（キャンバス「17b 旅行プランの日程」／ Web の `PlanEditor`）。
///
/// **自動で保存する**（2026-11-10 判断・札 #521・板 TripPlanDays の F34）。右上の「保存」は外した。
/// 手を止めてから少し待ってまとめて送る（`TripAutosave`）。送るのは**変えた項目だけ**（`TripPlanText.patch`）。
/// 送る前に読み直し、別の端末で変わっていたら知らせて止める。
///
/// 🔴 **送れなかった直しを黙って失わない。** 圏外・断られたときは画面の上に「まだ送れていません」と
/// 「もう一度試す」を残し、戻るときは今の「保存せずに戻る」の確かめを出す（`unsavedLeaveGuard`）。
/// 送れる状態なら、戻るときに確かめずに送ってから戻る。端末に控えは持たない（今の決まりのまま）。
///
/// 並べ替えは行の右の**運ぶ印を押さえて運ぶ**（同じ日の中も、別の日へも・`TripPlanEdit.dropped`）。
/// 行のほかの所を押すと今どおり撮影スポットが開く。読み上げでは持ち手 ≡ を上下にスワイプ（2026-11-12）と「…」。
/// 場所と場所の間には移動の見込みの1行（`TripLegRow`・Apple の地図が返した数だけ）。
struct TripPlanDetailView: View {

    let planId: String
    @ObservedObject var model: TripPlansModel
    /// DM の会話から作ったプランの相手（2a の流れの最後・「[名前] と共有する」を出す）。承認前の会話では渡さない
    var sharePeer: TripSharePeer? = nil
    /// 開いたときの「日程 | 会話」（受信箱・プッシュから開いたときは会話）
    var startTab: TripShareText.Tab = .days
    /// 開いたら今日の日まで送る（2026-11-16 判断・使い勝手の見直し A2: 旅の日にホームの札を押した）。
    /// 今日の日は見出しを「今日」にして札の縁を真鍮にする（これはどこから開いても）
    var opensToday = false

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var hidden: ModerationStore
    /// 電波なしで使える旅（板 72・2026-10-09）
    @EnvironmentObject private var offline: OfflineTripStore
    @EnvironmentObject private var connectivity: Connectivity
    /// 「プランを入れ替えました」の知らせ（札 #667）
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss
    /// 移動の見込み（アプリを開いている間の控え・`TravelEstimator`）
    @ObservedObject private var travel = TravelEstimator.shared
    /// 画面の外でプランが書き換わった知らせ（「旅行プランに入れる」のシート）
    @ObservedObject private var outsideChanges = TripPlanChanges.shared
    /// AI で作ったプラン（札 #621）: 並べた理由・押すだけの直し・替える・元に戻す（アプリを開いている間だけ）
    @ObservedObject private var aiNotes = TripAINotes.shared
    @StateObject private var aiRunner = TripAIRunner()
    /// AI の組み直しと替えるの前の日程（「元に戻す」で1つずつ戻す。画面を出たら消える）
    @State private var aiHistory: [TripReplan.Step] = []
    /// 組み直しの手順（画面を閉じたら取り消す。取り消した回は回数に数えない・札 #667 の確かめ役）
    @State private var replanTask: Task<Void, Never>?
    /// 組み直しの案（札 #667）。**「この案にする」まで日程は変えない**（`TripReplan.Proposal`）
    @State private var replan: TripReplan.Proposal?
    /// 案の「今 | 組み直した案」のどちらを見ているか
    @State private var replanShowingAfter = true
    /// 組んでいる条件（チップの名前か打った文）
    @State private var replanWorking: String?
    /// AI で組めなかった回の1行と、帯から Pro の案内を開けるか
    @State private var replanNotice: String?
    @State private var replanNoticePro = false
    @State private var aiShowPro = false
    @State private var aiSwap: TripAISwapTarget?
    @Environment(\.scenePhase) private var scenePhase

    /// 自動保存で送れていない事情（圏外・断られた・別の端末の変更）。送れたら消す
    @State private var problem: TripAutosave.Problem?
    /// 手を止めてから送るまでの待ち（打ち直すたびに取り消して待ち直す）
    @State private var autosave = TripAutosaveDebouncer()
    /// 送りを1本にまとめる（2秒の待ち・戻る・撮影スポットを開く・裏に回るが重なっても2本走らせない）
    @State private var flusher = TripAutosaveFlusher()
    /// 「保存せずに戻る」を選んだ（消える間に送らない）
    @State private var discarding = false
    /// 運んでいる行の落とし先（その行の上に真鍮の線を出す）。日の末尾は `item == nil`
    @State private var dropTarget: DropSpot?
    /// 開いている区間のシート
    @State private var legTarget: LegTarget?
    /// 「日付」のシート（2026-11-16 判断・使い勝手の見直し A5）
    @State private var editingDates = false
    /// 今日の日まで送ったか（開いたときの1回だけ。あとで日程が変わっても送り直さない）
    @State private var scrolledToToday = false
    /// 電波なしの札の「Pro か」（上と下の2枚で1つ・`OfflineTripCard.slot`）
    @State private var offlinePro: Bool?
    /// 変えた出発の時刻（この iPhone だけ・札 #677）
    @ObservedObject private var starts = TripStartStore.shared
    /// 出発の時刻のチップを開いている日
    @State private var openStartDay: Int?
    @ScaledMetric(relativeTo: .body) private var timeWidth: CGFloat = TripTimeStyle.columnWidth
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct DropSpot: Equatable { let day: Int; let item: Int? }
    private struct LegTarget: Identifiable {
        let leg: TripTravel.Leg
        let estimates: [TripTravel.Estimate]
        /// 地図のアプリを開く手段（行と同じ `TripTravel.mapsMode`）
        let mode: TripTravel.Mode
        let sun: TripDraft.Sun?
        let destinationTimes: [String]
        let previousTimes: [String]
        /// 長い移動（Google フライトだけ）
        let long: Bool
        /// 行き先の日の日付
        let date: String?
        var id: String { leg.id }
    }

    /// 手元の下書き。**開き直したらサーバーの姿に戻す**（Web と同じ）
    @State private var days: [TripDay] = []
    @State private var start: String?
    @State private var end: String?
    @State private var loadedFrom: TripPlan?
    /// 保存で送った下書き。応答が届いたとき、**それ以降に打った編集があれば残す**
    @State private var sent: Draft?
    @State private var appeared = false
    /// 「場所を足す」を押した日
    @State private var picking: PickTarget?
    /// 撮影スポットの別名（slug → 別名・場所を足すシートの探す欄で使う）。取れなければ空
    @State private var aliases: [String: [String]] = [:]
    /// 外した場所の控え（この画面を開いている間だけ・日の下に「外しました　戻す」・2026-11-12 モックの場面6）
    @State private var removedShelf: [TripPlanEdit.Removed] = []
    @State private var removedSeq = 0
    /// 「地図で見る」を押した日（`TripDayMapView`）
    @State private var mapDay: MapTarget?
    /// 消すか確かめている日（予定の入った日だけ・`TripPlanEdit.confirmsRemoving`）。
    /// **画面の中に開く札で確かめる**（プランの削除と同じ形）。系統の確認ダイアログにすると、
    /// 保存の返事を待つ間に出した確認の上にエラーのアラートが立てず、以後の知らせが止まった
    /// （37b96ec のレビュー）
    @State private var removingDay: RemoveDayTarget?
    @State private var confirmingDelete = false
    // MARK: 仲間（2026-11-12・札 #553）
    /// 選んでいる「日程 | 会話」（nil の間は `startTab`）
    @State private var chosenTab: TripShareText.Tab?
    @State private var members: [TripMember] = []
    @State private var shareWorking = false
    @State private var inviting = false
    @State private var inviteLink: TripInviteLink?
    @State private var inviteError: String?
    @State private var chatUnread = false
    /// ほかの仲間の変更に重ね直して送り直した回数（続けてぶつかるなら止めて知らせる）
    @State private var rebases = 0
    /// 「保存して戻る／変更を捨てる」の確認
    @State private var confirmLeave = false
    /// 失敗の帯（2026-11-25 判断・人間工学の案 2・`TripPlanFailure`）。前は5つの窓（`.alert`）で、OK しか無く画面が止まった。
    /// 下の帯に出して、「もう一度」1回で直す（`failureRetry`）。下までスクロールしていても見える所（指の近く）に出す
    @State private var failure: TripPlanFailure?
    /// 帯の「もう一度」で走らせる直し（送り直せる失敗だけ。項目が変わった回は空で「閉じる」）。1回だけ取り出せる（`TripPlanRetry`）
    @State private var failureRetry = TripPlanRetry()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 帯を払っている量（離したら戻すか閉じる・`TripPlanFailure.swipeCloses`）
    @State private var failureDrag: CGSize = .zero
    /// 名前を引く材料が**一度でも取れたか**。取れた後の読み直しの失敗で消さない
    @State private var gotPhotos = false
    @State private var gotIndex = false
    /// 保存を送った回数（「保存して戻る」の失敗の知らせを、その後に別の保存が
    /// 走っていたら出さないための目印）
    @State private var saveAttempt = 0
    /// 名前を引く材料（取れなくても画面は出る——観光スポットは「読み込めませんでした」、撮影地は鍵のままになるだけ）
    @State private var photos: [Photo] = []
    /// 自分の写真（プランの場所に、その日に撮った1枚を並べる・札 #710 の案3・`TripPlanPhotos`）。取れなければ空のまま
    @State private var myPhotos: [Photo] = []
    /// 点線の枠から開く投稿（観光スポットを撮影地に入れて開く）
    @State private var stopPost: TripStopPostTarget?
    @State private var loadedIndex: [OfficialSpot] = []
    /// 名前と座標を引く索引。読み込む前は、AI で作ったときの候補で引く（2026-11-23 判断・作り終えた直後に `sp_…` が見えていた）
    private var index: [OfficialSpot] {
        get { TripPlanText.nameIndex(loaded: loadedIndex, candidates: aiNotes.note(planId)?.candidates ?? []) }
        nonmutating set { loadedIndex = newValue }
    }
    /// 索引を一度でも聞き終えたか（成否を問わない）。聞き終えるまでは、名前を引けない観光スポットの行を骨組みにする
    @State private var indexTried = false
    /// 候補の材料（写真の一覧・スポットの索引）を**取れなかった**か。
    /// 「聞けなかった」を「まだ保存していない」と言わないために持つ
    @State private var sourcesFailed = false

    private struct PickTarget: Identifiable { let day: Int; var id: Int { day } }
    /// 消すか確かめている日（何日目と、**押したときの日程まるごと**）。
    /// 日程が変わったら札を出さない・消さない（`TripPlanEdit.removeDay`）
    private struct RemoveDayTarget {
        let index: Int
        let days: [TripDay]
    }
    private struct MapTarget: Identifiable {
        let day: Int
        let stops: [TripDayMap.Stop]
        var id: Int { day }
    }
    /// ひとことを書いている項目（何日目の何番目と、**開いたときの項目そのもの**）。
    /// 書く欄を開いている間に日程が差し替わっても、別の項目に書かない（`TripPlanEdit.locate`）
    private struct NoteTarget { let day: Int; let item: Int; let original: TripItem }
    @State private var noteTarget: NoteTarget?
    @State private var noteText = ""
    private struct Draft: Equatable {
        var days: [TripDay]
        var start: String?
        var end: String?
    }
    private var draft: Draft { Draft(days: days, start: start, end: end) }

    private var plan: TripPlan? { model.plan(planId) }
    /// 撮影地の行。**描くたびに導かない**（項目ごとに2回引くので重い）——読めたときと
    /// 画面に戻ったときに作り直す。
    ///
    /// 🔴 **ブロック・通報は画面に戻ったときの写し（`dropped`）で外す。** 生の
    /// `hidden.snapshot` を読むと、積んだスポットの画面の中でブロックした瞬間に行が
    /// 消え、`NavigationLink` ごと上の画面が閉じていた（`SpotDetailView` の注記と同じ）。
    /// 鍵で1行に寄せる（`allMergedBySlug`・マイページの行きたい場所と同じ行）
    @State private var places: [DerivedSpot.Place] = []
    @State private var dropped = ModerationSnapshot()
    /// この画面がいちばん上に出ているか（スポットを積んでいる間は行を触らない）
    @State private var onTop = false
    /// 戻るスワイプ途中の `onAppear` で行を消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    /// 前面が確定したときだけ、撮影地の行を作り直す
    private func landPlanFront() {
        onTop = true
        dropped = hidden.snapshot
        refreshPlaces()
        // **前の画面の失敗の文を消すのは、開いた最初の1回だけ。** 項目の
        // スポットを開いて戻るたびに消していたので、保存に失敗した事情が
        // 下書きが未保存のまま見えなくなっていた
        if !appeared {
            appeared = true
            model.clearError()
        }
        resetIfNeeded()
    }

    private func refreshPlaces() {
        places = DerivedSpot.allMergedBySlug(in: dropped.visible(photos))
    }

    /// 圏外で、端末に保存した中身がある（板 72c）。**このときはプランを変えさせない**（電波が戻るまで）
    private var offlineManifest: OfflineTripManifest? {
        connectivity.isOffline ? offline.manifest(planId) : nil
    }

    var body: some View {
        #if DEBUG
        if TripPlanFixture.isOn { TripPlanFixtureCounter.shared.bodyCount += 1 }
        #endif
        return Group {
            if let manifest = offlineManifest {
                ScrollView {
                    OfflineTripContent(manifest: manifest)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                }
            } else if let plan {
                if tab.wrappedValue == .chat, plan.share != nil {
                    chatScreen(plan)
                } else {
                    editor(plan)
                }
            } else {
                // 消した直後・別の端末で消されたとき
                // 2026-11-12（第2章）: 見出しは「見つかりません」（読み込みの失敗ではない）
                ErrorBanner(title: L("プランが見つかりません", "Trip not found"),
                            message: L("このプランは消されたようです。旅行プランの一覧から開き直してください",
                                       "This trip seems to have been deleted. Open it again from your trip list."))
            }
        }
        .webScreen()
        .navigationTitle(L("旅行プラン", "Trip plans"))
        .navigationBarTitleDisplayMode(.inline)
        // 送れる状態なら確かめずに送ってから戻る。送れていない（圏外・断られた・別の端末の変更）ときだけ
        // 今の「保存して戻る／保存せずに戻る」の確かめを出す（`TripAutosave.leave`）
        .unsavedLeaveGuard(TripAutosave.unsaved(leaveAction), isPresented: leaveBinding,
                           canSave: model.busy == nil && !isOffline && problem != .conflict,
                           message: L("まだ送れていない変更があります。保存せずに戻ると、変えた日程は残りません。",
                                      "Some changes aren't sent yet. If you go back without saving, they'll be lost."),
                           onSave: { saveAndLeave() },
                           onDiscard: {
                               discarding = true
                               autosave.cancel()
                               dismiss()
                           })
        .toolbar {
            // 題の下に「変更は自動で保存されます」（板 TripPlanDays）。圏外で保存した中身を出している間は出さない
            if offlineManifest == nil, plan != nil {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(L("旅行プラン", "Trip plans"))
                            .font(JPFont.bodyEmphasis)
                            .foregroundStyle(WebTheme.foreground)
                        Text(TripAutosave.status(sending: sending, problem: problem))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.faint)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tripPlan.autosaveStatus")
                }
            }
        }
        // ひとこと（項目に添えるメモ・200字まで）。**変えたら日程と一緒に保存する**
        // （保存ボタンと「保存せずに戻る？」の確認は、ほかの変更と同じ扱い）
        .alert(L("ひとこと", "Note"),
               isPresented: Binding(get: { noteTarget != nil },
                                    set: { if !$0 { noteTarget = nil } })) {
            TextField(L("例：朝いちばんに行く", "e.g. Go first thing in the morning"), text: $noteText)
            Button(Labels.Common.save) {
                let target = noteTarget
                noteTarget = nil
                guard let t = target else { return }
                if let at = TripPlanEdit.locate(days, day: t.day, item: t.item, original: t.original),
                   let next = TripPlanEdit.setNote(days, day: t.day, item: at, note: noteText) {
                    days = next
                } else {
                    // 書いている間に項目が外れた（別の端末・保存の応答で差し替わった）。
                    // 黙って捨てずに下の帯で知らせる（2026-11-25 判断・窓をやめた。もう一度しても同じなので「閉じる」）
                    fail(.note, L("書いている間に項目が変わったため、ひとことを入れられませんでした。もう一度書いてください。",
                                  "The item changed while you were writing, so the note wasn't added. Please try again."))
                }
            }
            Button(Labels.Common.cancel, role: .cancel) { noteTarget = nil }
        } message: {
            Text(L("\(TripPlanService.noteMax)字まで。空にすると外します", "Up to \(TripPlanService.noteMax) characters. Leave empty to remove."))
        }
        .sheet(isPresented: $inviting) {
            TripInviteSheet(title: plan?.title ?? "", link: inviteLink, failed: inviteError)
        }
        .task(id: plan?.share?.memberIds ?? []) { await loadShare() }
        .onAppear { adoptAINote() }
        .sheet(item: $aiSwap) { target in
            let note = aiNotes.note(planId)
            let used = Set(days.flatMap(\.items).compactMap { item -> String? in
                if case .spot(let id, _) = item { return id }
                return nil
            })
            TripAISwapSheet(spot: target.spot,
                            choices: TripAISwap.choices(for: target.spot, candidates: note?.candidates ?? [], used: used),
                            pick: { swapAI(target, to: $0) })
        }
        .fullScreenCover(isPresented: $aiShowPro) { PaywallView(origin: .tripAI) }
        // 点線の枠から開く投稿（札 #710 の案3）。閉じたら自分の写真を読み直して、枠を写真に替える
        .sheet(item: $stopPost, onDismiss: {
            TabRouter.shared.postSheetClosed()
            Task {
                let mine = try? await environment.photos.myPhotos()
                // 持ち主の確かめは `PhotoOwnership` に集める（他人の写真を行に入れない・2026-11-23）
                if let mine { myPhotos = PhotoOwnership.mine(mine, me: auth.userId) }
            }
        }) { target in
            NavigationStack {
                UploadView(spot: target.spot, onSaved: { photo in
                    TabRouter.shared.notePosted(photo)
                    myPhotos = PostedPhotos.merge(loaded: myPhotos, posted: [photo], owner: auth.userId)
                })
            }
        }
        // 失敗の帯（2026-11-25 判断・人間工学の案 2）。日程と会話のどちらのタブでも、いちばん下（指の近く）に出す
        .safeAreaInset(edge: .bottom) { failureBand }
        // 電波が戻って自動の保存が通ったら、保存の帯を消す（送っていない変更が残っている間は消さない）
        .onChange(of: problem == nil && !isDirty) { _, settled in
            if settled, failure?.isSettled(problemRemains: problem != nil, dirty: isDirty) == true { clearFailure() }
        }
        // 🔴 **取り直せなかった回は、取れていた材料を消さない。** この `.task` は
        // 項目のスポットを開いて戻るたびに走る。圏外で戻ると、読めていた場所の名前と
        // リンクが消えて鍵（sp_…）だけになり、候補も「読み込めませんでした」になっていた
        .task {
            // 2026-11-23 判断: 写真の一覧と索引を同時に聞く（前は写真の一覧を待ってから索引を聞き、その間 `sp_…` が見えていた）
            async let photosCall = try? await environment.gallery.fetchPhotos()
            async let indexCall = try? await environment.spots.fetchIndex()
            let fetchedIndex = await indexCall
            if let fetchedIndex { index = fetchedIndex; gotIndex = true }
            indexTried = true
            let fetchedPhotos = await photosCall
            if let fetchedPhotos { photos = fetchedPhotos; gotPhotos = true }
            // 自分の写真（札 #710 の案3）。ログインしている人の分だけ。取れなかった回は前の分を残す
            var mine: [Photo]?
            if auth.userId != nil { mine = try? await environment.photos.myPhotos() }
            // 自分の写真だけ（`PhotoOwnership`・持ち主の分からない行も入れない）
            if let mine { myPhotos = PhotoOwnership.mine(mine, me: auth.userId) }
            // 別名は取れなくてもよい（名前と読みで当たる・`fetchAliases` は投げない）
            let fetchedAliases = await environment.spots.fetchAliases()
            if !fetchedAliases.isEmpty { aliases = fetchedAliases }
            sourcesFailed = !gotPhotos || !gotIndex
            refreshPlaces()
        }
        // 出ている間に届いたブロック（起動直後のサーバーとの同期など）も拾う。
        // **上に積んでいる間は触らない**（行が消えると上の画面が閉じる）
        .onChange(of: hidden.revision) { _, _ in
            guard onTop else { return }
            dropped = hidden.snapshot
            refreshPlaces()
        }
        .onDisappear {
            // 離れるとき（撮影スポットを積む・戻る）は待たずに送る。「保存せずに戻る」の回は送らない
            if !discarding, isDirty, problem == nil { Task { _ = await flush() } }
            // 組み直しは取り消す（取り消した回は回数に数えない・札 #667 の確かめ役）
            replanTask?.cancel()
            replanTask = nil
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
            onTop = false
        }
        .onAppear {
            switch front.appear() {
            case .first:
                landPlanFront()
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    landPlanFront()
                }
            }
        }
        .onChange(of: plan) { _, _ in resetIfNeeded() }
        // 変えたら、手を止めてから少し待って送る（`TripAutosave.delayNanoseconds`）
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        // 🔴 **裏に回るときは待たずに送る**（確かめ役の指摘・2026-11-10: 2 秒の待ちの間にアプリを閉じると直しが消えた）。
        // 裏で少しだけ続けさせてもらう（`beginBackgroundTask`）
        // background のときだけ（inactive と background の2回で2本にしない・確かめ役の指摘 F）
        .onChange(of: scenePhase) { _, phase in
            guard TripAutosave.sendsOnScenePhase(phase), isDirty, !discarding, problem == nil else { return }
            let window = TripBackgroundWindow(name: "trip-autosave")
            Task { @MainActor in
                _ = await flush(force: true)
                window.end()
            }
        }
        // 画面の外（「旅行プランに入れる」のシート）でこのプランが書き換わった → 直しが無ければ読み直す
        .onChange(of: outsideChanges.revision) { _, _ in
            guard outsideChanges.lastPlanId == planId,
                  TripAutosave.reloadsAfterOutsideChange(dirty: isDirty, sending: sending) else { return }
            Task { await model.load(environment: environment) }
        }
        // 電波が戻ったら、送れていなかった直しを送る
        .onChange(of: connectivity.isOffline) { _, offline in
            guard !offline else { return }
            if problem == .offline { problem = nil }
            scheduleAutosave()
            requestTravel(travelLayout().all)
        }
        // 季節の一文・時刻帯のために、日程にある撮影スポットの詳細を重ねる（索引だけの行だけ）
        // 索引を読む前（AI の候補で名前を引いている間）は重ねない。読んだ索引で置き換わるので、読んでから重ねる
        .task(id: SpotDetailNeeds.key(planSpotsNeedingDetails) + (gotIndex ? "" : "#waiting")) {
            let needs = planSpotsNeedingDetails
            guard gotIndex, !needs.isEmpty else { return }
            index = await environment.spots.withDetails(index, for: needs)
        }
        // 移動の見込みを聞く（開いているプランの区間だけ・同じ区間は控え）
        .sheet(item: $legTarget) { target in
            NavigationStack {
                TripLegSheet(leg: target.leg, estimates: target.estimates, mode: target.mode,
                             sun: target.sun, destinationTimes: target.destinationTimes,
                             previousTimes: target.previousTimes, long: target.long, date: target.date)
            }
            .presentationDetents([.medium, .large])
        }
        // 日程が変わったら日の削除の札を閉じる。控えを残すと、日程が元の形に戻ったときに
        // 押していない札がまた開いた（a229438 のレビュー）
        .onChange(of: days) { _, now in
            if let target = removingDay, target.days != now { removingDay = nil }
        }
        // 日程が変わったら（日を消す・組み直し・元に戻す・仲間の変更・日付の変更）、出発の時刻を今の日へ運ぶ
        // （場所の重なりで日を対応させる・札 #677 の確かめ役）。開いたときも、覚えたときの日程から運ぶ（閉じている間の変更・札 #685）
        .onChange(of: startSlots) { _, now in starts.sync(planId: planId, to: now) }

        // その日の場所を番号つきで地図に・前の場所からの経路（2026-09-30）。
        // **開いた時点の日程で出す**（保存していない並び替えも反映する）
        .sheet(item: $mapDay) { target in
            NavigationStack {
                TripDayMapView(title: L("\(target.day + 1)日目の地図", "Day \(target.day + 1) map"),
                               stops: target.stops)
            }
        }
        // 場所を足す（2026-11-12・1.1.85・札 #570）: 探す欄・押せばすぐ入る・入れる日を替えられる。
        // 足すたびに親の `days` が変わり、シートの中身も描き直る（入れた行が「入れました」になる）
        .sheet(item: $picking) { target in
            NavigationStack {
                TripPlanPickSheet(startDay: target.day,
                                  days: days,
                                  dayLabels: days.indices.map {
                                      TripPlanSheetDay(label: L("\($0 + 1)日目", "Day \($0 + 1)"), date: pickDayDate($0))
                                  },
                                  sourcesFailed: sourcesFailed,
                                  choices: pickChoices,
                                  index: index,
                                  aliases: aliases,
                                  seasonLine: { choice, day in seasonLine(for: choice, day: day) },
                                  onAdd: { item, day in add(item, to: day) },
                                  onUndo: { item, day in
                                      if let next = TripPlanSearch.undoing(item, day: day, in: days) { days = next }
                                  })
            }
        }
    }

    /// サーバーの姿が変わったら（保存・取り直し）、下書きをそれに合わせる。
    ///
    /// 🔴 **ただし、まだ送っていない編集があれば下書きを残す。** 保存の返事を
    /// 待つ間も日の追加や項目の削除はできるので、返事で丸ごと上書きすると
    /// その間に打った編集が黙って消えていた。残した分は「保存」が押せる
    /// （比べる相手が新しいサーバーの姿になる）
    private func resetIfNeeded() {
        guard let plan, plan != loadedFrom else { return }
        let untouched = loadedFrom.map {
            !TripPlanText.isDirty(plan: $0, days: days, start: start, end: end)
        } ?? true
        let keep = !untouched && draft != sent
        loadedFrom = plan
        sent = nil
        guard !keep else { return }
        days = plan.days
        start = plan.startDate
        end = plan.endDate
    }

    /// 下書きと比べる相手。**下書きにサーバーの姿を入れる前（開いた最初の1コマ）は無い**
    /// ——`days` は空で始まり `onAppear` で初めて入るので、その間は日程のあるプランが
    /// 「変えた」に見え、戻るが自前のものにちらつき「保存」が押せる濃さで出ていた
    private var comparedPlan: TripPlan? { loadedFrom == nil ? nil : plan }

    private var isDirty: Bool {
        guard let plan = comparedPlan else { return false }
        return TripPlanText.isDirty(plan: plan, days: days, start: start, end: end)
    }

    /// 圏外か。UI テストの見本（`-JPTripPlanFixtureOffline`・Debug のときだけ）でも圏外として扱う
    private var isOffline: Bool { connectivity.isOffline || TripPlanFixture.offline }

    /// 日程を送っている間（`sent` は保存の間だけ立つ。削除では立たない）
    private var sending: Bool { model.busy != nil && sent != nil }

    private var leaveAction: TripAutosave.Leave {
        TripAutosave.leave(dirty: isDirty, sending: sending, problem: problem, offline: isOffline)
    }

    /// 戻るを押した。**送れる状態なら確かめずに送ってから戻る**（送れなければ確かめを出す）
    private var leaveBinding: Binding<Bool> {
        Binding(get: { confirmLeave }, set: { wanted in
            guard wanted, leaveAction == .sendThenLeave else { confirmLeave = wanted; return }
            Task {
                if await flush(force: true) { dismiss() } else { confirmLeave = true }
            }
        })
    }

    // MARK: - 自動保存

    /// 手を止めてから少し待って送る。打ち直すたびに待ち直す（書き込みの回数を抑える）
    private func scheduleAutosave() {
        guard isDirty, !discarding else {
            autosave.cancel()
            return
        }
        autosave.schedule { _ = await flush() }
    }

    /// 送る。**送れたか**を返す（変えていなければ true）。
    ///
    /// - 圏外なら送らずに「まだ送れていません」を残す
    /// - 送る前に読み直し、別の端末で変わっていたら送らずに止める（`TripAutosave.conflicted`）
    /// - 送っている間に打った直しは、送れたあとで続けて送る
    /// - `force`: 断られた直後でも送り直す（「もう一度試す」・「保存して戻る」）
    private func flush(force: Bool = false) async -> Bool {
        await flusher.run { await flushNow(force: force) }
    }

    /// 送る本体（`flusher` を通して1本ずつ走る）
    private func flushNow(force: Bool) async -> Bool {
        autosave.cancel()
        guard plan != nil, isDirty else { return true }
        if problem == .conflict { return false }
        if case .failed? = problem, !force { return false }
        guard !isOffline else { problem = .offline; return false }
        guard TripAutosave.shouldSend(dirty: isDirty, busy: model.busy != nil, problem: problem) else {
            // ほかの書き込み（削除・前の送信）の最中。終わってから送り直す
            scheduleAutosave()
            return false
        }
        guard let fresh = await model.fetchFresh(environment: environment) else {
            problem = isOffline ? .offline
                : .failed(L("通信を確かめて、もう一度お試しください。", "Check your connection and try again."))
            return false
        }
        if TripAutosave.conflicted(base: loadedFrom, server: fresh.first { $0.planId == planId }) {
            // 共有したプラン: ほかの仲間の変更の上に、自分が変えた分だけを重ね直して送る（`TripShareText.rebase`）。
            // 本人だけのプラン（別の端末）は今までどおり止めて知らせる
            guard let server = fresh.first(where: { $0.planId == planId }), server.share != nil,
                  let base = loadedFrom, rebases < TripAutosave.maxRebases else {
                problem = .conflict
                return false
            }
            rebases += 1
            let mineDays = days, mineStart = start, mineEnd = end
            loadedFrom = server
            sent = nil
            model.adopt(server)
            days = TripShareText.rebase(base: base.days, mine: mineDays, server: server.days)
            start = TripShareText.rebaseDate(base: base.startDate, mine: mineStart, server: server.startDate)
            end = TripShareText.rebaseDate(base: base.endDate, mine: mineEnd, server: server.endDate)
            guard isDirty else { problem = nil; return true }
        }
        let ok = await save()
        let next = TripAutosave.afterSave(ok: ok, conflict: model.lastConflict, rebases: rebases)
        if ok {
            rebases = 0
            problem = nil
            // 🔴 **送れたらその場で比べる相手を新しい版に**（確かめ役の指摘 F: 古い版のまま次の読み直しと比べると、
            // 自分の書き込みを「別の端末の変更」と誤って止めた）。送っている間の直しは残す（下で送り直す）
            if let plan {
                loadedFrom = plan
                sent = nil
            }
            if isDirty { scheduleAutosave() }
        } else if case .retry(let counted) = next {
            // 読み直してから送るまでの間に、ほかの仲間が先に書いた（409）。もう一度読み直して重ね直す。
            // 🔴 **この道でも回数を数える**（2026-11-12 確かめ役の指摘: 数えておらず、読み直しが古い姿を返し続けると
            // 上限なしに送り直した）。手元が共有と知らないプランでも、409 は共有したプランにしか返らないので送り直す
            rebases = counted
            model.clearError()
            return await flushNow(force: force)
        } else {
            problem = .failed(model.errorMessage ?? L("もう一度お試しください。", "Please try again."))
            // 文は上の「まだ送れていません」の札で出す（赤い行と二重にしない）
            model.clearError()
        }
        return ok
    }

    /// 別の端末の変更を読み直す（この画面で変えた分は残らない）
    private func reloadFromServer() async {
        // 送り直しの数を0に戻す（2026-11-12 確かめ役の見直し2: 戻さないと、上限で止まって読み直したあとの
        // 最初のぶつかりで重ね直さずにまた止まった）
        rebases = 0
        await model.load(environment: environment)
        guard let plan else { return }
        loadedFrom = plan
        sent = nil
        days = plan.days
        start = plan.startDate
        end = plan.endDate
        problem = nil
    }

    nonisolated static func problemText(_ problem: TripAutosave.Problem?, shared: Bool = false) -> String {
        switch problem {
        case .failed(let message)?: return message
        case .offline?: return L("圏外のため送れませんでした。", "You're offline.")
        case .conflict?: return TripAutosave.conflictLead(shared: shared)
        case nil: return L("もう一度お試しください", "Please try again.")
        }
    }

    /// 見本のときだけの「送った回数」（Release では何も出さない）
    @ViewBuilder
    private var fixtureSendsLabel: some View {
        #if DEBUG
        if TripPlanFixture.isOn { TripPlanFixtureSendsLabel() }
        #endif
    }

    /// 送れていない直しの札（画面の上・板 Components 06 の灰の印 → 何が起きたか → 押せる一手）
    @ViewBuilder
    private var autosaveBanner: some View {
        if let text = TripAutosave.banner(problem, dirty: isDirty, shared: plan?.share != nil) {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                    Image(systemName: problem == .offline ? "wifi.slash" : "exclamationmark.triangle")
                        .foregroundStyle(WebTheme.faint)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if problem == .conflict {
                    TripOutlineButton(title: L("読み直す", "Reload")) {
                        Task { await reloadFromServer() }
                    }
                } else if TripPlanFailure.showsTopRetry(failure: failure) {
                    // 保存の帯（下の「もう一度」）が出ている間は、一手を帯の1か所にする
                    TripOutlineButton(title: L("もう一度試す", "Try again")) {
                        Task { _ = await flush(force: true) }
                    }
                    .disabled(sending)
                }
            }
            .padding(JPSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jpCardFace()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tripPlan.unsent")
        }
    }

    // MARK: - 詳細・移動の見込み

    /// 詳細（季節の文・時刻帯）を重ねる撮影スポット（日程にある・行きたいに入っていて、まだ索引だけのもの）
    private var planSpotsNeedingDetails: [OfficialSpot] {
        let ids = Set(days.flatMap(\.items).compactMap { item -> String? in
            if case .spot(let id, _) = item { return id } else { return nil }
        })
        // 候補のシートの季節の一文のために、「行きたい」の撮影スポットも（ふつうは数か所）
        let wanted = wishlist.spotIds
        return SpotDetailNeeds.indexOnly(index.filter {
            ids.contains($0.spotId) || wanted.contains(SavedSpotKey.official($0.slug))
        })
    }

    /// 区間の材料と区間（日ごと）。🔴 **描くたびに1回だけ作り、日の節へ渡す**（確かめ役の指摘: 日の節ごと・区間ごとに
    /// 作り直し、台帳を何度もなめていた）。撮影スポットは鍵で1回だけ引く
    struct TravelLayout {
        let stopsByDay: [[TripTravel.Stop]]
        let legsByDay: [[TripTravel.Leg]]
        var all: [TripTravel.Leg] { legsByDay.flatMap { $0 } }
        var key: String { all.map(\.key).joined(separator: ";") }
        /// 座標のある場所が1か所だけのとき、その番号と1行
        let single: (number: Int, hint: String)?

        func legs(_ di: Int) -> [TripTravel.Leg] { legsByDay.indices.contains(di) ? legsByDay[di] : [] }
    }

    private func travelLayout() -> TravelLayout {
        let numbers = TripStyle.stopNumbers(days.map(\.items.count))
        let spots = Dictionary(index.map { ($0.spotId, $0) }, uniquingKeysWith: { first, _ in first })
        let stopsByDay = days.indices.map { di in
            TripDayMap.stops(of: days[di], index: index, places: places,
                             startNumber: numbers.indices.contains(di) ? (numbers[di].first ?? 1) : 1)
                .enumerated().map { offset, stop -> TripTravel.Stop in
                    var spot: OfficialSpot?
                    if days[di].items.indices.contains(offset), case .spot(let id, _) = days[di].items[offset] {
                        spot = spots[id]
                    }
                    return TripTravel.stop(name: stop.name, coords: stop.coords, number: stop.number, spot: spot)
                }
        }
        let flat = stopsByDay.flatMap { $0 }
        let located = flat.filter { $0.coords != nil }
        let single = TripTravel.singlePlaceHint(locatedPlaces: located.count, allPlaces: flat.count)
            .flatMap { hint in located.first.map { ($0.number, hint) } }
        return TravelLayout(stopsByDay: stopsByDay, legsByDay: TripTravel.planLegs(stopsByDay), single: single)
    }

    /// 圏外では聞かない（Apple のサーバーに聞くため）
    private func requestTravel(_ legs: [TripTravel.Leg]) {
        guard !isOffline, offlineManifest == nil else { return }
        travel.request(legs)
    }

    /// 送る。**通ったか**を返す（「保存して戻る」は通ったときだけ閉じる）
    private func save() async -> Bool {
        guard let plan else { return false }
        var patch = TripPlanText.patch(plan: plan, days: days, start: start, end: end)
        // 共有したプランは版を添える（ほかの仲間が先に変えていたら 409 で断られ、読み直して重ね直す）
        patch.rev = plan.share?.rev
        saveAttempt &+= 1
        sent = draft
        let saved = await model.update(planId, patch, environment: environment)
        // 断られたら控えを捨てる（次に届く姿で下書きを上書きしない）
        if !saved { sent = nil }
        return saved
    }

    private func editor(_ plan: TripPlan) -> some View {
        // 区間の材料は描くたびに1回だけ（日の節へ渡す）
        let layout = travelLayout()
        return ScrollViewReader { proxy in
            editorScroll(plan, layout: layout, today: todayIndex, proxy: proxy)
        }
        // 移動の見込みを聞く（開いているプランの区間だけ・同じ区間は控え）
        .task(id: layout.key) { requestTravel(layout.all) }
        // 電波なしの札の「Pro か」（サーバーが決める・読めなければ nil）。札を置かない間も読む（`offlineSlot`）
        .task { offlinePro = (try? await environment.profiles.myProfile())?.isPro }
    }

    /// 日程の画面の中身（`ScrollViewReader` の中・今日の日まで送るため proxy を受ける）
    private func editorScroll(_ plan: TripPlan, layout: TravelLayout, today: Int?, proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(plan)

                // AI の札は1行に畳んで出す（2026-11-16 判断・A6・`TripAICard.open`）。
                // 2026-11-20 判断（札 #667）: 「元に戻す」は下の組み直しの列に1つだけ置く（札の中には出さない）。
                // 組み直しの帯を出している間・組んでいる間は札の帯を出さない（帯を2本重ねない）
                // 行き先を選ばずに作った: アプリが決めた行き先を1行（2026-11-23 owner・`TripAIAutoPlace`）
                if let place = aiNotes.note(planId)?.autoPlace {
                    TripAIAutoPlaceLine(place: place)
                }
                if let note = aiNotes.note(planId), TripAICard.hasContent(note) {
                    TripAICard(note: note, usage: aiRunner.usage, working: replanWorking != nil,
                               online: !connectivity.isOffline,
                               showsBand: replanNotice == nil && replanWorking == nil,
                               redo: { runReplan(label: L("整えて", "Tidy up"), request: "整えて", typed: false) },
                               openPro: { aiShowPro = true })
                }

                // 組み直す（札 #667・案1の模型）。観光スポットが1つでも入っているプランだけ（組み直す物が無いのに出さない）
                if hasReplanSpots || replan != nil || !aiHistory.isEmpty {
                    TripReplanBar(working: replanWorking, proposed: replan?.label, notice: replanNotice,
                                  noticeOpensPro: replanNoticePro, canUndo: !aiHistory.isEmpty && replan == nil,
                                  run: { label, request, typed in runReplan(label: label, request: request, typed: typed) },
                                  quick: quickReplan,
                                  undo: undoAI,
                                  openPro: { aiShowPro = true })
                }

                // 送れていない直し（圏外・断られた・別の端末の変更）。日付の下・日程の上に残す。
                // UI テストの見本のときだけ、自動保存が送った回数を**見えない要素**に重ねる（`TripPlanFixture`・Debug のみ）
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    autosaveBanner
                }
                .overlay(alignment: .topLeading) { fixtureSendsLabel }

                // 電波なしで使えるようにする（板 72・日付の下）。比べるのはサーバーの姿のプラン。
                // 2026-11-16 判断（A6）: ここに出すのは Pro の人の札だけ。Pro でない人の「PRO」の案内は最後の日の下
                offlineSlot(plan, .top)

                if let error = model.errorMessage {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                }

                if days.isEmpty {
                    Text(L("まだ日程がありません。下から追加してください。", "No days yet. Add one below."))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                }
                // 組み直した案を見ている間は、日程の所に案を出す（読むだけ。置き換えるまで日程は変えない・札 #667）
                if let proposal = replan {
                    TripReplanPreview(proposal: proposal, showingAfter: $replanShowingAfter,
                                      heading: { di, day in dayHeading(di, day) },
                                      resolve: { TripDraft.place(for: $0, index: index, places: places, loading: !indexTried) })
                } else {
                    // 通し番号（1日目 1・2、2日目 3 …・板 TripPlanDays）。圏外の画面・地図の画像の点と同じ数え方
                    let numbers = TripStyle.stopNumbers(days.map(\.items.count))
                    ForEach(Array(days.enumerated()), id: \.offset) { di, day in
                        daySection(di, day, numbers: numbers.indices.contains(di) ? numbers[di] : [], layout: layout,
                                   isToday: di == today)
                            .padding(.top, di == 0 ? 0 : JPSpace.xs)
                            .id(Self.dayAnchor(di))
                    }

                    addDayButton
                }
                // 日程の下（Group は並びの間隔を変えない。ViewBuilder の子は 10 までなのでまとめる）
                Group {
                    // 出どころ（移動の見込みを1つでも出したとき・日程のいちばん下）
                    if layout.all.contains(where: { !estimates(for: $0).isEmpty }) {
                        Text(TripTravel.sourceNote)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    } else if travel.throttled {
                        Text(TripTravel.throttledNote)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    }
                    // Pro でない人の「電波なしで使えるようにする PRO」（2026-11-16 判断・A6: 日付と1日目の間から、最後の日の下へ）
                    offlineSlot(plan, .bottom)
                    deleteCard(plan)
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd)
        }
        // 組み直した案の「元に戻す」「この案にする」（案1の模型・下に固定する帯）
        .safeAreaInset(edge: .bottom) {
            if replan != nil {
                TripReplanActions(working: replanWorking != nil, discard: discardReplan, accept: acceptReplan)
            }
        }
        // 旅の日にホームの札から開いた: 今日の日まで送る（日程が読めて、今日の日があるときの1回だけ・A2）
        .onChange(of: today, initial: true) { _, index in
            scrollToToday(index, proxy: proxy)
        }
    }

    /// 今日の日まで送る（開いたときの1回だけ・`opensToday` のときだけ）
    private func scrollToToday(_ index: Int?, proxy: ScrollViewProxy) {
        guard opensToday, !scrolledToToday, let index else { return }
        scrolledToToday = true
        Task { @MainActor in
            // 並びが組み上がってから送る（読めた直後のコマでは、まだ下の日の高さが決まっていない）
            try? await Task.sleep(nanoseconds: 120_000_000)
            proxy.scrollTo(Self.dayAnchor(index), anchor: .top)
        }
    }

    /// 電波なしの札（上か下）。**この場所に出す姿のときだけ並びに置く**（出さない側に高さ 0 の札を置くと、縦の間隔 14 が
    /// 余分に空く）。Pro かどうかは画面が読む（`offlinePro`・`editor` の `.task`）
    @ViewBuilder
    private func offlineSlot(_ plan: TripPlan, _ slot: OfflineTripCard.Slot) -> some View {
        if OfflineTripCard.shows(OfflineTripCard.phase(plan: plan, offline: offline, isPro: offlinePro), in: slot) {
            OfflineTripCard(plan: plan, index: index, places: places, sourcesReady: gotIndex && gotPhotos,
                            slot: slot, isPro: $offlinePro)
        }
    }

    /// 日の節の目印（今日の日まで送る `scrollTo` の先）
    nonisolated static func dayAnchor(_ di: Int) -> String { "tripPlan.day.\(di)" }

    /// 今日の日（0 から）。日付の無いプラン・旅の前と後は nil（`TripPlanText.todayIndex`・端末の時刻帯の今日）
    private var todayIndex: Int? {
        TripPlanText.todayIndex(days: days, start: start, end: end, now: Date(), in: .current)
    }

    // MARK: - 日付

    /// 「日付」の欄（2026-11-16 判断・使い勝手の見直し A5）。**出発と帰着の2つの欄を1つにした。**
    /// 押すと作る流れと同じ暦と近くの休みがシートで開く（`TripPlanDatesSheet`）。押す回数は 欄 → 出発 → 帰着 の 3
    /// （休みのチップなら 2）。前は2つの欄で端末の日付の選び方を2回開いていた（約9回）。
    /// 板 TripPlanDays の `.dt`（52 の箱・上に 12 の名前・下に 15 の日付・surface-2・白 8% の縁・角 12）はそのまま。
    /// 上の小さい字に泊数を添える（「日付　1 泊 2 日」・模型 A5）。日付の無いプランは「日付を入れる」。
    /// **開いただけでは日付を書き換えない**（Web で作った「帰着が出発より前」のプランもそのまま見せる・`periodField`）
    private func dateField() -> some View {
        let field = TripDraft.periodField(start: start, end: end)
        return Button {
            editingDates = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(field?.label ?? L("日付", "Dates"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                Text(field?.value ?? L("日付を入れる", "Set dates"))
                    .font(field == nil ? JPFont.body : JPFont.number(JPTypeScale.body, weight: .regular))
                    .foregroundStyle(field == nil ? WebTheme.text2 : WebTheme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: TripStyle.dateFieldHeight, alignment: .leading)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(field.map { $0.label + L("、", ", ") + $0.value } ?? L("日付を入れる", "Set dates"))
        .accessibilityHint(L("押すと暦が開きます", "Opens the calendar"))
        .accessibilityIdentifier("tripPlan.dates")
    }

    /// 「仲間を誘う」（2026-11-16 判断・A6: 仲間の段から「日付」の欄と同じ行の右へ）。高さは欄と同じ 52・角 12・
    /// 白 14% の線。幅を取らないよう字は「誘う」（読み上げは「仲間を誘う」・模型 A6）。圏外の間は出さない（送れない）
    private func inviteButton(_ plan: TripPlan) -> some View {
        Button {
            Task { await invite(plan) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L("誘う", "Invite"))
                    .font(JPFont.footnote.weight(.semibold))
                    .fixedSize()
            }
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: TripStyle.dateFieldHeight)
            .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(shareWorking)
        .accessibilityLabel(TripShareText.invite)
        .accessibilityIdentifier("tripShare.invite")
    }

    // MARK: - 日ごと

    private var pickChoices: [TripPlanText.Choice] {
        TripPlanText.choices(wishlistKeys: wishlist.spotIds, places: places, index: index)
    }

    /// 候補の季節の一文（その日の月の季節の案内がある撮影スポットだけ・`TripDraft.seasonLine`）
    private func seasonLine(for choice: TripPlanText.Choice, day di: Int) -> String? {
        guard days.indices.contains(di),
              let ymd = TripPlanText.dayDate(index: di, day: days[di], start: start, end: end),
              let spot = spotFor(choice.item) else { return nil }
        return TripDraft.seasonLine(spot, ymd: ymd)
    }

    /// 候補のシートの眉に添える日付（「12月24日」）。日付の無いプランは nil
    private func pickDayDate(_ di: Int) -> String? {
        guard days.indices.contains(di),
              let date = TripPlanText.dayDate(index: di, day: days[di], start: start, end: end) else { return nil }
        return TakenDay.label(date)
    }

    /// 日の見出し（v2 の板 TripPlanDays: 真鍮の眉「1日目　12月24日」と右へ消える線）
    private func dayHeading(_ di: Int, _ day: TripDay, today: Bool = false) -> String {
        Self.dayHeadingText(di, date: TripPlanText.dayDate(index: di, day: day, start: start, end: end), today: today)
    }

    /// 見出しの字。今日の日は頭に「今日」（2026-11-16 判断・A2: 「今日　2 日目　12月17日」・模型 A2 の眉）
    nonisolated static func dayHeadingText(_ di: Int, date: String?, today: Bool) -> String {
        var head = L("\(di + 1)日目", "Day \(di + 1)")
        if today { head = L("今日\u{2002}", "Today\u{2002}") + head }
        if let label = TakenDay.label(date) {
            head += "\u{2002}\(label)"
        }
        return head
    }

    private func daySection(_ di: Int, _ day: TripDay, numbers: [Int], layout: TravelLayout,
                            isToday: Bool = false) -> some View {
        #if DEBUG
        if TripPlanFixture.isOn { TripPlanFixtureCounter.shared.daySectionCount += 1 }
        #endif
        let ymd = TripPlanText.dayDate(index: di, day: day, start: start, end: end)
        let resolved = day.items.map { TripDraft.place(for: $0, index: index, places: places) }
        let sun = TripDraft.sun(ymd: ymd, spots: daySpots(day))
        let legs = layout.legs(di)
        let estimatesByLeg = legs.map { estimates(for: $0) }
        // 着く時刻の目安（札 #677・案A・端末で計算・保存しない）。日付の無いプランは今日の日の入りで
        // 鍵は日付のある日はその日の日付（日を消す・組み直しでずれない・`TripStartStore`）
        let startMinutes = starts.minutes(planId: planId, ymd: ymd, day: di)
        let times = dayTimes(day, resolved: resolved, numbers: numbers, legs: legs, estimates: estimatesByLeg,
                             ymd: ymd, sun: sun, startMinutes: startMinutes)
        let showsTimes = !day.items.isEmpty
        let timesInColumn = !typeSize.isAccessibilitySize
        let timesInset: CGFloat = showsTimes && timesInColumn ? timeWidth + TripTimeStyle.columnGap : 0
        let startOpen = Binding(get: { openStartDay == di }, set: { openStartDay = $0 ? di : nil })
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                JPEyebrowLine(dayHeading(di, day, today: isToday))
                    .padding(.trailing, JPSpace.xs)
                // 出発の時刻（日の見出しの右・押す、選ぶの2回）。大きな字の設定では下の行へ
                if showsTimes && timesInColumn {
                    TripStartButton(start: startMinutes, open: startOpen)
                        .padding(.trailing, JPSpace.xxs)
                }
                // 地図で見る。**地図に置ける場所がある日だけ**（押しても空の地図を出さない）
                let stops = TripDayMap.stops(of: day, index: index, places: places, startNumber: numbers.first ?? 1)
                if TripDayMap.hasPins(stops) {
                    Button {
                        mapDay = MapTarget(day: di, stops: stops)
                    } label: {
                        Image(systemName: "map")
                            .foregroundStyle(WebTheme.text2)
                            .webTappable()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(di + 1) 日目を地図で見る", "Show day \(di + 1) on a map"))
                }
                // 日の操作（板 F34: 日の削除は「…」に畳む。赤いゴミ箱はプランの削除の1つだけ）
                Menu {
                    Button(role: .destructive) {
                        guard days.indices.contains(di) else { return }
                        if TripPlanEdit.confirmsRemoving(days[di]) {
                            removingDay = RemoveDayTarget(index: di, days: days)
                        } else {
                            removeDay(di, confirmedOn: days)
                        }
                    } label: {
                        Label(L("この日を削除", "Remove this day"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(WebTheme.text2)
                        .webTappable()
                }
                .accessibilityLabel(L("\(di + 1) 日目の操作", "Day \(di + 1) actions"))
                .accessibilityIdentifier("tripPlan.dayMenu")
            }

            // 今日の日は、日の出の行から追加の行までを札で囲む（`TripTodayFrame`・2026-11-16 判断・A2）
            VStack(alignment: .leading, spacing: 0) {
            // 日の出・日の入り（端末の計算）・同じ時間帯の重なり・間に合わないとき（計算した数だけ）
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                if showsTimes && !timesInColumn {
                    TripStartButton(start: startMinutes, open: startOpen)
                }
                if showsTimes && openStartDay == di {
                    TripStartChips(start: startMinutes) { m in
                        starts.set(m, planId: planId, ymd: ymd, day: di)
                        // 時刻と一緒に今の日程を覚える（閉じている間に日程が変わっても、開いたときに運べる・札 #685）
                        starts.sync(planId: planId, to: startSlots)
                        openStartDay = nil
                    }
                }
                if showsTimes {
                    TripTimeNote()
                }
                if let sun, let line = TripSunText.line(sun) {
                    TripDayNote(text: line, symbol: "sun.max")
                }
                if let overlap = TripDraft.overlapNote(resolved.map(\.times)) {
                    TripDayNote(text: overlap, symbol: "exclamationmark.circle", strong: true)
                }
                if let warning = TripTravel.dayWarning(
                    // その日の移動だけを数える（前の日からの区間は朝の移動で、昼の長さと比べない）
                    travel: TripTravel.dayTravel(legs, estimates: estimatesByLeg),
                    lateNames: legs.map { leg in leg.crossesDay ? nil : Self.lateName(leg, resolved: resolved, numbers: numbers) },
                    sun: sun) {
                    TripDayNote(text: warning, symbol: "clock.badge.exclamationmark", strong: true)
                        .accessibilityIdentifier("tripPlan.dayWarning")
                }
            }
            .padding(.bottom, JPSpace.xxs)

            // v2: 札で囲まず、行の下に白 8% の区切り線（板 TripPlanDays の `.st`）
            VStack(spacing: 0) {
                // 札は**消える日の箱の中の先頭**に開く（別の箱にすると、どちらが消えるのか分かりにくい・
                // プランの削除の札も押したボタンと同じ箱の中）
                if isConfirmingRemove(di) {
                    removeDayConfirm(di)
                    divider
                }
                if day.items.isEmpty {
                    Text(L("まだ何も入っていません。", "Nothing planned."))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                        .frame(maxWidth: .infinity, minHeight: JPHeight.row, alignment: .leading)
                        .dropDestination(for: String.self) { items, _ in
                            drop(items.first, toDay: di, toItem: nil)
                        } isTargeted: { setDropTarget($0, DropSpot(day: di, item: nil)) }
                    divider
                }
                ForEach(Array(day.items.enumerated()), id: \.offset) { ii, item in
                    let number = numbers.indices.contains(ii) ? numbers[ii] : ii + 1
                    // 場所の上に、前の場所からの区間（1 日目の最初の場所の上には無い。2 日目以降の最初は前の日から）。
                    // 区間の行は**区切り線で挟まない**（縦の線で前後の場所をつなぐ・2026-11-11）
                    if let leg = legs.first(where: { $0.to.number == number }), ii > 0 || leg.crossesDay {
                        let index = legs.firstIndex(where: { $0.id == leg.id }) ?? 0
                        legRow(leg, estimates: estimatesByLeg.indices.contains(index) ? estimatesByLeg[index] : [],
                               sun: sun, toTimes: resolved.indices.contains(ii) ? resolved[ii].times : [],
                               fromTimes: numbers.firstIndex(of: leg.from.number)
                                   .flatMap { resolved.indices.contains($0) ? resolved[$0].times : nil } ?? [],
                               date: ymd)
                        // 時刻の列のぶん右へ（区間の縦の線を番号の丸にそろえる。区間の行の左には時刻を置かない）
                        .padding(.leading, timesInset)
                    } else if ii > 0 {
                        divider
                    }
                    let timeRow = times.rows.indices.contains(ii) ? times.rows[ii] : TripTimes.Row(arrive: nil)
                    // 夜・夕方の場所の前のあき（「日の入り 16:32 まで 1時間55分あき」）
                    if showsTimes, let wait = TripTimes.waitLine(timeRow), let at = timeRow.arrive {
                        TripTimeMinorRow(time: at - timeRow.wait, text: wait, inColumn: timesInColumn, width: timeWidth,
                                         identifier: "trip.time.wait")
                    }
                    itemRow(di, ii, item, number: number,
                            season: spotFor(item).flatMap { TripDraft.seasonLine($0, ymd: ymd) },
                            chips: resolved.indices.contains(ii)
                                ? TripDraft.timeChips(resolved[ii].times, arrive: showsTimes ? timeRow.arrive : nil) : [],
                            time: showsTimes ? timeRow : nil)
                    if showsTimes, ii == day.items.count - 1, let end = times.end {
                        TripTimeMinorRow(time: end, text: L("ごろ 終わり", "done"), spoken: TripTimes.endLine(end),
                                         inColumn: timesInColumn, width: timeWidth, identifier: "trip.time.end")
                    }
                    // 場所が1か所だけ: 移動の目安が出ない理由を、その場所の下に1行で（2026-11-11）。
                    // 区切り線は日の最後の1本だけ（1行を線で挟まない・確かめ役の指摘）
                    if let single = layout.single, single.number == number {
                        TripDayNote(text: single.hint, symbol: "arrow.triangle.swap")
                            .padding(.bottom, JPSpace.xs)
                            .accessibilityIdentifier("trip.leg.singleHint")
                    }
                    if ii == day.items.count - 1 { divider }
                }
                // 外した場所（この画面を開いている間・日の下・「戻す」で外したときの位置へ）
                ForEach(TripPlanEdit.shelf(removedShelf, day: di, days: days)) { removed in
                    removedRow(removed)
                }
                addRow(di, full: day.items.count >= TripPlanService.itemsPerDayMax, compact: !day.items.isEmpty)
                    .overlay(alignment: .top) { dropLine(DropSpot(day: di, item: nil)) }
                    .dropDestination(for: String.self) { items, _ in
                        drop(items.first, toDay: di, toItem: nil)
                    } isTargeted: { setDropTarget($0, DropSpot(day: di, item: nil)) }
            }
            }
            .modifier(TripTodayFrame(on: isToday))
        }
    }

    /// その日の着く時刻の目安（札 #677）。滞在は観光スポットの種類から、移動は区間の見込み（`TripTimes.planMoves`）
    private func dayTimes(_ day: TripDay, resolved: [TripDraft.Place], numbers: [Int], legs: [TripTravel.Leg],
                          estimates: [[TripTravel.Estimate]], ymd: String?, sun: TripDraft.Sun?,
                          startMinutes: Int) -> TripTimes.Day {
        guard !day.items.isEmpty else { return TripTimes.Day(rows: [], end: nil) }
        #if DEBUG
        let began = DispatchTime.now()
        defer { if TripPlanFixture.isOn { TripPlanFixtureCounter.shared.countTimes(began) } }
        #endif
        // 描くたびに呼ばれるので、撮影スポットは1回だけ引く（区間の見込みが届くたびに画面ごと描き直す）
        let spots = day.items.map(spotFor)
        let stops = day.items.indices.map { ii in
            TripTimes.Stop(name: resolved.indices.contains(ii) ? resolved[ii].name : "",
                           stay: TripTimes.stayMinutes(for: spots[ii]),
                           times: resolved.indices.contains(ii) ? resolved[ii].times : [])
        }
        let long = legs.indices.map { i in
            TripTravel.showsAsLong(legs[i], estimates: estimates[i],
                                   settled: travel.isSettled(legs[i], modes: TripTravel.modes(for: legs[i],
                                                                     transitAvailable: TravelEstimator.transitAvailable)))
        }
        let coords = day.items.indices.map { resolved.indices.contains($0) ? resolved[$0].coords : nil }
        let moves = TripTimes.planMoves(numbers: Array(numbers.prefix(day.items.count)), coords: coords, legs: legs,
                                        estimates: estimates, long: long)
        // 日付のある日は日の出の行と同じ計算を使い回す。日付の無いプランだけ今日で計算する
        let light = TripTimes.light(ymd != nil ? sun : TripDraft.sun(ymd: TripTimes.todayYMD(), spots: spots.compactMap { $0 }))
        return TripTimes.schedule(start: startMinutes, stops: stops, moves: moves, light: light)
    }

    /// その日の撮影スポット（日程の順）
    /// 出発の時刻を覚える日の鍵と場所（`TripStartStore.slots`）
    private var startSlots: [TripStartKeys.DaySlot] {
        TripStartKeys.slots(planId: planId, days: days, start: start, end: end)
    }

    private func daySpots(_ day: TripDay) -> [OfficialSpot] {
        day.items.compactMap(spotFor)
    }

    private func spotFor(_ item: TripItem) -> OfficialSpot? {
        guard case .spot(let id, _) = item else { return nil }
        return index.first { $0.spotId == id }
    }

    /// 区間の行き先が夕方の場所（夕方の斜光・日没後の案内）なら、その名前
    nonisolated static func lateName(_ leg: TripTravel.Leg, resolved: [TripDraft.Place], numbers: [Int]) -> String? {
        guard let at = numbers.firstIndex(of: leg.to.number), resolved.indices.contains(at) else { return nil }
        let times = resolved[at].times
        return times.contains("goldenHour") || times.contains("dusk") ? resolved[at].name : nil
    }

    /// 返った見込み（先に出す手段の順・最大2つ）
    private func estimates(for leg: TripTravel.Leg) -> [TripTravel.Estimate] {
        TripTravel.shown(TripTravel.modes(for: leg, transitAvailable: TravelEstimator.transitAvailable),
                         results: travel.results(for: leg))
    }


    private func legRow(_ leg: TripTravel.Leg, estimates: [TripTravel.Estimate], sun: TripDraft.Sun?,
                        toTimes: [String], fromTimes: [String], date: String?) -> some View {
        let modes = TripTravel.modes(for: leg, transitAvailable: TravelEstimator.transitAvailable)
        let settled = travel.isSettled(leg, modes: modes)
        return TripLegRow(leg: leg, estimates: estimates, settled: settled,
                          offline: isOffline, throttled: travel.throttled) {
            legTarget = LegTarget(leg: leg, estimates: estimates,
                                  mode: TripTravel.mapsMode(estimates, leg: leg, settled: settled),
                                  sun: sun, destinationTimes: toTimes,
                                  previousTimes: fromTimes,
                                  long: TripTravel.showsAsLong(leg, estimates: estimates, settled: settled),
                                  date: date)
        }
    }

    // MARK: - 運ぶ

    private func setDropTarget(_ targeted: Bool, _ spot: DropSpot) {
        #if DEBUG
        if TripPlanFixture.isOn {
            if targeted { TripPlanFixtureCounter.shared.targeted += 1 }
            TripPlanFixtureCounter.shared.mark("T\(targeted ? "+" : "-")\(spot.day).\(spot.item.map(String.init) ?? "add")")
        }
        #endif
        if targeted { dropTarget = spot } else if dropTarget == spot { dropTarget = nil }
    }

    /// 落とす先の印（真鍮の 2pt の線・色だけでなく位置で伝える）
    @ViewBuilder
    private func dropLine(_ spot: DropSpot) -> some View {
        if dropTarget == spot {
            #if DEBUG
            if TripPlanFixture.isOn {
                // 見本のときだけ、線が出ているかを UI テストが数える（札 #521・(b) のあとに線が残るか）
                Rectangle().fill(WebTheme.accent).frame(height: 2)
                    .accessibilityElement()
                    .accessibilityIdentifier("tripPlan.dropLine")
                    .accessibilityLabel("\(spot.day).\(spot.item.map(String.init) ?? "add")")
            } else {
                Rectangle().fill(WebTheme.accent).frame(height: 2).accessibilityHidden(true)
            }
            #else
            Rectangle().fill(WebTheme.accent).frame(height: 2).accessibilityHidden(true)
            #endif
        }
    }

    /// 落とした。規則は `TripPlanEdit.dropped`（落とした時点の日程で項目を探し直す）
    private func drop(_ payload: String?, toDay: Int, toItem: Int?) -> Bool {
        dropTarget = nil
        #if DEBUG
        if TripPlanFixture.isOn {
            TripPlanFixtureCounter.shared.dropped += 1
            TripPlanFixtureCounter.shared.mark("D\(toDay).\(toItem.map(String.init) ?? "add")")
        }
        #endif
        guard let payload, let next = TripPlanEdit.dropped(days, payload: payload, toDay: toDay, toItem: toItem) else {
            #if DEBUG
            if TripPlanFixture.isOn {
                TripPlanFixtureCounter.shared.rejected += 1
                TripPlanFixtureCounter.shared.mark("R")
            }
            #endif
            return false
        }
        days = next
        #if DEBUG
        if TripPlanFixture.isOn { TripPlanFixtureCounter.shared.mark("S") }
        #endif
        return true
    }

    /// 札を出している日か。**押したときから日程が変わっていたら出さない**
    private func isConfirmingRemove(_ di: Int) -> Bool {
        guard let target = removingDay else { return false }
        return target.index == di && target.days == days
    }

    /// 日を消す。消せたら読み上げで知らせる（焦点は次の日のゴミ箱に残るので、消えたことが聞こえない）
    private func removeDay(_ di: Int, confirmedOn snapshot: [TripDay]) {
        removingDay = nil
        guard let next = TripPlanEdit.removeDay(days, at: di, snapshot: snapshot) else { return }
        days = next
        removedShelf = TripPlanEdit.shelfAfterRemovingDay(removedShelf, removedDay: di)
        announce(L("\(di + 1) 日目を削除しました", "Removed day \(di + 1)"))
    }

    /// 日を消す前の札（プランの削除の札と同じ形・v2 の板 OfflineSaveStates 5 の確かめと同じ部品）
    private func removeDayConfirm(_ di: Int) -> some View {
        JPDeleteConfirm(question: L("\(di + 1)日目と、その日の予定を削除しますか？", "Remove day \(di + 1) and its plans?"),
                        confirmTitle: L("削除する", "Remove"), identifier: "trip.day.remove") {
            guard let target = removingDay else { return }
            removeDay(di, confirmedOn: target.days)
        } onCancel: {
            removingDay = nil
        }
        .padding(.vertical, JPSpace.s)
    }

    private var divider: some View {
        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
    }

    private func itemRow(_ di: Int, _ ii: Int, _ item: TripItem, number: Int,
                         season: String?, chips: [TripDraft.TimeChip], time: TripTimes.Row? = nil) -> some View {
        let pending = TripPlanText.isPending(item, index: index, loading: !indexTried)
        // 2026-11-23 判断（確かめ役の指摘）: 骨組みの間は名前を「読み込み中」にし、「…」と ≡ と「替える」は出さない
        // （前は骨組みの横の「…」の読み上げと ≡ に「観光スポット（読み込めませんでした）」が出ていた）
        let name = TripPlanText.displayName(for: item, index: index, places: places, loading: !indexTried)
        // 右の印は「…」と ≡ の2つ（2026-11-12 判断・1.1.85・札 #570・資料「みんなで埋める旅行プラン」の場面7）。
        // - 2026-11-11 は「…」1つにして、並べ替えは行を押さえて運ぶ形だった。**どこを掴めば動くかが見えなかった**ので、
        //   行の右端に ≡ の持ち手を常に出す（owner「ドラッグアンドドロップで入れ替えたり…簡単に操作できるように」）
        // - 運ぶのは ≡ だけ。行のほかの所を押すと今どおり撮影スポットが開く（押した所と運ぶ所が混ざらない）
        // - 外すは今どおり「…」の中（誤って押しやすい × を行に置かない）
        // - 読み上げの人は ≡ を上下にスワイプで上へ・下へ、操作で「N日目へ」「外す」（`TripPlanEdit.accessibilityMoves`）
        // 右の印は今どおり「…」と ≡ の2つ。AI で作ったプランの「替える」は名前の下（番号の丸の右・36）に置く
        // （2026-11-15 確かめ役の指摘「右に3つが混み合う」。押す回数は替える1回のまま）
        // 自分の写真で埋まる（札 #710 の案3）: その日に撮った自分の1枚。今日のまだの観光スポットは点線の「＋」
        let ymd = days.indices.contains(di) ? TripPlanText.dayDate(index: di, day: days[di], start: start, end: end) : nil
        let mine = TripPlanPhotos.mine(for: item, on: ymd, mine: myPhotos)
        let invites = TripPlanPhotos.invites(item, on: ymd, today: TripPlanText.ymd(pickedIn: .current, Date()),
                                             hasPhoto: mine != nil)
        let thumb = TripPlanPhotos.thumb(mine: mine, spot: spotFor(item))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if pending {
                    TripStopSkeleton(number: number)
                } else {
                    itemLink(item, name: name, number: number, season: season, chips: chips, time: time, thumb: thumb)
                    TripStopPhotoSlot(invites: invites, name: name) { invitePost(item) }
                    itemMenu(di, ii, item, name: name)
                    dragHandle(di, ii, item, name: name)
                }
            }
            if !pending {
                TripStopPhotoLine(photo: mine, invites: invites)
                    .padding(.leading, thumb == nil ? 36 : 36 + TripStopThumbView.side + JPSpace.s)
                aiSwapButton(di, ii, item, name: name)
            }
        }
        .overlay(alignment: .top) { dropLine(DropSpot(day: di, item: ii)) }
        .dropDestination(for: String.self) { items, _ in
            drop(items.first, toDay: di, toItem: ii)
        } isTargeted: { setDropTarget($0, DropSpot(day: di, item: ii)) }
    }

    /// 点線の枠: その観光スポットを撮影地に入れて投稿の画面を開く（札 #710 の案3）。押す回数 枠 → 写真 → 投稿 = 3
    private func invitePost(_ item: TripItem) {
        guard case .spot(let spotId, _) = item, let spot = index.first(where: { $0.spotId == spotId }) else { return }
        stopPost = TripStopPostTarget(spot: UploadSpotTarget(spot))
    }

    /// 持ち手 ≡（行の右端・当たり 44pt・2026-11-12 札 #570）。押さえて運ぶ（同じ日の中も、別の日へも）。
    /// 読み上げでは**上下のスワイプで上へ・下へ**（調整できる要素）、操作で「N日目へ移す」「外す」
    private func dragHandle(_ di: Int, _ ii: Int, _ item: TripItem, name: String) -> some View {
        let moves = TripPlanEdit.accessibilityMoves(days, day: di, item: ii)
        return Image(systemName: "line.3.horizontal")
            .font(.body)
            .foregroundStyle(WebTheme.text2)
            .webTappable()
            .contentShape(Rectangle())
            .draggable(TripPlanEdit.dragPayload(day: di, item: ii, of: item)) { dragPreview(name) }
            .accessibilityLabel(L("「\(name)」を運ぶ", "Move \(name)"))
            .accessibilityValue(L("\(di + 1) 日目、\(ii + 1) 番目", "Day \(di + 1), item \(ii + 1)"))
            .accessibilityHint(L("上か下にスワイプで並べ替えます。押さえたまま運ぶと別の日へも移せます",
                                 "Swipe up or down to reorder. Touch and hold, then drag to move to another day."))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: perform(.up, di, ii, item, name: name)
                case .decrement: perform(.down, di, ii, item, name: name)
                @unknown default: break
                }
            }
            .accessibilityActions {
                ForEach(Array(moves.enumerated()), id: \.offset) { _, move in
                    Button(Self.moveTitle(move)) { perform(move, di, ii, item, name: name) }
                }
            }
            .accessibilityIdentifier("tripPlan.dragHandle")
    }

    /// 読み上げの操作の名前（「…」のメニューと同じ言葉）
    nonisolated static func moveTitle(_ move: TripPlanEdit.A11yMove) -> String {
        switch move {
        case .up: return L("上へ", "Move up")
        case .down: return L("下へ", "Move down")
        case .toDay(let to): return L("\(to + 1)日目へ移す", "Move to day \(to + 1)")
        case .remove: return L("この日程から外す", "Remove from this trip")
        }
    }

    /// 動かす・外す（持ち手の読み上げと「…」のメニューの両方から）。**押した時点の日程で同じ項目を探し直す**
    /// （描いた時点の位置で動かすと、その間に保存の応答で差し替わった姿を巻き戻す・`TripPlanEdit.locate`）
    private func perform(_ move: TripPlanEdit.A11yMove, _ di: Int, _ ii: Int, _ item: TripItem, name: String) {
        guard let at = TripPlanEdit.locate(days, day: di, item: ii, original: item) else { return notMoved(name) }
        switch move {
        case .up:
            guard let next = TripPlanEdit.moveUp(days, day: di, item: at) else { return notMoved(name) }
            apply(next, said: L("「\(name)」を \(di + 1) 日目の \(at) 番目へ移しました", "Moved \(name) to position \(at) on day \(di + 1)"))
        case .down:
            guard let next = TripPlanEdit.moveDown(days, day: di, item: at) else { return notMoved(name) }
            apply(next, said: L("「\(name)」を \(di + 1) 日目の \(at + 2) 番目へ移しました", "Moved \(name) to position \(at + 2) on day \(di + 1)"))
        case .toDay(let to):
            guard let next = TripPlanEdit.moveToDay(days, day: di, item: at, toDay: to) else { return notMoved(name) }
            apply(next, said: L("「\(name)」を \(to + 1) 日目へ移しました", "Moved \(name) to day \(to + 1)"))
        case .remove:
            // `removing` も押した時点の日程で探し直す（外した位置 `at` は控えに残す）
            guard let next = TripPlanEdit.removing(days, day: di, item: ii, original: item) else { return notMoved(name) }
            days = next
            // 外しても日の下に「外しました　戻す」を残す（この画面を開いている間・2026-11-12 モックの場面6）
            removedSeq += 1
            removedShelf.append(TripPlanEdit.Removed(id: removedSeq, day: di, index: at, item: item))
            announce(L("「\(name)」を外しました。日の下の「戻す」で戻せます", "Removed \(name). Use Restore below the day to undo."))
        }
    }

    /// 外した場所の行（日の下・点線の枠・打ち消した名前と「戻す」）。押す回数は 1（以前は戻す道が無く、足し直していた）
    private func removedRow(_ removed: TripPlanEdit.Removed) -> some View {
        let name = TripPlanText.displayName(for: removed.item, index: index, places: places, loading: !indexTried)
        let pending = TripPlanText.isPending(removed.item, index: index, loading: !indexTried)
        return HStack(spacing: JPSpace.xs) {
            if pending {
                TripStopSkeleton.bone(width: 120, height: 13)
                    .accessibilityLabel(L("読み込み中", "Loading"))
            } else {
                Text(name)
                    .strikethrough(true, color: WebTheme.text3)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("外しました", "Removed"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
            Spacer(minLength: JPSpace.xs)
            Button {
                restore(removed, name: name)
            } label: {
                // 線の小ボタン（見た目 36・当たり 44・`jpOutlineButton(.inline)`）
                Text(L("戻す", "Restore"))
                    .jpOutlineButton(.inline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("「\(name)」を戻す", "Restore \(name)"))
            .accessibilityIdentifier("tripPlan.restore")
        }
        .padding(.leading, JPSpace.s)
        .padding(.trailing, JPSpace.xxs)
        .overlay(RoundedRectangle(cornerRadius: JPRadius.field)
            .strokeBorder(WebTheme.outline, style: StrokeStyle(lineWidth: JPStroke.hairline, dash: [4, 3])))
        .padding(.vertical, JPSpace.xxs)
        .accessibilityElement(children: .contain)
    }

    /// 戻す。外したときの日・位置へ（入らなければ知らせる）
    private func restore(_ removed: TripPlanEdit.Removed, name: String) {
        removedShelf.removeAll { $0.id == removed.id }
        guard let next = TripPlanEdit.restoring(days, removed) else {
            // もう入っている（足し直した）なら控えを消すだけ。日が無い・いっぱいのときは知らせる
            if TripPlanEdit.dayContaining(removed.item, in: days) == nil { notMoved(name) }
            return
        }
        apply(next, said: L("「\(name)」を戻しました", "Restored \(name)"))
    }

    /// 運んでいる間の絵（見本のときだけ、持ち上がった回数を数える）
    private func dragPreview(_ name: String) -> some View {
        Text(name)
            .font(JPFont.bodyEmphasis)
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, JPSpace.s)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
            .onAppear {
                #if DEBUG
                if TripPlanFixture.isOn {
                    TripPlanFixtureCounter.shared.lifted += 1
                    TripPlanFixtureCounter.shared.mark("L")
                }
                #endif
            }
            .onDisappear {
                #if DEBUG
                if TripPlanFixture.isOn { TripPlanFixtureCounter.shared.mark("E") }
                #endif
            }
    }

    /// 項目の操作（2026-09-30）: 上へ・下へ・別の日へ・ひとこと。**規則は `TripPlanEdit`**
    /// （範囲外やいっぱいの日へは移さない）。上へ・下へは押せないとき無効（灰色）で残し、
    /// 「別の日へ移す」は移せる日が無いとき（1日だけ・ほかの日が全部いっぱい）出さない。
    /// 押せるかどうかも `TripPlanEdit` の答えから導く（判定を二重に持たない）
    private func itemMenu(_ di: Int, _ ii: Int, _ item: TripItem, name: String) -> some View {
        // 押せるかどうかは描いた時点の答えで決めてよい。**押したときの計算は、押した時点の
        // `days` から、その位置にまだこの項目があるかを確かめてやり直す**（描いた時点の
        // 日程を丸ごと持って入れると、その間に保存の応答で差し替わった姿を巻き戻す）
        let canUp = TripPlanEdit.moveUp(days, day: di, item: ii) != nil
        let canDown = TripPlanEdit.moveDown(days, day: di, item: ii) != nil
        let targets = TripPlanEdit.movableDays(days, from: di)
        return Menu {
            Button {
                perform(.up, di, ii, item, name: name)
            } label: { Label(L("上へ", "Move up"), systemImage: "arrow.up") }
            .disabled(!canUp)
            Button {
                perform(.down, di, ii, item, name: name)
            } label: { Label(L("下へ", "Move down"), systemImage: "arrow.down") }
            .disabled(!canDown)
            // 移せる日が1つだけなら、日を選ぶ段を挟まず「2日目へ移す」と直接出す（押す回数 3 → 2・2026-11-12）
            if let only = TripPlanEdit.directMoveTarget(days, from: di) {
                Button {
                    perform(.toDay(only), di, ii, item, name: name)
                } label: { Label(Self.moveTitle(.toDay(only)), systemImage: "calendar") }
            } else if !targets.isEmpty {
                Menu {
                    ForEach(targets, id: \.self) { to in
                        Button(L("\(to + 1)日目", "Day \(to + 1)")) {
                            perform(.toDay(to), di, ii, item, name: name)
                        }
                    }
                } label: { Label(L("別の日へ移す", "Move to another day"), systemImage: "calendar") }
            }
            Button {
                noteText = item.note ?? ""
                noteTarget = NoteTarget(day: di, item: ii, original: item)
            } label: {
                Label(item.note == nil ? L("ひとことを書く", "Add a note") : L("ひとことを直す", "Edit note"),
                      systemImage: "text.bubble")
            }
            // 外す（2026-11-11: 行の × をここへ畳んだ）。押した時点の日程で同じ項目を探し直す。
            // 外しても日の下に「戻す」が残る（2026-11-12）
            Button(role: .destructive) {
                perform(.remove, di, ii, item, name: name)
            } label: {
                Label(L("この日程から外す", "Remove from this trip"), systemImage: "minus.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(WebTheme.text3)
                .webTappable()
        }
        // 画面の下のほうで上に開いても、上へ・下へが逆さに並ばないようにする
        .menuOrder(.fixed)
        .accessibilityLabel(L("「\(name)」の操作", "Actions for \(name)"))
        // 行の身元は位置なので、並べ替えのあと読み上げの焦点は同じ位置に残る。
        // 位置を値として読ませ、動かした結果は `apply` が読み上げる
        .accessibilityValue(L("\(di + 1) 日目、\(ii + 1) 番目", "Day \(di + 1), item \(ii + 1)"))
    }

    // MARK: - AI で作ったプラン（札 #621）

    /// 開いたとき: まだ見ていない印を消し、移動が無理で外した場所を日の下の「外しました　戻す」へ移す
    private func adoptAINote() {
        TripAIJobs.shared.markSeen(planId)
        for r in aiNotes.takeRemoved(planId) {
            removedSeq += 1
            removedShelf.append(TripPlanEdit.Removed(id: removedSeq, day: r.day, index: Int.max,
                                                     item: TripDraft.place(spot: r.spot).item))
        }
    }

    /// 「替える」（AI を使わない）。候補の残りから近い順に3つ
    @ViewBuilder
    private func aiSwapButton(_ di: Int, _ ii: Int, _ item: TripItem, name: String) -> some View {
        if let note = aiNotes.note(planId), !note.candidates.isEmpty, case .spot(let id, _) = item,
           let spot = index.first(where: { $0.spotId == id }) ?? note.candidates.first(where: { $0.spotId == id }) {
            Button {
                aiSwap = TripAISwapTarget(day: di, item: ii, spot: spot)
            } label: {
                Text(L("替える", "Swap"))
                    .jpOutlineButton(.inline)
            }
            .buttonStyle(.plain)
            // 番号の丸の右（名前の頭）にそろえる。AI のプランでないときは何も出さない（余白も作らない）
            .padding(.leading, TripStyle.stopNumberSide + JPSpace.s + timeLeading)
            .accessibilityLabel(L("「\(name)」を近くの別の所に替える", "Swap \(name) for a nearby place"))
            .accessibilityIdentifier("tripAI.swap")
        }
    }

    private func swapAI(_ target: TripAISwapTarget, to spot: OfficialSpot) {
        guard days.indices.contains(target.day), days[target.day].items.indices.contains(target.item) else { return }
        var next = days
        next[target.day].items[target.item] = TripDraft.place(spot: spot).item
        aiHistory.append(TripReplan.Step(before: days, after: next))
        apply(next, said: L("\(target.spot.name)を\(spot.name)に替えました", "Swapped \(target.spot.name) for \(spot.name)"))
    }

    private func undoAI() {
        guard let last = aiHistory.popLast() else { return }
        // 置き換えたときに棚へ回した場所は、戻すと日程に戻るので棚から外す（二重に「戻す」を出さない）
        let added = Set(last.shelf)
        removedShelf.removeAll { added.contains($0.id) }
        // 置き換えた後に入った変更（仲間の変更など）は残し、置き換えで変えた分だけを戻す（`TripReplan.undo`）
        apply(TripReplan.undo(last, current: days), said: L("前の日程に戻しました", "Restored the previous plan"))
    }

    /// 組み直しを始める（前の手順は取り消す。画面を閉じたら `onDisappear` で取り消す）
    private func runReplan(label: String, request: String, typed: Bool) {
        guard replanWorking == nil else { return }
        replanTask?.cancel()
        replanTask = Task { await startReplan(label: label, request: request, typed: typed) }
    }

    // MARK: - 組み直す（札 #667）

    /// 観光スポットが1つでも入っているか（組み直しの列を出すか）
    private var hasReplanSpots: Bool {
        days.contains { day in day.items.contains { if case .spot = $0 { return true } else { return false } } }
    }

    /// 「雨なら」「もっとゆっくり」・打った条件で組み直し、案を出す（**日程はまだ変えない**）。
    ///
    /// 2026-11-20 判断（owner 承認の案1・札 #667）:
    /// - 打った条件は AI を呼ぶ前に `AskGuard` で断る（作りやセキュリティの質問。回数も使わない）
    /// - AI に渡すのは、このプランの観光スポット（公開の台帳）・日付・条件だけ。撮影地、ひとこと、仲間のことは渡さない
    /// - 回数は旅行プランの AI と同じ枠。端末の AI は案を出す直前に1回取る（`TripAIRunner.revise(countAfter:)`）
    private func startReplan(label: String, request: String, typed: Bool) async {
        guard replanWorking == nil, let plan else { return }
        replanNotice = nil
        replanNoticePro = false
        if typed, TripReplan.refusesTyped(request) {
            replanNotice = TripReplan.refusalLine(request)
            return
        }
        let note = aiNotes.note(planId)
        let lookup = Dictionary((index + (note?.candidates ?? [])).map { ($0.spotId, $0) }, uniquingKeysWith: { a, _ in a })
        let current: [[OfficialSpot]] = days.map { day in
            day.items.compactMap { item in
                if case .spot(let id, _) = item { return lookup[id] }
                return nil
            }
        }
        let before = days
        replanWorking = label
        defer { replanWorking = nil }
        if aiRunner.usage == nil { await aiRunner.loadUsage(service: environment.tripAI) }
        let result = await aiRunner.revise(request: TripReplan.request(condition: request, start: start, end: end),
                                           current: current, candidates: note?.candidates ?? [], index: index,
                                           offline: connectivity.isOffline, service: environment.tripAI,
                                           title: plan.title, countAfter: true)
        if Task.isCancelled { return }
        // 「AI に送らなかった」の札から同意して送ったら、札の帯の理由を替える（`TripReplan.noteMode`・Mac run 1729）
        if var now = aiNotes.note(planId), TripReplan.noteMode(after: result, current: now.mode) != now.mode {
            now.mode = TripReplan.noteMode(after: result, current: now.mode)
            aiNotes.set(planId, now)
        }
        if let result, let proposal = TripReplan.proposal(label: label, before: before, current: current, result: result) {
            replanShowingAfter = true
            replan = proposal
            announce(L("組み直した案を出しました。入れ替えた所は\(proposal.changedCount)か所です",
                       "Here's a new plan. Changed: \(proposal.changedCount)"))
        } else {
            let tier = aiRunner.usage?.tier
            let isPro = tier == "pro" || tier == "admin"
            replanNotice = TripReplan.failureLine(result, isPro: isPro)
            replanNoticePro = TripReplan.opensPro(result, isPro: isPro)
            if let line = replanNotice { announce(line) }
        }
    }

    /// 「この案にする」。今の日程を控えてから置き換える（「元に戻す」で戻せる）。共有したプランは、置き換えた日程を
    /// ふだんの自動保存（版 rev を添えて送る・409 なら読み直して重ね直す）で送る。案を見ている間に仲間の変更が届いていたら、
    /// その上に案で変えた分だけを重ねる（`TripReplan.accept`）
    private func acceptReplan() {
        guard let proposal = replan else { return }
        guard replanWorking == nil else { return }
        let next = TripReplan.accept(proposal, current: days)
        var added: [Int] = []
        for d in proposal.dropped {
            removedSeq += 1
            removedShelf.append(TripPlanEdit.Removed(id: removedSeq, day: d.day, index: d.index, item: d.item))
            added.append(removedSeq)
        }
        aiHistory.append(TripReplan.Step(before: days, after: next, shelf: added))
        replan = nil
        apply(next, said: L("プランを入れ替えました", "Plan replaced"))
        toasts.show(L("プランを入れ替えました", "Plan replaced"))
        if let note = aiNotes.note(planId) {
            aiNotes.set(planId, TripAINote(reason: proposal.reason.isEmpty ? note.reason : proposal.reason, mode: .ai,
                                           removed: [], candidates: note.candidates, autoPlace: note.autoPlace))
        }
    }

    /// 案の「元に戻す」（案をやめる。日程は初めから変えていない）
    private func discardReplan() {
        replan = nil
        announce(L("今の日程のままにしました", "Kept your current plan"))
    }

    /// 「雨なら」「もっとゆっくり」（2026-11-24 判断・`TripQuickReplan`）。AI を使わずに**押したらすぐ**組み直す。
    /// 外した所は日の下の「外しました　戻す」へ、知らせの帯と組み直しの列の「元に戻す」で戻せる。変わらなければ帯で理由を言う
    private func quickReplan(_ tweak: TripAITweak) {
        guard replanWorking == nil, replan == nil else { return }
        replanNotice = nil
        replanNoticePro = false
        let note = aiNotes.note(planId)
        let lookup = Dictionary((index + (note?.candidates ?? [])).map { ($0.spotId, $0) }, uniquingKeysWith: { a, _ in a })
        let result: TripQuickReplan.Result
        switch tweak {
        case .slow:
            result = TripQuickReplan.slower(days) { item in
                if case .spot(let id, _) = item { return lookup[id]?.coords }
                return nil
            }
        case .rain:
            result = TripQuickReplan.rain(days, spots: lookup, pool: index + (note?.candidates ?? []))
        }
        guard result.changed else {
            replanNotice = result.line
            announce(result.line)
            return
        }
        var added: [Int] = []
        for d in result.dropped {
            removedSeq += 1
            removedShelf.append(TripPlanEdit.Removed(id: removedSeq, day: d.day, index: d.index, item: d.item))
            added.append(removedSeq)
        }
        let step = TripReplan.Step(before: days, after: result.days, shelf: added)
        aiHistory.append(step)
        apply(result.days, said: result.line)
        // 帯の「元に戻す」は、この組み直しがまだいちばん新しいときだけ戻す（あとで別の組み直しをしていたら、列の「元に戻す」で順に戻す）
        toasts.show(result.line, undo: ToastCenter.Undo(
            title: L("元に戻す", "Undo"),
            failure: L("このあとに別の組み直しをしたので、日程の上の「元に戻す」から戻してください",
                       "You've rearranged again since. Use Undo above the plan.")) {
            guard aiHistory.last == step else { return false }
            undoAI()
            return true
        })
    }

    /// 並べ替え・移動を映し、結果を読み上げる（目で追えない人に、項目がどこへ行ったかを伝える）
    private func apply(_ next: [TripDay], said: String) {
        days = next
        announce(said)
    }

    /// 押したときに項目が見つからなかった（メニューを開いている間に日程が差し替わった）。
    /// **黙って何もしないと、押しても効かなかったように見える**——下の帯で知らせ、読み上げでも伝える
    /// （2026-11-25 判断・窓をやめた。もう一度しても同じなので「閉じる」）
    private func notMoved(_ name: String) {
        fail(.move, L("「\(name)」は項目が変わったため動かせませんでした。もう一度お試しください。",
                      "\(name) couldn't be moved because the item changed. Please try again."))
    }

    // MARK: - 失敗の帯（2026-11-25 判断・人間工学の案 2・`TripPlanFailure`）

    /// 失敗を下の帯に出す。送り直せる失敗は `retry` を「もう一度」に結ぶ。読み上げでも1回伝える
    private func fail(_ kind: TripPlanFailure.Kind, _ detail: String, retry: (() -> Void)? = nil) {
        let next = TripPlanFailure(kind: kind, detail: detail, serial: (failure?.serial ?? 0) + 1)
        failureRetry = TripPlanRetry(next.canRetry ? retry : nil)
        failureDrag = .zero
        withAnimation(.easeOut(duration: 0.24)) { failure = next }
        // 上に別の画面を積んでいる間は鳴らさない（戻ったら帯が見える）
        if onTop { announce(next.spoken(offline: isOffline)) }
    }

    private func clearFailure() {
        failureRetry = TripPlanRetry()
        failureDrag = .zero
        withAnimation(.easeOut(duration: 0.2)) { failure = nil }
    }

    /// 「保存して戻る」。送れたら戻る。送れなければ下の帯に残し、「もう一度」で同じことをする
    private func saveAndLeave() {
        Task {
            if await flush(force: true) {
                clearFailure()
                dismiss()
            } else {
                fail(.save, Self.problemText(problem, shared: plan?.share != nil), retry: { saveAndLeave() })
            }
        }
    }

    /// 下の帯（デザインの板の「状態の帯」`JPStateBand`・黒地の上の札）。横か下へ払うと閉じる
    @ViewBuilder
    private var failureBand: some View {
        if let failure {
            JPStateBand(kind: isOffline && failure.canRetry ? .offline : .partial,
                        title: failure.title, message: failure.message(offline: isOffline),
                        actionTitle: failure.actionTitle,
                        isBusy: failure.canRetry && model.busy != nil,
                        actionIdentifier: "tripPlan.failure.action") {
                // 取り出すのは1回だけ（続けて押しても2回は送らない）
                let retry = failureRetry.take()
                clearFailure()
                retry?()
            }
            .accessibilityIdentifier("tripPlan.failure")
            // 送り直せる帯は右の小ボタンが「もう一度」なので、払えない人に「閉じる」を読み上げの操作で足す
            .accessibilityAction(named: L("閉じる", "Close")) { clearFailure() }
            .offset(x: failureDrag.width, y: max(0, failureDrag.height))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { failureDrag = $0.translation }
                    .onEnded { value in
                        if TripPlanFailure.swipeCloses(dx: Double(value.translation.width),
                                                       dy: Double(value.translation.height)) {
                            clearFailure()
                        } else {
                            // 動きを減らす設定では弾ませずに戻す
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { failureDrag = .zero }
                        }
                    }
            )
            .padding(.horizontal, JPSpace.gutter)
            .padding(.bottom, JPSpace.xs)
            // 動きを減らす設定では濃さだけで出し入れする
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .id(failure.serial)
        }
    }

    /// 読み上げを出す。**少し遅らせる**——メニューが閉じると焦点が「…」に戻ってその名前を
    /// 読み始め、同時に出した読み上げは割り込まれて消えることがある
    private func announce(_ text: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    /// 名前を押すとその場所へ。**開ける先が無いものは行だけ**（押しても何も起きない札を作らない）
    @ViewBuilder
    private func itemLink(_ item: TripItem, name: String, number: Int, season: String?, chips: [TripDraft.TimeChip],
                          time: TripTimes.Row? = nil, thumb: TripStopThumb? = nil) -> some View {
        switch item {
        case .spot(let spotId, _):
            if let spot = index.first(where: { $0.spotId == spotId }) {
                NavigationLink {
                    OfficialSpotView(spot: spot, spots: index, photos: photos, photosKnown: gotPhotos)
                } label: {
                    itemLabel(name, number: number, isSpot: true, note: item.note, season: season, chips: chips, by: addedByText(item), time: time,
                              thumb: thumb)
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, number: number, isSpot: true, note: item.note, season: season, chips: chips, by: addedByText(item), time: time,
                          thumb: thumb)
            }
        case .location(let slug, _):
            if let place = places.first(where: { $0.slug == slug }) {
                NavigationLink {
                    SpotDetailView(spot: place, photos: photos)
                } label: {
                    itemLabel(name, number: number, isSpot: false, note: item.note, season: nil, chips: [], by: addedByText(item), time: time,
                              thumb: thumb)
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, number: number, isSpot: false, note: item.note, season: nil, chips: [], by: addedByText(item), time: time,
                          thumb: thumb)
            }
        }
    }

    /// 行の中身（v2 の板 TripPlanDays・F30: 番号の丸 → 名前 → 季節の一文と時間帯の札 → ひとこと・`TripStopLabel`）
    private func itemLabel(_ name: String, number: Int, isSpot: Bool, note: String?,
                           season: String?, chips: [TripDraft.TimeChip], by: TripShareText.AddedBy? = nil, time: TripTimes.Row? = nil,
                           thumb: TripStopThumb? = nil) -> some View {
        let byLeading: CGFloat = time == nil ? 36 : 36 + timeLeading
        return VStack(alignment: .leading, spacing: 2) {
            TripStopLabel(number: number, name: name, isSpot: isSpot, season: season, timeChips: chips, note: note,
                          time: time?.arrive, showsTime: time != nil, timeCaution: time.flatMap(TripTimes.cautionLine),
                          thumb: thumb)
            // 共有したプランで、ほかの仲間が足した場所（「あおが足しました」）。名前は太く明るく、続きは細く暗く
            // ——空白で区切らない（2026-11-23 判断）
            if let by {
                (Text(by.lead).foregroundStyle(WebTheme.text3)
                    + Text(by.name).fontWeight(.semibold).foregroundStyle(WebTheme.text2)
                    + Text(by.tail).foregroundStyle(WebTheme.text3))
                    .font(JPFont.caption)
                    .accessibilityLabel(by.text)
                    .padding(.leading, byLeading)
                    .accessibilityIdentifier("tripPlan.addedBy")
            }
        }
    }

    /// 時刻の列のぶんの左の余白（大きな字の設定では列を作らないので 0・札 #677）
    private var timeLeading: CGFloat {
        typeSize.isAccessibilitySize ? 0 : timeWidth + TripTimeStyle.columnGap
    }

    private func addedByText(_ item: TripItem) -> TripShareText.AddedBy? {
        guard let plan else { return nil }
        return TripShareText.addedBy(plan, item, members: members, me: auth.userId)
    }

    // MARK: - 仲間（2026-11-12・札 #553）

    private var tab: Binding<TripShareText.Tab> {
        Binding(get: { chosenTab ?? startTab }, set: { chosenTab = $0 })
    }

    /// 題・出発と帰着・仲間の段（日程の画面の頭。式を分けて型の推論を軽くする）
    private func header(_ plan: TripPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 題（v2 の板 TripPlanDays: 明朝の大見出し・Title 1）
            Text(plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title)
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)

            // 「日付」の欄と、その右に「誘う」（2026-11-16 判断・A5・A6）。誘うは圏外の間は出さない（送れない）
            HStack(spacing: JPSpace.xs) {
                dateField()
                if !isOffline { inviteButton(plan) }
            }

            // 仲間（共有する・人数と顔・「日程 | 会話」・2026-11-12）。圏外の間は出さない（送れない）。
            // 誘うは上の行へ移したので、出すものが無いプラン（共有していない・DM の相手もいない）は段ごと置かない
            shareSection(plan)
        }
        .sheet(isPresented: $editingDates) {
            TripPlanDatesSheet(start: start, end: end) { s, e in
                start = s
                end = e
            }
        }
    }

    @ViewBuilder
    private func shareSection(_ plan: TripPlan) -> some View {
        if !isOffline, TripShareStrip.hasContent(plan: plan, peer: sharePeer, showsInvite: false) {
            shareStrip(plan, showsInvite: false)
        }
    }

    private func shareStrip(_ plan: TripPlan, showsInvite: Bool = true) -> TripShareStrip {
        TripShareStrip(plan: plan, members: members, peer: sharePeer, working: shareWorking,
                       tab: tab, chatUnread: chatUnread,
                       onShareWithPeer: { Task { await share(with: sharePeer) } },
                       onInvite: { Task { await invite(plan) } },
                       showsInvite: showsInvite)
    }

    /// 会話の画面（題・仲間の段・切り替えは日程と同じ所に置き、下に会話と入力欄）
    private func chatScreen(_ plan: TripPlan) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            Text(plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title)
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, JPSpace.gutter)
            shareStrip(plan).padding(.horizontal, JPSpace.gutter)
            TripChatPane(planId: planId, plan: plan, members: members,
                         resolveName: { TripPlanText.displayName(for: $0, index: index, places: places, loading: !indexTried) })
        }
        .padding(.top, JPSpace.xs)
        .onAppear { chatUnread = false }
    }

    /// 仲間の名前と会話の未読（共有したプランだけ）
    private func loadShare() async {
        guard let plan, plan.share != nil, !isOffline else { return }
        do {
            let detail = try await environment.tripShare.detail(planId: planId)
            members = detail.members
            if let link = detail.invite { inviteLink = link }
        } catch {
            // 名前が引けなくても日程は使える（顔の段は印だけ・「足しました」は出さない）
        }
        let current = chosenTab ?? startTab
        if current == .chat { return }
        do {
            let items = try await environment.tripShare.inbox()
            let mine = items.first(where: { $0.planId == planId })
            chatUnread = (mine?.unread ?? 0) > 0
        } catch {
            chatUnread = false
        }
    }

    /// 共有する（作った人）。相手を渡せば、その人をすぐ仲間に（DM から作ったプラン）
    private func share(with peer: TripSharePeer?) async {
        guard !shareWorking else { return }
        // 送っていない直しを先に送る（共有すると行が移るので、送り先を1つにしておく）
        guard await flush(force: true) else { return }
        shareWorking = true
        defer { shareWorking = false }
        do {
            let detail = try await environment.tripShare.share(planId: planId, with: peer?.id)
            members = detail.members
            await model.load(environment: environment)
        } catch {
            fail(.share, (error as? LocalizedError)?.errorDescription ?? L("もう一度お試しください。", "Please try again."),
                 retry: { Task { await share(with: peer) } })
        }
    }

    /// 仲間を誘う（共有していなければ先に共有する）→ リンクのシート
    private func invite(_ plan: TripPlan) async {
        inviteError = nil
        if plan.share == nil {
            await share(with: nil)
            guard self.plan?.share != nil else { return }
        }
        inviting = true
        if inviteLink != nil { return }
        do {
            inviteLink = try await environment.tripShare.invite(planId: planId)
        } catch {
            inviteError = (error as? LocalizedError)?.errorDescription ?? L("リンクを作れませんでした。", "Couldn't make a link.")
        }
    }

    /// 「場所を足す」（v2 の板 TripPlanDays の `.add`: 真鍮の ＋ と字・48）
    /// - `compact`: 場所の入った日は小さく（「＋ 追加」・真鍮の字・当たり 44pt）。**空の日だけ**真鍮の大きな行で目立たせる
    ///   （2026-11-11 owner「UI もブラッシュアップして」: 日ごとに大きな行が並んで縦に長かった。押す回数は変わらない）
    private func addRow(_ di: Int, full: Bool, compact: Bool = false) -> some View {
        Button {
            picking = PickTarget(day: di)
        } label: {
            HStack(spacing: JPSpace.xs) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                // 2026-11-12（札 #570）: シートで観光スポットも探せるので「場所を足す」（モックの場面5の言葉）
                Text(compact ? L("追加", "Add") : L("場所を足す", "Add places"))
                    .font(compact ? JPFont.footnote.weight(.semibold) : JPFont.bodyEmphasis)
                Spacer(minLength: 0)
            }
            // 小さくても真鍮の字（板 `.add`・owner の好み「デザインの箇所は白より真鍮」・確かめ役の指摘）
            .foregroundStyle(WebTheme.accent)
            .frame(minHeight: compact ? WebTheme.minTapTarget : JPHeight.field)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(L("\(di + 1) 日目に場所を足す", "Add places to day \(di + 1)"))
        .buttonStyle(.plain)
        .accessibilityIdentifier("tripPlan.addRow.\(di)")
        // 1日に置ける数はサーバーと対（超えると保存で断られる）
        .disabled(full)
        .opacity(full ? 0.5 : 1)
    }

    /// 足す。**入ったか**を返す（いっぱいの日・無い日は断る・`TripPlanEdit.adding`）
    private func add(_ item: TripItem, to di: Int) -> Bool {
        guard let next = TripPlanEdit.adding(item, to: days, day: di) else { return false }
        days = next
        return true
    }

    private var addDayButton: some View {
        let full = days.count >= TripPlanService.daysMax
        return Button {
            days.append(TripDay())
        } label: {
            // v2 の副ボタン（44・白 14% の線・Components 01）
            Label(L("日を追加", "Add a day"), systemImage: "plus")
                .jpPillButton(.outline)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tripPlan.addDay")
        .disabled(full)
        .opacity(full ? 0.5 : 1)
    }

    // MARK: - 削除

    /// 削除（抜ける）を送る。断られたら下の帯の「もう一度」で送り直す（2026-11-25 判断・窓をやめた）
    private func removePlan() {
        Task {
            if await model.remove(planId, environment: environment) {
                dismiss()
            } else {
                fail(.delete, model.errorMessage ?? L("もう一度お試しください", "Please try again."),
                     retry: { removePlan() })
            }
        }
    }

    /// **消す前に一度聞く。** 日程ごと消えるうえ、戻す手が無い（Web と同じ）。
    ///
    /// v2 の板 TripPlanDays: 一番下に `WebTheme.danger` の字の行を1つだけ（札で囲まない）。
    /// 確かめは**画面の中に開く**（板は系統の確認の札だが、保存のアラートと重ならないよう前のまま）
    private func deleteCard(_ plan: TripPlan) -> some View {
        let title = plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title
        // 共有したプランの仲間（作った人でない）は「抜ける」。作った人の削除は仲間全員から消える（サーバーが分ける）
        let leaving = plan.share != nil && !(plan.share?.isOwner(auth.userId) ?? false)
        return VStack(spacing: JPSpace.xs) {
            Button {
                confirmingDelete.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: leaving ? "rectangle.portrait.and.arrow.right" : "trash").accessibilityHidden(true)
                    Text(leaving ? TripShareText.leave : L("「\(title)」を削除", "Delete \(title)"))
                }
                .font(JPFont.body)
                .foregroundStyle(WebTheme.danger)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tripPlan.delete")

            if confirmingDelete {
                JPDeleteConfirm(question: leaving ? TripShareText.leaveConfirm
                                : plan.share != nil ? L("仲間全員から、この旅行プランと会話を削除しますか？", "Delete this trip and its chat for everyone?")
                                : L("この旅行プランを削除しますか？", "Delete this trip?"),
                                confirmTitle: leaving ? L("抜ける", "Leave") : L("削除する", "Delete"),
                                busy: model.busy != nil, identifier: "trip.delete") {
                    confirmingDelete = false
                    removePlan()
                } onCancel: {
                    confirmingDelete = false
                }
            }
        }
        .padding(.top, JPSpace.xs)
    }
}


#if DEBUG
/// 見本のときだけ出す「送った回数 N」（UI テストが値で読む・`accessibilityValue`）
private struct TripPlanFixtureSendsLabel: View {
    @ObservedObject private var counter = TripPlanFixtureCounter.shared

    /// 2026-11-14 判断（前回の点検の残り）: **画面には出さず、見えない要素の値にだけ出す**（CLAUDE.md「値を出す仕組みは
    /// UI テストのときだけ見えない要素に」）。前は日程の上に「送った回数 0 / lift=0 target=0 …」が字で見え、
    /// 画面写真を板と比べるときに見た目が違った。UI テストは値（`accessibilityValue`）だけを読む
    var body: some View {
        ZStack(alignment: .topLeading) {
            Self.probe(id: "tripPlan.fixtureSends", value: "\(counter.sends)")
            // 運ぶ操作の数（UI テストが値で読む）
            Self.probe(id: "tripPlan.fixtureDrag", value: counter.dragLine)
            // 運ぶ操作の出来事の並び（UI テストが値で読む）
            Self.probe(id: "tripPlan.fixtureDragTrail", value: counter.trailLine)
            // 速さの数（描き直しの回数・時刻の計算・主の糸の止まり・札 #677）
            Self.probe(id: "tripPlan.fixturePerf", value: counter.perfLine)
        }
        .allowsHitTesting(false)
        .onAppear { counter.startWatchdog() }
    }

    /// 見えない値の要素（字は透明・1pt）
    static func probe(id: String, value: String) -> some View {
        Text(".")
            .font(JPFont.caption)
            .foregroundStyle(Color.clear)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(id)
            .accessibilityValue(value)
    }
}
#endif

/// 裏で少しだけ続けさせてもらう窓（`beginBackgroundTask`）。**時間切れでも終える**（確かめ役の指摘・2026-11-10）
@MainActor
private final class TripBackgroundWindow {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    /// 終える（2度目は何もしない）
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}


/// 今日の日の札（2026-11-16 判断・使い勝手の見直し A2・模型 A2）: 地は札の面 #0E0E0F、縁は真鍮 55%、角 16、
/// 内側 14（下は 6）。**板 TripPlanDays は日を札で囲まない**（区切り線の行）。今日の日だけ囲むのは、旅の日に開いたとき
/// 「今日はここ」が見て分かるため（真鍮は黒い地の上。色だけで伝えず、見出しの「今日」の字でも伝える）
struct TripTodayFrame: ViewModifier {
    let on: Bool
    /// 縁の濃さ（真鍮 55%）
    static let borderOpacity = 0.55

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.l)
                    .strokeBorder(WebTheme.accent.opacity(Self.borderOpacity), lineWidth: JPStroke.hairline))
                .padding(.top, JPSpace.xs)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tripPlan.today")
        } else {
            content
        }
    }
}

/// 「替える」の対象（札 #621）
struct TripAISwapTarget: Identifiable {
    let day: Int
    let item: Int
    let spot: OfficialSpot
    var id: String { "\(day)-\(item)-\(spot.spotId)" }
}

/// 名前をまだ引けていない観光スポットの行の骨組み（2026-11-23 判断・索引を読み込む間に `sp_…` を見せない）。
/// 番号の丸は本物と同じ（日程の番号は先に分かる）、名前と季節の一文は灰の棒（`AskLoadingSkeleton` の流れの骨組みと同じ surface-4）
struct TripStopSkeleton: View {
    let number: Int
    /// 行の写真の欄の寸法（44pt・角10）。行の写真（`TripStopThumbView`）と同じ値を使う（2026-11-23 判断・統合で写しを1つにした）
    static let photoSide: CGFloat = TripStopThumbView.side
    static let photoCorner: CGFloat = JPRadius.s

    var body: some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            TripStopNumber(number: number)
                .padding(.top, 2)
            // 写真の欄と同じ枠（44pt・角10）。行に写真の欄が入っても、読み込み終わりで名前が横にずれない（2026-11-23 判断）
            RoundedRectangle(cornerRadius: Self.photoCorner)
                .fill(WebTheme.surface4)
                .frame(width: Self.photoSide, height: Self.photoSide)
            VStack(alignment: .leading, spacing: 6) {
                Self.bone(width: 150, height: 16)
                Self.bone(width: 80, height: 12)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.vertical, JPSpace.s)
        .frame(minHeight: JPHeight.tallRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(number)、読み込み中", "\(number), loading"))
        .accessibilityIdentifier("tripPlan.stopSkeleton")
    }

    static func bone(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(WebTheme.surface4)
            .frame(width: width, height: height)
    }
}
