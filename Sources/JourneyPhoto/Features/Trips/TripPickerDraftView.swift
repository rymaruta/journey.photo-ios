import SwiftUI

/// 写真から選んだ場所の旅行プランの下書き（`TripPickerView` の次）。
///
/// 選んだ場所を**地域（国・都道府県）で束ね、近い順に日へ割り振った**姿を見せる
/// （`TripPicker.grouped` / `days`）。出発・帰着を入れると、その日数に合わせて
/// 割り振り直す。題・日付・日程を見て「保存」で作る。
///
/// **保存は1回。** 題・日程・日付をまとめて作る（`POST /user/trips`・サーバーの `createTrip` が
/// 全部読む）。以前は作ってから `PUT` で日程を入れる2段で、2段目で落ちると空のプランが残った。
///
/// 移動時間・道のり・費用は**出さない**（計算していない。`TripPlanText` の約束）。
/// 並びは直線の距離で近い順にしただけなので、そう書く。
struct TripPickerDraftView: View {

    @ObservedObject var picker: TripPickerModel
    @ObservedObject var plans: TripPlansModel
    let onSaved: (String) -> Void

    @EnvironmentObject private var environment: AppEnvironment

    /// 保存の最中か（`TripPickerModel.saving`。板の「閉じる」もこれで止める）
    private var saving: Bool {
        get { picker.saving }
        nonmutating set { picker.saving = newValue }
    }

    // 題・日付・失敗の文は `TripPickerModel` が持つ（開き直しで消さない）。ここは読み書きを流すだけ
    private var start: String? {
        get { picker.draftStart }
        nonmutating set { picker.draftStart = newValue }
    }
    private var end: String? {
        get { picker.draftEnd }
        nonmutating set { picker.draftEnd = newValue }
    }
    private var errorText: String? {
        get { picker.draftError }
        nonmutating set { picker.draftError = newValue }
    }

    private var groups: [[OfficialSpot]] { TripPicker.grouped(picker.picked) }
    private var days: [[OfficialSpot]] {
        TripPicker.days(groups, dayCount: TripPicker.dayCount(start: start, end: end))
    }
    private var suggestedTitle: String { TripPicker.defaultTitle(groups) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                titleField
                HStack(spacing: 10) {
                    dateField(L("出発", "From"), value: $picker.draftStart, fallback: end, isStart: true)
                    dateField(L("帰着", "To"), value: $picker.draftEnd, fallback: start, isStart: false)
                }
                Text(dateNote)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("tripPicker.draft.error")
                }

                if picker.picked.isEmpty {
                    Text(L("場所がありません。前の画面で写真を選んでください。",
                           "No places yet. Go back and pick some photos."))
                        .font(.callout)
                        .foregroundStyle(WebTheme.muted2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        daySection(index, day)
                    }
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        // 保存の最中は戻らせない（戻ってもう一度保存すると、作る途中のプランと重なる）
        .navigationBarBackButtonHidden(saving)
        .webScreen()
        .navigationTitle(L("旅行プランの下書き", "Trip draft"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 頭

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Draft")
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(L("選んだ \(picker.picked.count) か所の旅", "A trip with \(picker.picked.count) places"))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.foreground)
            // **何をしたかを正直に書く**（道のり・移動時間は計算していない）
            Text(L("地域ごとに束ね、直線の距離で近い順に並べました。移動時間や道のりは計算していません。保存したあと、日程の画面で入れ替えられます。",
                   "Grouped by region and ordered by straight-line distance. Travel time isn't calculated. You can rearrange it after saving."))
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var titleField: some View {
        TextField(suggestedTitle, text: $picker.draftTitle)
            .font(.body)
            .foregroundStyle(WebTheme.foreground)
            .submitLabel(.done)
            // **上限で止める**（一覧の「作る」と同じ）
            .onChange(of: picker.draftTitle) { old, new in
                let kept = PostLimits.limited(old: old, new: new, limit: TripPlanService.titleMax)
                if kept != new { picker.draftTitle = kept }
            }
            .accessibilityLabel(L("旅行プランのタイトル", "Trip title"))
            .padding(.horizontal, 14)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var dateNote: String {
        TripPicker.dateNote(dayCount: TripPicker.dayCount(start: start, end: end), planned: days.count)
    }

    // MARK: - 出発・帰着（`TripPlanDetailView` と同じ決まり）

    private func dateField(_ label: String, value: Binding<String?>, fallback: String?,
                           isStart: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
            HStack(spacing: 4) {
                if value.wrappedValue != nil {
                    DatePicker(label, selection: pickerBinding(value, isStart: isStart), displayedComponents: .date)
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
                    .accessibilityLabel(L("\(label)の日付を消す", "Clear \(label)"))
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
                    .accessibilityLabel(L("\(label)の日付を入れる", "Set \(label) date"))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `YYYY-MM-DD` ⇔ ピッカーの日。選んだときだけ前後を揃える（`TripPlanText.ordered`）
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

    private func daySection(_ index: Int, _ day: [OfficialSpot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(TripPlanText.dayHeading(index: index, day: TripDay(), start: start, end: end))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WebTheme.faint)
                if let region = TripPicker.regionLabel(of: day) {
                    Text(region)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if day.isEmpty {
                    Text(L("まだ何も入っていません。", "Nothing planned."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .padding(.horizontal, 14)
                }
                ForEach(Array(day.enumerated()), id: \.element.spotId) { offset, spot in
                    if offset > 0 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                    row(spot)
                }
            }
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func row(_ spot: OfficialSpot) -> some View {
        HStack(spacing: 12) {
            // 小さな写真は見分けるための手がかり（出典は札の画面で出している。ここでは名前を主に読む）
            if let photo = spot.photo {
                Color.clear
                    .frame(width: 44, height: 44)
                    // 44pt の枠なので縮小版（読めなければ元の画像・`SpotThumbImage`）
                    .overlay(SpotThumbImage(image: photo))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                if let region = spot.regionLabel {
                    Text(region)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // **このプランから外すだけ**（「行きたい」には残る）
            // 保存の間は外させない（押した時点の日程を送っていて、済むとすぐ閉じる）
            Button {
                guard !saving else { return }
                picker.remove(spot.spotId)
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .accessibilityLabel(L("「\(spot.name)」をこのプランから外す", "Remove \(spot.name) from this trip"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 60)
    }

    // MARK: - 保存

    private var canSave: Bool { !picker.picked.isEmpty && !saving && plans.busy == nil }

    /// 写真のある画面の主ボタン＝白の塗り＋墨（1画面に1つ）
    private var saveBar: some View {
        Button { save() } label: {
            HStack(spacing: 8) {
                if saving { ProgressView().tint(WebTheme.accentText) }
                Text(L("旅行プランを保存", "Save trip"))
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(WebTheme.accentText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(WebTheme.accentBackground, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WebTheme.background)
        .accessibilityIdentifier("tripPicker.save")
    }

    private func save() {
        guard canSave else { return }
        let trimmed = picker.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let sendTitle = TripPlanService.titleToSend(trimmed.isEmpty ? suggestedTitle : trimmed)
        // **押した時点の日程を送る**（待っている間に外した場所は次の保存で）
        let sendDays = TripPicker.tripDays(days)
        let sendStart = start
        let sendEnd = end
        saving = true
        errorText = nil
        Task {
            defer { saving = false }
            // **題・日程・日付を1回で作る。** 作ってから日程を別に送ると、2回目で落ちた回に
            // 空のプランが残った
            guard let made = await plans.create(title: sendTitle, days: sendDays,
                                                startDate: sendStart, endDate: sendEnd,
                                                environment: environment) else {
                errorText = plans.errorMessage
                    ?? L("旅行プランを作れませんでした。もう一度お試しください。", "Couldn't create the trip. Please try again.")
                // 文はこの画面で出す。**一覧の model に残さない**（板を閉じたあと、取れている
                // 一覧の上に赤い行が残る。一覧は自分の読み込みの失敗だけを出す）
                plans.clearError()
                return
            }
            onSaved(made.planId)
        }
    }
}
