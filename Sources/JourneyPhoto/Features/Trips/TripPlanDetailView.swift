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
/// 行のほかの所を押すと今どおり撮影スポットが開く。読み上げでは「…」の上へ／下へ／別の日へ移すを残す。
/// 場所と場所の間には移動の見込みの1行（`TripLegRow`・Apple の地図が返した数だけ）。
struct TripPlanDetailView: View {

    let planId: String
    @ObservedObject var model: TripPlansModel

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var hidden: ModerationStore
    /// 電波なしで使える旅（板 72・2026-10-09）
    @EnvironmentObject private var offline: OfflineTripStore
    @EnvironmentObject private var connectivity: Connectivity
    @Environment(\.dismiss) private var dismiss
    /// 移動の見込み（アプリを開いている間の控え・`TravelEstimator`）
    @ObservedObject private var travel = TravelEstimator.shared
    /// 画面の外でプランが書き換わった知らせ（「旅行プランに入れる」のシート）
    @ObservedObject private var outsideChanges = TripPlanChanges.shared
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
    /// 季節の一文・時刻帯のために詳細を重ねた（索引だけの行の文は詳細にある）
    @State private var detailsKey = ""

    private struct DropSpot: Equatable { let day: Int; let item: Int? }
    private struct LegTarget: Identifiable {
        let leg: TripTravel.Leg
        let estimates: [TripTravel.Estimate]
        let modes: [TripTravel.Mode]
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
    /// 「行きたい場所から追加」を押した日
    @State private var picking: PickTarget?
    /// 「地図で見る」を押した日（`TripDayMapView`）
    @State private var mapDay: MapTarget?
    /// 消すか確かめている日（予定の入った日だけ・`TripPlanEdit.confirmsRemoving`）。
    /// **画面の中に開く札で確かめる**（プランの削除と同じ形）。系統の確認ダイアログにすると、
    /// 保存の返事を待つ間に出した確認の上にエラーのアラートが立てず、以後の知らせが止まった
    /// （37b96ec のレビュー）
    @State private var removingDay: RemoveDayTarget?
    @State private var confirmingDelete = false
    /// 「保存して戻る／変更を捨てる」の確認
    @State private var confirmLeave = false
    /// 「保存して戻る」が断られた（アラートで出す——下までスクロールしていると
    /// 画面の中の赤い行は見えず、押しても何も起きないように見えた）
    @State private var leaveSaveError: String?
    /// 削除が断られた（アラートで出す——理由は `leaveSaveError` と同じ。
    /// 削除の札は画面のいちばん下にあり、上の赤い行は見えない）
    @State private var deleteError: String?
    /// 名前を引く材料が**一度でも取れたか**。取れた後の読み直しの失敗で消さない
    @State private var gotPhotos = false
    @State private var gotIndex = false
    /// 保存を送った回数（「保存して戻る」の失敗の知らせを、その後に別の保存が
    /// 走っていたら出さないための目印）
    @State private var saveAttempt = 0
    /// 名前を引く材料（取れなくても画面は出る——名前が鍵のままになるだけ）
    @State private var photos: [Photo] = []
    @State private var index: [OfficialSpot] = []
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
    /// ひとことを書いている間に届いた保存の失敗。**欄を閉じたあとに出す**（その間に出すと
    /// アラートが2つ重なって片方が捨てられる。捨てると下までスクロールした人に何も見えない）
    @State private var deferredSaveError: String?
    /// ひとことを入れられなかった知らせ（書いている間に項目が外れた）
    @State private var noteError: String?
    /// 項目を動かせなかった知らせ（メニューを開いている間に日程が差し替わった）
    @State private var moveError: String?

    /// **いまアラートを出してよいか。** 候補のシート・上に積んだ画面・戻る確認・ひとことの欄の
    /// 間と、**ほかのアラートがもう立っている間**は出さない（2つ目は捨てられ、その値が立った
    /// ままになると次から出なくなる）。同じ条件を手で写すと片方だけ直す形になるので1か所に置く
    private var canPresentAlert: Bool {
        picking == nil && onTop && !confirmLeave && noAlertShowing
    }

    /// ほかのアラートがどれも立っていない。**アラートを立てる経路は全部これを見る**
    /// （1本でも見ないと、立ったままの値が残ったとき全部の知らせが止まる）。
    /// ひとことの欄（`noteTarget`）は経路ごとに扱いが違う（閉じてから出す／出さない）ので含めない
    private var noAlertShowing: Bool {
        leaveSaveError == nil && noteError == nil && deleteError == nil && moveError == nil
    }
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
        Group {
            if let manifest = offlineManifest {
                ScrollView {
                    OfflineTripContent(manifest: manifest)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                }
            } else if let plan {
                editor(plan)
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
                           backTitle: L("旅行プラン", "Trip plans"),
                           message: L("まだ送れていない変更があります。保存せずに戻ると、変えた日程は残りません。",
                                      "Some changes aren't sent yet. If you go back without saving, they'll be lost."),
                           onSave: {
                               Task {
                                   // 断られたら残り、アラートで知らせる
                                   if await flush(force: true) {
                                       dismiss()
                                   } else {
                                       let mine = saveAttempt
                                       let message = Self.problemText(problem)
                                       // 確認の板が閉じ切ってから出す（閉じている途中に出すと
                                       // SwiftUI が黙って捨てることがある）
                                       try? await Task.sleep(nanoseconds: 350_000_000)
                                       guard saveAttempt == mine, !confirmLeave, noAlertShowing else { return }
                                       if noteTarget != nil { deferredSaveError = message; return }
                                       leaveSaveError = message
                                   }
                               }
                           },
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
        .alert(L("保存できませんでした", "Couldn't save"),
               isPresented: Binding(get: { leaveSaveError != nil },
                                    set: { if !$0 { leaveSaveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(leaveSaveError ?? "")
        }
        // ひとこと（項目に添えるメモ・200字まで）。**変えたら日程と一緒に保存する**
        // （保存ボタンと「保存せずに戻る？」の確認は、ほかの変更と同じ扱い）
        .alert(L("ひとこと", "Note"),
               isPresented: Binding(get: { noteTarget != nil },
                                    set: { if !$0 { noteTarget = nil } })) {
            TextField(L("例: 朝いちばんに行く", "e.g. Go first thing in the morning"), text: $noteText)
            Button(Labels.Common.save) {
                let target = noteTarget
                noteTarget = nil
                guard let t = target else { return }
                if let at = TripPlanEdit.locate(days, day: t.day, item: t.item, original: t.original),
                   let next = TripPlanEdit.setNote(days, day: t.day, item: at, note: noteText) {
                    days = next
                } else {
                    // 書いている間に項目が外れた（別の端末・保存の応答で差し替わった）。
                    // 黙って捨てずに知らせる。アラートは閉じた後に、出してよい時だけ
                    // （ほかの確認・候補のシート・上に積んだ画面の間は出さない）
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard canPresentAlert, noteTarget == nil else { return }
                        noteError = L("書いている間に項目が変わったため、ひとことを入れられませんでした。もう一度書いてください。",
                                      "The item changed while you were writing, so the note wasn't added. Please try again.")
                    }
                }
            }
            Button(Labels.Common.cancel, role: .cancel) { noteTarget = nil }
        } message: {
            Text(L("\(TripPlanService.noteMax)字まで。空にすると外します", "Up to \(TripPlanService.noteMax) characters. Leave empty to remove."))
        }
        .alert(L("ひとことを入れられませんでした", "Couldn't add the note"),
               isPresented: Binding(get: { noteError != nil },
                                    set: { if !$0 { noteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noteError ?? "")
        }
        .alert(L("動かせませんでした", "Couldn't move"),
               isPresented: Binding(get: { moveError != nil },
                                    set: { if !$0 { moveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveError ?? "")
        }
        // ひとことの欄を閉じたら、その間に届いた保存の失敗を出す
        .onChange(of: noteTarget == nil) { _, closed in
            guard closed, let message = deferredSaveError else { return }
            deferredSaveError = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard canPresentAlert, noteTarget == nil else { return }
                leaveSaveError = message
            }
        }
        .alert(L("削除できませんでした", "Couldn't delete"),
               isPresented: Binding(get: { deleteError != nil },
                                    set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        // 🔴 **取り直せなかった回は、取れていた材料を消さない。** この `.task` は
        // 項目のスポットを開いて戻るたびに走る。圏外で戻ると、読めていた場所の名前と
        // リンクが消えて鍵（sp_…）だけになり、候補も「読み込めませんでした」になっていた
        .task {
            let fetchedPhotos = try? await environment.gallery.fetchPhotos()
            let fetchedIndex = try? await environment.spots.fetchIndex()
            if let fetchedPhotos { photos = fetchedPhotos; gotPhotos = true }
            if let fetchedIndex { index = fetchedIndex; gotIndex = true }
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
        .task(id: SpotDetailNeeds.key(planSpotsNeedingDetails)) {
            let needs = planSpotsNeedingDetails
            guard !needs.isEmpty else { return }
            index = await environment.spots.withDetails(index, for: needs)
        }
        // 移動の見込みを聞く（開いているプランの区間だけ・同じ区間は控え）
        .sheet(item: $legTarget) { target in
            NavigationStack {
                TripLegSheet(leg: target.leg, estimates: target.estimates, modes: target.modes,
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

        // その日の場所を番号つきで地図に・前の場所からの経路（2026-09-30）。
        // **開いた時点の日程で出す**（保存していない並び替えも反映する）
        .sheet(item: $mapDay) { target in
            NavigationStack {
                TripDayMapView(title: L("\(target.day + 1) 日目の地図", "Day \(target.day + 1) map"),
                               stops: target.stops)
            }
        }
        .sheet(item: $picking) { target in
            NavigationStack {
                TripPlanPickSheet(dayIndex: target.day,
                                  dayDate: pickDayDate(target.day),
                                  capacity: TripStyle.remaining(
                                      dayCount: days.indices.contains(target.day) ? days[target.day].items.count : 0,
                                      max: TripPlanService.itemsPerDayMax),
                                  sourcesFailed: sourcesFailed,
                                  choices: pickChoices,
                                  seasonLines: seasonLines(for: pickChoices, day: target.day)) { choice in
                    add(choice.item, to: target.day)
                }
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
            problem = .conflict
            return false
        }
        let ok = await save()
        if ok {
            problem = nil
            // 🔴 **送れたらその場で比べる相手を新しい版に**（確かめ役の指摘 F: 古い版のまま次の読み直しと比べると、
            // 自分の書き込みを「別の端末の変更」と誤って止めた）。送っている間の直しは残す（下で送り直す）
            if let plan {
                loadedFrom = plan
                sent = nil
            }
            if isDirty { scheduleAutosave() }
        } else {
            problem = .failed(model.errorMessage ?? L("もう一度お試しください。", "Please try again."))
            // 文は上の「まだ送れていません」の札で出す（赤い行と二重にしない）
            model.clearError()
        }
        return ok
    }

    /// 別の端末の変更を読み直す（この画面で変えた分は残らない）
    private func reloadFromServer() async {
        await model.load(environment: environment)
        guard let plan else { return }
        loadedFrom = plan
        sent = nil
        days = plan.days
        start = plan.startDate
        end = plan.endDate
        problem = nil
    }

    nonisolated static func problemText(_ problem: TripAutosave.Problem?) -> String {
        switch problem {
        case .failed(let message)?: return message
        case .offline?: return L("圏外のため送れませんでした。", "You're offline.")
        case .conflict?: return L("別の端末でこのプランが変わりました。", "This trip changed on another device.")
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
        if let text = TripAutosave.banner(problem, dirty: isDirty) {
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
                } else {
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
        let patch = TripPlanText.patch(plan: plan, days: days, start: start, end: end)
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 題（v2 の板 TripPlanDays: 明朝の大見出し・Title 1）
                Text(plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title)
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: JPSpace.xs) {
                    dateField(L("出発", "From"), value: $start, fallback: end, isStart: true)
                    dateField(L("帰着", "To"), value: $end, fallback: start, isStart: false)
                }

                // 送れていない直し（圏外・断られた・別の端末の変更）。日付の下・日程の上に残す。
                // UI テストの見本のときだけ、その下に自動保存が送った回数（`TripPlanFixture`・Debug のみ）
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    autosaveBanner
                    fixtureSendsLabel
                }

                // 電波なしで使えるようにする（板 72・日付の下）。比べるのはサーバーの姿のプラン
                OfflineTripCard(plan: plan, index: index, places: places, sourcesReady: gotIndex && gotPhotos)

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
                // 通し番号（1日目 1・2、2日目 3 …・板 TripPlanDays）。圏外の画面・地図の画像の点と同じ数え方
                let numbers = TripStyle.stopNumbers(days.map(\.items.count))
                ForEach(Array(days.enumerated()), id: \.offset) { di, day in
                    daySection(di, day, numbers: numbers.indices.contains(di) ? numbers[di] : [], layout: layout)
                        .padding(.top, di == 0 ? 0 : JPSpace.xs)
                }

                addDayButton
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
                deleteCard(plan)
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd)
        }
        // 移動の見込みを聞く（開いているプランの区間だけ・同じ区間は控え）
        .task(id: layout.key) { requestTravel(layout.all) }
    }

    // MARK: - 出発・帰着

    /// 日付の欄。**端末の日付ピッカー**で選ぶ（Web は `type="date"`。文字で打たせない）。
    /// 空にもできる（Web も空を許す）
    private func dateField(_ title: String, value: Binding<String?>, fallback: String?,
                           isStart: Bool) -> some View {
        // v2 の板 TripPlanDays の `.dt`: 52 の箱の中に、上に 12 の名前・下に日付（surface-2・白 8% の縁・角 12）
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            HStack(spacing: JPSpace.xxs) {
                if value.wrappedValue != nil {
                    DatePicker(title, selection: pickerBinding(value, isStart: isStart), displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    Button {
                        value.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WebTheme.text3)
                            .webTappable()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(title)の日付を消す", "Clear \(title)"))
                } else {
                    Button {
                        // 入れる日は**もう片方の日付**、無ければ今日
                        value.wrappedValue = fallback ?? TripPlanText.ymd(pickedIn: .current, Date())
                    } label: {
                        Text(L("日付を入れる", "Set date"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(title)の日付を入れる", "Set \(title) date"))
                }
            }
        }
        .padding(.horizontal, JPSpace.s)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, minHeight: TripStyle.dateFieldHeight, alignment: .leading)
        .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }

    /// `YYYY-MM-DD` ⇔ ピッカーの日。**端末のゾーンのその日**で読み書きする
    /// 選んだときだけ前後を揃える（`TripPlanText.ordered`）。**開いたときの値には
    /// 触らない**——Web で作った「帰着が出発より前」のプランを開いただけで書き換えない
    private func pickerBinding(_ value: Binding<String?>, isStart: Bool) -> Binding<Date> {
        Binding(
            get: { TripPlanText.pickerDate(fromYMD: value.wrappedValue, in: .current) ?? Date() },
            set: {
                value.wrappedValue = TripPlanText.ymd(pickedIn: .current, $0)
                let fixed = TripPlanText.ordered(start: start, end: end, movedStart: isStart)
                if fixed.start != start { start = fixed.start }
                if fixed.end != end { end = fixed.end }
            }
        )
    }

    // MARK: - 日ごと

    private var pickChoices: [TripPlanText.Choice] {
        TripPlanText.choices(wishlistKeys: wishlist.spotIds, places: places, index: index)
    }

    /// 候補の季節の一文（その日の月の季節の案内がある撮影スポットだけ・`TripDraft.seasonLine`）
    private func seasonLines(for choices: [TripPlanText.Choice], day di: Int) -> [String: String] {
        guard days.indices.contains(di),
              let ymd = TripPlanText.dayDate(index: di, day: days[di], start: start, end: end) else { return [:] }
        var out: [String: String] = [:]
        for choice in choices {
            guard let spot = spotFor(choice.item), let line = TripDraft.seasonLine(spot, ymd: ymd) else { continue }
            out[choice.id] = line
        }
        return out
    }

    /// 候補のシートの眉に添える日付（「12月24日」）。日付の無いプランは nil
    private func pickDayDate(_ di: Int) -> String? {
        guard days.indices.contains(di),
              let date = TripPlanText.dayDate(index: di, day: days[di], start: start, end: end) else { return nil }
        return TakenDay.label(date)
    }

    /// 日の見出し（v2 の板 TripPlanDays: 真鍮の眉「1日目 · 12月24日」と右へ消える線）
    private func dayHeading(_ di: Int, _ day: TripDay) -> String {
        var head = L("\(di + 1) 日目", "Day \(di + 1)")
        if let date = TripPlanText.dayDate(index: di, day: day, start: start, end: end),
           let label = TakenDay.label(date) {
            head += L(" · \(label)", " · \(label)")
        }
        return head
    }

    private func daySection(_ di: Int, _ day: TripDay, numbers: [Int], layout: TravelLayout) -> some View {
        let ymd = TripPlanText.dayDate(index: di, day: day, start: start, end: end)
        let resolved = day.items.map { TripDraft.place(for: $0, index: index, places: places) }
        let sun = TripDraft.sun(ymd: ymd, spots: daySpots(day))
        let legs = layout.legs(di)
        let estimatesByLeg = legs.map { estimates(for: $0) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                JPEyebrowLine(dayHeading(di, day))
                    .padding(.trailing, JPSpace.xs)
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

            // 日の出・日の入り（端末の計算）・同じ時間帯の重なり・間に合わないとき（計算した数だけ）
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
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
                    } else if ii > 0 {
                        divider
                    }
                    itemRow(di, ii, item, number: number,
                            season: spotFor(item).flatMap { TripDraft.seasonLine($0, ymd: ymd) },
                            chip: resolved.indices.contains(ii) ? TripDraft.timeChip(resolved[ii].times) : nil)
                    // 場所が1か所だけ: 移動の目安が出ない理由を、その場所の下に1行で（2026-11-11）。
                    // 区切り線は日の最後の1本だけ（1行を線で挟まない・確かめ役の指摘）
                    if let single = layout.single, single.number == number {
                        TripDayNote(text: single.hint, symbol: "arrow.triangle.swap")
                            .padding(.bottom, JPSpace.xs)
                            .accessibilityIdentifier("trip.leg.singleHint")
                    }
                    if ii == day.items.count - 1 { divider }
                }
                addRow(di, full: day.items.count >= TripPlanService.itemsPerDayMax, compact: !day.items.isEmpty)
                    .overlay(alignment: .top) { dropLine(DropSpot(day: di, item: nil)) }
                    .dropDestination(for: String.self) { items, _ in
                        drop(items.first, toDay: di, toItem: nil)
                    } isTargeted: { setDropTarget($0, DropSpot(day: di, item: nil)) }
            }
        }
    }

    /// その日の撮影スポット（日程の順）
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
            legTarget = LegTarget(leg: leg, estimates: estimates, modes: modes, sun: sun, destinationTimes: toTimes,
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
        announce(L("\(di + 1) 日目を削除しました", "Removed day \(di + 1)"))
    }

    /// 日を消す前の札（プランの削除の札と同じ形・v2 の板 OfflineSaveStates 5 の確かめと同じ部品）
    private func removeDayConfirm(_ di: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("\(di + 1) 日目と、その日の予定を削除しますか？", "Remove day \(di + 1) and its plans?"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
            HStack(spacing: JPSpace.xs) {
                TripOutlineButton(title: L("削除する", "Remove"), strong: true, fill: true) {
                    guard let target = removingDay else { return }
                    removeDay(di, confirmedOn: target.days)
                }
                TripOutlineButton(title: Labels.Common.cancel, fill: true) {
                    removingDay = nil
                }
            }
        }
        .padding(.vertical, JPSpace.s)
    }

    private var divider: some View {
        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
    }

    private func itemRow(_ di: Int, _ ii: Int, _ item: TripItem, number: Int,
                         season: String?, chip: String?) -> some View {
        let name = TripPlanText.label(for: item, index: index, places: places)
        // 🔴 **右の印は「…」1つに**（2026-11-11 owner「UI もブラッシュアップして」: 「…」「×」「≡」の3つが並んで重かった）。
        // - 外すは「…」の中（押す回数 1 → 2。日程から外すのは取り消せるが、誤って押しやすい × を行に置かない）
        // - 並べ替えは**行を押さえて運ぶ**（iOS の決まりの操作。押す回数は変わらない）。行を押すと今どおり撮影スポットが開く
        // - 読み上げの人は「…」の上へ・下へ・別の日へ移す・外す
        return HStack(spacing: 0) {
            if TripPlanFixture.dragHandleVariant {
                // 比べるための運ぶ印の版（見本のときだけ・`-JPTripPlanDragHandle`）
                itemLink(item, name: name, number: number, season: season, chip: chip)
                Image(systemName: "line.3.horizontal")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text3)
                    .webTappable()
                    .contentShape(Rectangle())
                    .draggable(TripPlanEdit.dragPayload(day: di, item: ii, of: item)) { dragPreview(name) }
                    .accessibilityLabel(L("「\(name)」を運ぶ", "Move \(name)"))
                    .accessibilityIdentifier("tripPlan.dragHandle")
            } else {
                itemLink(item, name: name, number: number, season: season, chip: chip)
                    .draggable(TripPlanEdit.dragPayload(day: di, item: ii, of: item)) { dragPreview(name) }
                    .accessibilityHint(L("押すと開きます。押さえたまま運ぶと並べ替えます", "Tap to open. Touch and hold, then drag to reorder."))
                    .accessibilityIdentifier("tripPlan.dragHandle")
            }
            itemMenu(di, ii, item, name: name)
        }
        .overlay(alignment: .top) { dropLine(DropSpot(day: di, item: ii)) }
        .dropDestination(for: String.self) { items, _ in
            drop(items.first, toDay: di, toItem: ii)
        } isTargeted: { setDropTarget($0, DropSpot(day: di, item: ii)) }
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
                guard let at = TripPlanEdit.locate(days, day: di, item: ii, original: item),
                      let next = TripPlanEdit.moveUp(days, day: di, item: at) else { return notMoved(name) }
                apply(next, said: L("「\(name)」を \(di + 1) 日目の \(at) 番目へ移しました", "Moved \(name) to position \(at) on day \(di + 1)"))
            } label: { Label(L("上へ", "Move up"), systemImage: "arrow.up") }
            .disabled(!canUp)
            Button {
                guard let at = TripPlanEdit.locate(days, day: di, item: ii, original: item),
                      let next = TripPlanEdit.moveDown(days, day: di, item: at) else { return notMoved(name) }
                apply(next, said: L("「\(name)」を \(di + 1) 日目の \(at + 2) 番目へ移しました", "Moved \(name) to position \(at + 2) on day \(di + 1)"))
            } label: { Label(L("下へ", "Move down"), systemImage: "arrow.down") }
            .disabled(!canDown)
            if !targets.isEmpty {
                Menu {
                    ForEach(targets, id: \.self) { to in
                        Button(L("\(to + 1) 日目", "Day \(to + 1)")) {
                            guard let at = TripPlanEdit.locate(days, day: di, item: ii, original: item),
                                  let next = TripPlanEdit.moveToDay(days, day: di, item: at, toDay: to) else { return notMoved(name) }
                            apply(next, said: L("「\(name)」を \(to + 1) 日目へ移しました", "Moved \(name) to day \(to + 1)"))
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
            // 外す（2026-11-11: 行の × をここへ畳んだ）。押した時点の日程で同じ項目を探し直す
            Button(role: .destructive) {
                guard let next = TripPlanEdit.removing(days, day: di, item: ii, original: item) else { return notMoved(name) }
                days = next
                announce(L("「\(name)」を外しました", "Removed \(name)"))
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
        .accessibilityValue(L("\(di + 1) 日目・\(ii + 1) 番目", "Day \(di + 1), item \(ii + 1)"))
    }

    /// 並べ替え・移動を映し、結果を読み上げる（目で追えない人に、項目がどこへ行ったかを伝える）
    private func apply(_ next: [TripDay], said: String) {
        days = next
        announce(said)
    }

    /// 押したときに項目が見つからなかった（メニューを開いている間に日程が差し替わった）。
    /// **黙って何もしないと、押しても効かなかったように見える**——目で見ている人には
    /// アラート（ひとことの経路と同じく、メニューが閉じてから・出してよい時だけ）、
    /// VoiceOver の人にはアラートがそのまま読まれる
    private func notMoved(_ name: String) {
        let message = L("「\(name)」は項目が変わったため動かせませんでした。もう一度お試しください。",
                        "\(name) couldn't be moved because the item changed. Please try again.")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            // 出せないとき（戻る確認・上の画面・ほかのアラート）は、せめて読み上げで伝える
            guard canPresentAlert, noteTarget == nil else {
                // 出せないときは読み上げで伝える（上に別の画面を積んだ回は鳴らさない）
                if onTop { announce(message) }
                return
            }
            moveError = message
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
    private func itemLink(_ item: TripItem, name: String, number: Int, season: String?, chip: String?) -> some View {
        switch item {
        case .spot(let spotId, _):
            if let spot = index.first(where: { $0.spotId == spotId }) {
                NavigationLink {
                    OfficialSpotView(spot: spot, spots: index, photos: photos, photosKnown: gotPhotos)
                } label: {
                    itemLabel(name, number: number, isSpot: true, note: item.note, season: season, chip: chip)
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, number: number, isSpot: true, note: item.note, season: season, chip: chip)
            }
        case .location(let slug, _):
            if let place = places.first(where: { $0.slug == slug }) {
                NavigationLink {
                    SpotDetailView(spot: place, photos: photos)
                } label: {
                    itemLabel(name, number: number, isSpot: false, note: item.note, season: nil, chip: nil)
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, number: number, isSpot: false, note: item.note, season: nil, chip: nil)
            }
        }
    }

    /// 行の中身（v2 の板 TripPlanDays・F30: 番号の丸 → 名前 → 季節の一文と時間帯の札 → ひとこと・`TripStopLabel`）
    private func itemLabel(_ name: String, number: Int, isSpot: Bool, note: String?,
                           season: String?, chip: String?) -> some View {
        TripStopLabel(number: number, name: name, isSpot: isSpot, season: season, timeChip: chip, note: note)
    }

    /// 「行きたい場所から追加…」（v2 の板 TripPlanDays の `.add`: 真鍮の ＋ と字・48）
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
                Text(compact ? L("追加", "Add") : L("行きたい場所から追加…", "Add a saved place…"))
                    .font(compact ? JPFont.footnote.weight(.semibold) : JPFont.bodyEmphasis)
                Spacer(minLength: 0)
            }
            // 小さくても真鍮の字（板 `.add`・owner の好み「デザインの箇所は白より真鍮」・確かめ役の指摘）
            .foregroundStyle(WebTheme.accent)
            .frame(minHeight: compact ? WebTheme.minTapTarget : JPHeight.field)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(L("\(di + 1) 日目に行きたい場所から追加", "Add a saved place to day \(di + 1)"))
        .buttonStyle(.plain)
        .accessibilityIdentifier("tripPlan.addRow.\(di)")
        // 1日に置ける数はサーバーと対（超えると保存で断られる）
        .disabled(full)
        .opacity(full ? 0.5 : 1)
    }

    private func add(_ item: TripItem, to di: Int) {
        guard days.indices.contains(di),
              days[di].items.count < TripPlanService.itemsPerDayMax else { return }
        days[di].items.append(item)
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

    /// **消す前に一度聞く。** 日程ごと消えるうえ、戻す手が無い（Web と同じ）。
    ///
    /// v2 の板 TripPlanDays: 一番下に `WebTheme.danger` の字の行を1つだけ（札で囲まない）。
    /// 確かめは**画面の中に開く**（板は系統の確認の札だが、保存のアラートと重ならないよう前のまま）
    private func deleteCard(_ plan: TripPlan) -> some View {
        let title = plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title
        return VStack(spacing: JPSpace.xs) {
            Button {
                confirmingDelete.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").accessibilityHidden(true)
                    Text(L("「\(title)」を削除", "Delete \(title)"))
                }
                .font(JPFont.body)
                .foregroundStyle(WebTheme.danger)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if confirmingDelete {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("この旅行プランを削除しますか？", "Delete this trip?"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                    HStack(spacing: JPSpace.xs) {
                        TripOutlineButton(title: L("削除する", "Delete"), strong: true, fill: true) {
                            confirmingDelete = false
                            Task {
                                if await model.remove(planId, environment: environment) {
                                    dismiss()
                                } else if canPresentAlert, noteTarget == nil {
                                    // 出せるときだけ（ほかのアラート・ひとことの欄が開いていない時）。
                                    // 出せない回は赤い行が残る（保存と違い、閉じてから出す控えは持たない）
                                    deleteError = model.errorMessage
                                        ?? L("もう一度お試しください", "Please try again.")
                                }
                            }
                        }
                        .disabled(model.busy != nil)
                        .opacity(model.busy == nil ? 1 : 0.5)
                        TripOutlineButton(title: Labels.Common.cancel, fill: true) {
                            confirmingDelete = false
                        }
                    }
                }
                .padding(JPSpace.m)
                .jpCardFace()
            }
        }
        .padding(.top, JPSpace.xs)
    }
}


#if DEBUG
/// 見本のときだけ出す「送った回数 N」（UI テストが値で読む・`accessibilityValue`）
private struct TripPlanFixtureSendsLabel: View {
    @ObservedObject private var counter = TripPlanFixtureCounter.shared

    var body: some View {
        Text(L("送った回数 \(counter.sends)", "Sent \(counter.sends)"))
            .font(JPFont.caption.monospacedDigit())
            .foregroundStyle(WebTheme.text3)
            .accessibilityIdentifier("tripPlan.fixtureSends")
            .accessibilityValue("\(counter.sends)")
        // 運ぶ操作の数（UI テストが値で読む）
        Text(counter.dragLine)
            .font(JPFont.caption.monospacedDigit())
            .foregroundStyle(WebTheme.text3)
            .accessibilityIdentifier("tripPlan.fixtureDrag")
            .accessibilityValue(counter.dragLine)
        // 運ぶ操作の出来事の並び（UI テストが値で読む。見本のときだけ 1 行で出す）
        Text(counter.trail.last ?? "-")
            .font(JPFont.caption.monospacedDigit())
            .foregroundStyle(WebTheme.text3)
            .lineLimit(1)
            .accessibilityIdentifier("tripPlan.fixtureDragTrail")
            .accessibilityValue(counter.trailLine)
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
