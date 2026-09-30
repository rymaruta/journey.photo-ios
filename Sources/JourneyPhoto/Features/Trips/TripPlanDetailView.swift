import SwiftUI
import UIKit

/// 旅行プランの日程（キャンバス「17b 旅行プランの日程」／ Web の `PlanEditor`）。
///
/// **保存は明示的。** 打つたびにサーバーへ送らず、右上の「保存」で送る。
/// 変えていなければ押させない（無駄な往復と、他の端末の編集の打ち消しを避ける）。
/// 送るのは**変えた項目だけ**（`TripPlanText.patch`）。
///
/// 🔴 **変えた日程があるまま黙って戻らせない。** 保存は右上だけなので、以前は
/// 戻るで下書きが確かめもなく消えていた。変えている間・送っている間は標準の戻る
/// を隠し、「保存して戻る／変更を捨てる／キャンセル」を確かめる
/// （`TripPlanText.leave`・`unsavedLeaveGuard`。親しい友達と同じもの）。
struct TripPlanDetailView: View {

    let planId: String
    @ObservedObject var model: TripPlansModel

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.dismiss) private var dismiss

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
    /// 消すか確かめている日（予定の入った日だけ・`TripPlanEdit.confirmsRemoving`）
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
    /// 消すか確かめている日（何日目と、**押したときの日そのもの**）
    private struct RemoveDayTarget {
        let index: Int
        let day: TripDay
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

    private func refreshPlaces() {
        places = DerivedSpot.allMergedBySlug(in: dropped.visible(photos))
    }

    var body: some View {
        Group {
            if let plan {
                editor(plan)
            } else {
                // 消した直後・別の端末で消されたとき
                ErrorBanner(message: L("プランが見つかりません", "Trip not found"))
            }
        }
        .webScreen()
        .navigationTitle(L("旅行プラン", "Trip plans"))
        .navigationBarTitleDisplayMode(.inline)
        // 削除などの最中は「保存して戻る」を出さない（送る口が断るので必ず失敗する）
        // 戻るの見た目は標準と同じ「‹ 旅行プラン」に保つ（前の画面の題）
        .unsavedLeaveGuard(leave, isPresented: $confirmLeave, canSave: model.busy == nil,
                           backTitle: L("旅行プラン", "Trip plans"),
                           message: L("保存しないで戻ると、変えた日程は残りません。",
                                      "If you go back without saving, your changes to this trip will be lost."),
                           onSave: {
                               Task {
                                   // 断られたら残り、アラートで知らせる
                                   if await save() {
                                       dismiss()
                                   } else {
                                       let mine = saveAttempt
                                       // **文は送った直後に取る**（待っている間に次の保存が
                                       // 走ると消える）。送る口は始めに文を消すので古い文は来ない
                                       let message = model.errorMessage
                                           ?? L("もう一度お試しください", "Please try again.")
                                       // 確認の板が閉じ切ってから出す（閉じている途中に出すと
                                       // SwiftUI が黙って捨てることがある）
                                       try? await Task.sleep(nanoseconds: 350_000_000)
                                       // その間に次の保存を送った・確認を開き直したなら出さない
                                       // （成功した後に前の失敗が出ていた。赤い行は残る）
                                       guard saveAttempt == mine, !confirmLeave, noAlertShowing else { return }
                                       // ひとことを書いている間は、欄を閉じてから出す（重ねない）
                                       if noteTarget != nil { deferredSaveError = message; return }
                                       leaveSaveError = message
                                   }
                               }
                           },
                           onDiscard: { dismiss() })
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { saveButton }
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
        .onDisappear { onTop = false }
        .onAppear {
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
        .onChange(of: plan) { _, _ in resetIfNeeded() }

        // その日の場所を番号つきで地図に・前の場所からの経路（2026-09-30）。
        // **開いた時点の日程で出す**（保存していない並び替えも反映する）
        // 予定の入った日を消す前に確かめる（系統の確認の部品・赤は系統のまま）
        .confirmationDialog(L("\((removingDay?.index ?? 0) + 1) 日目を削除しますか？",
                              "Remove day \((removingDay?.index ?? 0) + 1)?"),
                            isPresented: Binding(get: { removingDay != nil },
                                                 set: { if !$0 { removingDay = nil } }),
                            titleVisibility: .visible) {
            Button(L("削除", "Remove"), role: .destructive) {
                guard let target = removingDay else { return }
                removingDay = nil
                if let next = TripPlanEdit.removeDay(days, at: target.index, expected: target.day) {
                    days = next
                }
            }
        } message: {
            Text(L("この日の予定もなくなります。", "The plans for this day will be removed too."))
        }
        .sheet(item: $mapDay) { target in
            NavigationStack {
                TripDayMapView(title: L("\(target.day + 1) 日目の地図", "Day \(target.day + 1) map"),
                               stops: target.stops)
            }
        }
        .sheet(item: $picking) { target in
            NavigationStack {
                TripPlanPickSheet(dayIndex: target.day,
                                  sourcesFailed: sourcesFailed,
                                  choices: TripPlanText.choices(wishlistKeys: wishlist.spotIds,
                                                                places: places, index: index)) { choice in
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

    private var leave: UnsavedLeave {
        // 日程を送っている間（`sent` は保存の間だけ立つ。削除では立たない）
        TripPlanText.leave(plan: comparedPlan, days: days, start: start, end: end,
                           saving: model.busy != nil && sent != nil)
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

    private var saveButton: some View {
        Button(L("保存", "Save")) {
            Task {
                let saved = await save()
                guard !saved else { return }
                // 🔴 **断られたらアラートで知らせる。** 知らせは画面の上の赤い行だけで、
                // 下までスクロールしていると押しても何も起きないように見えた
                // （「保存して戻る」と同じ扱い）。
                // **出せるときだけ出す。** 候補のシートを開いている・上に画面を積んでいる・
                // 確認を出している間は、アラートは黙って捨てられる。そのときは赤い行だけが
                // 残る（この直しの前と同じ）。持っておいて後で出す作りは、戻るスワイプの
                // 長さ・他の確認・走っている保存と噛み合わず回帰が続いたので採らない
                // ほかのアラートが立っている間も出さない。ひとことの欄だけは下で「閉じてから出す」
                guard canPresentAlert else { return }
                let message = model.errorMessage ?? L("もう一度お試しください", "Please try again.")
                // ひとことを書いている間は、欄を閉じてから出す（重ねない・捨てない）
                if noteTarget != nil { deferredSaveError = message; return }
                leaveSaveError = message
            }
        }
        .font(.body.weight(.semibold))
        // **ヘッダーの文字の合図は真鍮**（デザインシステムの決まり）
        .foregroundStyle(WebTheme.accent)
        .opacity(isDirty && model.busy == nil ? 1 : 0.5)
        .disabled(!isDirty || model.busy != nil)
        .webTappable()
    }

    private func editor(_ plan: TripPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title)
                    .font(JPFont.cardTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    dateField(L("出発", "From"), value: $start, fallback: end, isStart: true)
                    dateField(L("帰着", "To"), value: $end, fallback: start, isStart: false)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, 4)
                }

                if days.isEmpty {
                    Text(L("まだ日程がありません。下から追加してください。", "No days yet. Add one below."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 4)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { di, day in
                    daySection(di, day)
                }

                addDayButton
                deleteCard(plan)
            }
            .padding(16)
        }
    }

    // MARK: - 出発・帰着

    /// 日付の欄。**端末の日付ピッカー**で選ぶ（Web は `type="date"`。文字で打たせない）。
    /// 空にもできる（Web も空を許す）
    private func dateField(_ title: String, value: Binding<String?>, fallback: String?,
                           isStart: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
            HStack(spacing: 4) {
                if value.wrappedValue != nil {
                    DatePicker(title, selection: pickerBinding(value, isStart: isStart), displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    Button {
                        value.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WebTheme.faint)
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
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.muted2)
                            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(title)の日付を入れる", "Set \(title) date"))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func daySection(_ di: Int, _ day: TripDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // 板どおり「1 日目」は普通の字、日付だけ等幅
                HStack(spacing: 0) {
                    Text(L("\(di + 1) 日目", "Day \(di + 1)"))
                        .font(.caption.weight(.medium))
                        .tracking(0.5)
                    if let date = TripPlanText.dayDate(index: di, day: day, start: start, end: end),
                       let label = TakenDay.label(date) {
                        Text(L("・\(label)", " · \(label)")).font(JPFont.mono(12))
                    }
                }
                .foregroundStyle(WebTheme.faint)
                .accessibilityElement(children: .combine)
                Spacer()
                // 地図で見る。**地図に置ける場所がある日だけ**（押しても空の地図を出さない）
                let stops = TripDayMap.stops(of: day, index: index, places: places)
                if TripDayMap.hasPins(stops) {
                    Button {
                        mapDay = MapTarget(day: di, stops: stops)
                    } label: {
                        Image(systemName: "map")
                            .foregroundStyle(WebTheme.muted2)
                            .webTappable()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(di + 1) 日目を地図で見る", "Show day \(di + 1) on a map"))
                    // 日の削除（赤）のすぐ隣に置かない（押し間違い・eaf0c48 のレビュー。空の日の削除は確認が無い）
                    .padding(.trailing, 8)
                }
                Button {
                    guard days.indices.contains(di) else { return }
                    if TripPlanEdit.confirmsRemoving(days[di]) {
                        removingDay = RemoveDayTarget(index: di, day: days[di])
                    } else {
                        days.remove(at: di)
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(WebTheme.danger)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("\(di + 1) 日目を削除", "Remove day \(di + 1)"))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if day.items.isEmpty {
                    Text(L("まだ何も入っていません。", "Nothing planned."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .padding(.horizontal, 14)
                }
                ForEach(Array(day.items.enumerated()), id: \.offset) { ii, item in
                    if ii > 0 { divider }
                    itemRow(di, ii, item)
                }
                divider
                addRow(di, full: day.items.count >= TripPlanService.itemsPerDayMax)
            }
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    private func itemRow(_ di: Int, _ ii: Int, _ item: TripItem) -> some View {
        let name = TripPlanText.label(for: item, index: index, places: places)
        return HStack(spacing: 12) {
            itemLink(item, name: name)
            itemMenu(di, ii, item, name: name)
            // **外す。** 日の削除（赤いゴミ箱）と見分けるため × にする
            Button {
                // 添字を確かめる（`add` と同じ）。描き直す前の古い添字で消さない
                guard days.indices.contains(di), days[di].items.indices.contains(ii) else { return }
                days[di].items.remove(at: ii)
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("「\(name)」を外す", "Remove \(name)"))
        }
        .padding(.trailing, 8)
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
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
    private func itemLink(_ item: TripItem, name: String) -> some View {
        switch item {
        case .spot(let spotId, _):
            if let spot = index.first(where: { $0.spotId == spotId }) {
                NavigationLink {
                    OfficialSpotView(spot: spot, spots: index, photos: photos)
                } label: {
                    itemLabel(name, icon: "mappin.and.ellipse", note: item.note)
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, icon: "mappin.and.ellipse", note: item.note)
            }
        case .location(let slug, _):
            if let place = places.first(where: { $0.slug == slug }) {
                NavigationLink {
                    SpotDetailView(spot: place, photos: photos)
                } label: {
                    itemLabel(name, icon: "map", note: item.note)
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, icon: "map", note: item.note)
            }
        }
    }

    private func itemLabel(_ name: String, icon: String, note: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(WebTheme.muted2)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                // 添えたひとこと（あるときだけ・薄く小さく）
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func addRow(_ di: Int, full: Bool) -> some View {
        Button {
            picking = PickTarget(day: di)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .foregroundStyle(WebTheme.muted2)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(L("行きたい場所から追加…", "Add a saved place…"))
                    .font(.body)
                    .foregroundStyle(WebTheme.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            Label(L("日を追加", "Add a day"), systemImage: "plus")
                .font(.subheadline)
                .foregroundStyle(WebTheme.foreground)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.5 : 1)
    }

    // MARK: - 削除

    /// **消す前に一度聞く。** 日程ごと消えるうえ、戻す手が無い（Web と同じ）
    private func deleteCard(_ plan: TripPlan) -> some View {
        let title = plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title
        return VStack(spacing: 0) {
            Button {
                confirmingDelete.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash").frame(width: 20).accessibilityHidden(true)
                    Text(L("「\(title)」を削除", "Delete \(title)"))
                    Spacer(minLength: 0)
                }
                .font(.body)
                .foregroundStyle(WebTheme.danger)
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if confirmingDelete {
                divider
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("この旅行プランを削除しますか？", "Delete this trip?"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                    HStack(spacing: 8) {
                        Button {
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
                        } label: {
                            Text(L("削除する", "Delete"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(WebTheme.danger)
                                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busy != nil)
                        .opacity(model.busy == nil ? 1 : 0.5)
                        Button {
                            confirmingDelete = false
                        } label: {
                            Text(Labels.Common.cancel)
                                .font(.footnote)
                                .foregroundStyle(WebTheme.foreground)
                                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
