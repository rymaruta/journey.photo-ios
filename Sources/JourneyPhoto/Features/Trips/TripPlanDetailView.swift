import SwiftUI

/// 旅行プランの日程（キャンバス「17b 旅行プランの日程」／ Web の `PlanEditor`）。
///
/// **保存は明示的。** 打つたびにサーバーへ送らず、右上の「保存」で送る。
/// 変えていなければ押させない（無駄な往復と、他の端末の編集の打ち消しを避ける）。
/// 送るのは**変えた項目だけ**（`TripPlanText.patch`）。
struct TripPlanDetailView: View {

    let planId: String
    @ObservedObject var model: TripPlansModel

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @Environment(\.dismiss) private var dismiss

    /// 手元の下書き。**開き直したらサーバーの姿に戻す**（Web と同じ）
    @State private var days: [TripDay] = []
    @State private var start: String?
    @State private var end: String?
    @State private var loadedFrom: TripPlan?
    /// 「行きたい場所から追加」を押した日
    @State private var picking: PickTarget?
    @State private var confirmingDelete = false
    /// 名前を引く材料（取れなくても画面は出る——名前が鍵のままになるだけ）
    @State private var photos: [Photo] = []
    @State private var index: [OfficialSpot] = []

    private struct PickTarget: Identifiable { let day: Int; var id: Int { day } }

    private var plan: TripPlan? { model.plan(planId) }
    private var places: [DerivedSpot.Place] { DerivedSpot.all(in: photos) }

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { saveButton }
        }
        .task {
            photos = (try? await environment.gallery.fetchPhotos()) ?? []
            index = (try? await environment.spots.fetchIndex()) ?? []
        }
        .onAppear { resetIfNeeded() }
        .onChange(of: plan) { _, _ in resetIfNeeded() }
        .sheet(item: $picking) { target in
            NavigationStack {
                TripPlanPickSheet(dayIndex: target.day,
                                  choices: TripPlanText.choices(wishlistKeys: wishlist.spotIds,
                                                                places: places, index: index)) { choice in
                    add(choice.item, to: target.day)
                }
            }
        }
    }

    /// サーバーの姿が変わったら（保存・取り直し）、下書きをそれに合わせる
    private func resetIfNeeded() {
        guard let plan, plan != loadedFrom else { return }
        loadedFrom = plan
        days = plan.days
        start = plan.startDate
        end = plan.endDate
    }

    private var isDirty: Bool {
        guard let plan else { return false }
        return TripPlanText.isDirty(plan: plan, days: days, start: start, end: end)
    }

    private var saveButton: some View {
        Button(L("保存", "Save")) {
            guard let plan else { return }
            let patch = TripPlanText.patch(plan: plan, days: days, start: start, end: end)
            Task { _ = await model.update(planId, patch, environment: environment) }
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
                    dateField(L("出発", "From"), value: $start, fallback: end)
                    dateField(L("帰着", "To"), value: $end, fallback: start)
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
    private func dateField(_ title: String, value: Binding<String?>, fallback: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
            HStack(spacing: 4) {
                if value.wrappedValue != nil {
                    DatePicker(title, selection: pickerBinding(value), displayedComponents: .date)
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
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `YYYY-MM-DD` ⇔ ピッカーの日。**端末のゾーンのその日**で読み書きする
    private func pickerBinding(_ value: Binding<String?>) -> Binding<Date> {
        Binding(
            get: { TripPlanText.pickerDate(fromYMD: value.wrappedValue, in: .current) ?? Date() },
            set: { value.wrappedValue = TripPlanText.ymd(pickedIn: .current, $0) }
        )
    }

    // MARK: - 日ごと

    private func daySection(_ di: Int, _ day: TripDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(TripPlanText.dayHeading(index: di, day: day, start: start, end: end))
                    .font(JPFont.mono(12))
                    .foregroundStyle(WebTheme.faint)
                Spacer()
                Button {
                    days.remove(at: di)
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
            // **外す。** 日の削除（赤いゴミ箱）と見分けるため × にする
            Button {
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

    /// 名前を押すとその場所へ。**開ける先が無いものは行だけ**（押しても何も起きない札を作らない）
    @ViewBuilder
    private func itemLink(_ item: TripItem, name: String) -> some View {
        switch item {
        case .spot(let spotId, _):
            if let spot = index.first(where: { $0.spotId == spotId }) {
                NavigationLink {
                    OfficialSpotView(spot: spot, spots: index, photos: photos)
                } label: {
                    itemLabel(name, icon: "mappin.and.ellipse")
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, icon: "mappin.and.ellipse")
            }
        case .location(let slug, _):
            if let place = places.first(where: { $0.slug == slug }) {
                NavigationLink {
                    SpotDetailView(spot: place, photos: photos)
                } label: {
                    itemLabel(name, icon: "map")
                }
                .buttonStyle(.plain)
            } else {
                itemLabel(name, icon: "map")
            }
        }
    }

    private func itemLabel(_ name: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(WebTheme.muted2)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(name)
                .font(.body)
                .foregroundStyle(WebTheme.text)
                .lineLimit(2)
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
                                if await model.remove(planId, environment: environment) { dismiss() }
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
