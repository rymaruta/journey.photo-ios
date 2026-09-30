import SwiftUI

/// 写真から選んだ場所の旅行プランの下書き（`TripPickerView` の次）。
///
/// 選んだ場所を**地域（国・都道府県）で束ね、近い順に日へ割り振った**姿を見せる
/// （`TripPicker.grouped` / `days`）。出発・帰着を入れると、その日数に合わせて
/// 割り振り直す。題・日付・日程を見て「保存」で作る。
///
/// **保存は2段。** 作る（`POST /user/trips`・題だけ）→ 日程と日付を入れる（`PUT`）。
/// サーバーの口は変えない。2段目が断られたときは、作ったプランを覚えて
/// **次の「保存」は2段目だけ**をやり直す（同じ題のプランを2つ作らない）。
///
/// 移動時間・道のり・費用は**出さない**（計算していない。`TripPlanText` の約束）。
/// 並びは直線の距離で近い順にしただけなので、そう書く。
struct TripPickerDraftView: View {

    @ObservedObject var picker: TripPickerModel
    @ObservedObject var plans: TripPlansModel
    let onSaved: (String) -> Void

    @EnvironmentObject private var environment: AppEnvironment

    @State private var title = ""
    @State private var start: String?
    @State private var end: String?
    @State private var saving = false
    @State private var errorText: String?

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
                    dateField(L("出発", "From"), value: $start, fallback: end, isStart: true)
                    dateField(L("帰着", "To"), value: $end, fallback: start, isStart: false)
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
        TextField(suggestedTitle, text: $title)
            .font(.body)
            .foregroundStyle(WebTheme.foreground)
            .submitLabel(.done)
            // **上限で止める**（一覧の「作る」と同じ）
            .onChange(of: title) { old, new in
                let kept = PostLimits.limited(old: old, new: new, limit: TripPlanService.titleMax)
                if kept != new { title = kept }
            }
            .accessibilityLabel(L("旅行プランのタイトル", "Trip title"))
            .padding(.horizontal, 14)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var dateNote: String {
        if let count = TripPicker.dayCount(start: start, end: end) {
            return L("\(count) 日間に割り振りました。", "Spread over \(count) days.")
        }
        return L("出発と帰着を入れると、その日数に合わせて割り振ります。",
                 "Set both dates to spread places over your trip.")
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
                    .overlay(RemoteImage(url: photo.url))
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
                Text(picker.createdPlanId == nil ? L("旅行プランを保存", "Save trip") : L("日程をもう一度保存", "Save the days again"))
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
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sendTitle = TripPlanService.titleToSend(trimmed.isEmpty ? suggestedTitle : trimmed)
        // **押した時点の日程を送る**（待っている間に外した場所は次の保存で）
        let sendDays = TripPicker.tripDays(days)
        let sendStart = start
        let sendEnd = end
        saving = true
        errorText = nil
        Task {
            defer { saving = false }
            let planId: String
            if let made = picker.createdPlanId {
                planId = made
            } else {
                guard let made = await plans.create(title: sendTitle, environment: environment) else {
                    errorText = plans.errorMessage
                        ?? L("旅行プランを作れませんでした。もう一度お試しください。", "Couldn't create the trip. Please try again.")
                    return
                }
                picker.createdPlanId = made.planId
                picker.createdTitle = sendTitle
                planId = made.planId
            }
            var patch = TripPlanService.Patch()
            patch.days = sendDays
            if let sendStart { patch.startDate = sendStart }
            if let sendEnd { patch.endDate = sendEnd }
            // やり直しの間に題を変えていたら、それも送る
            if let createdTitle = picker.createdTitle, createdTitle != sendTitle { patch.title = sendTitle }
            guard await plans.update(planId, patch, environment: environment) else {
                let reason = plans.errorMessage ?? L("もう一度お試しください", "Please try again")
                errorText = L("旅行プランは作りましたが、日程を保存できませんでした（\(reason)）。もう一度保存してください。",
                              "The trip was created, but the days couldn't be saved (\(reason)). Please save again.")
                return
            }
            onSaved(planId)
        }
    }
}
