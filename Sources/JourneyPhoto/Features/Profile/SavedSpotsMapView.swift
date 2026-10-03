import SwiftUI
import UIKit
import MapKit

/// 「行きたい場所」を地図で見る（3か月の計画の7の第一歩・2026-10-03）。
///
/// マイページの「行きたい場所」のタブの「地図で見る」から積む。並べるのは一覧と同じ行
/// （撮影地と台帳の撮影スポット）で、分け方・枠の計算は `SavedSpotsMap`（Linux で試験）。
///
///  - 地図の枠は**保存した場所が全部入る範囲**（`SavedSpotsMap.frame`。地図のタブのように
///    「いちばん重い塊」には寄せない）
///  - ピンは撮影スポットと同じ印（`SpotMapMarker`・真鍮）。**押すと選ぶ／外す**（2026-10-03・
///    複数えらべる）。選んだピンは板 MapPlace の選択中（accent-deep の丸・白 3pt の縁・黒 1pt の輪）
///    に白のチェック（色だけで状態を言わない——形も変える）。開くのは下の「選んだ場所」の行から
///  - 1か所以上選ぶと「この N か所で旅行プランを作る」（写真の無い画面の主ボタン＝真鍮の塗り＋墨）。
///    押すと既存の旅行プランを作って日程の画面へ（`SavedSpotsTrip`・板 WishlistTab と同じ流れ）
///  - 旅行プランに入っている場所はピンの右上に小さな印（プランの一覧と突き合わせるだけ）
///  - 座標の無いものは地図の下に一覧で残す（黙って消さない）
///  - 0件のときは「撮影スポットを探す」（地図のタブ）への出口
///
/// 🔴 **行は積んだときの写しを受け取る**（`MyPageView.wishIds` と同じ理由）。開いた
/// スポットで♥を外した瞬間に行が消えると、開いている画面が閉じる。戻れば一覧が取り直す
struct SavedSpotsMapView: View {

    let split: SavedSpotsMap.Split
    /// 撮影スポットの画面に渡す索引（近くのスポットを出すのに使う）
    let officialSpots: [OfficialSpot]
    /// 撮影地・撮影スポットの画面に渡す写真の集まり（マイページの `pool`）
    let photos: [Photo]
    /// 写真の一覧が読めているか（`OfficialSpotView.photosKnown`）
    let photosKnown: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter

    @State private var camera: MapCameraPosition = .automatic
    /// 枠を決めたときのピンの鍵（同じ集まりなら決め直さない・`frameIfNeeded`）
    @State private var framedKeys: [String]?
    /// 押したピン・行の鍵。開く先は `navigationDestination(item:)`
    @State private var opened: String?
    /// 選んだ場所（押した順）。近い順の案は最初に選んだ場所から始める
    @State private var selection = SavedSpotsTrip.Selection()
    /// 作っている最中（この画面だけの印）。**押した瞬間に同期で立てる**——`plans.busy` は
    /// `Task` の中で立つので、その前の二度押しで2つ作られうる
    @State private var creating = false
    /// 旅行プランの一覧（どのプランに入っているかの印と、作る口）。既存の model をそのまま使う
    @StateObject private var plans = TripPlansModel()
    /// 作ったプラン。日程の画面へ積む（板 WishlistTab: 押すと TripPlanDays へ）
    @State private var createdPlanId: String?
    /// 作れなかった事情（サーバーの言い分をそのまま）
    @State private var createError: String?

    private var selectedItems: [SavedSpotsMap.Item] {
        SavedSpotsTrip.nearestOrder(selection.items(in: split.pinned))
    }
    /// 項目の鍵 → 入っているプランの題。**一覧が取れたときだけ**（取れない回に「入っていない」と言わない）
    private var membership: [String: [String]] {
        plans.status == .loaded ? SavedSpotsTrip.membership(plans.plans) : [:]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if split.isEmpty {
                    emptyArea
                } else {
                    Text(SavedSpotsMap.summary(split))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 16)
                    if !split.pinned.isEmpty {
                        map
                        selectionArea
                    }
                    if !split.unplaced.isEmpty {
                        unplacedList
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .webScreen()
        .navigationTitle(L("行きたい場所の地図", "Want-to-go map"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { key in
            destination(for: key)
        }
        .navigationDestination(item: $createdPlanId) { planId in
            TripPlanDetailView(planId: planId, model: plans)
        }
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty {
                createBar
            }
        }
        .onAppear { frameIfNeeded() }
        .onChange(of: split.pinned.map(\.key)) { _, _ in frameIfNeeded() }
        // 日程の画面から戻るたびに取り直す（そこで外した・足した場所の印を合わせる）
        .task(id: createdPlanId == nil) {
            guard createdPlanId == nil else { return }
            await plans.load(environment: environment)
        }
    }

    // MARK: - 地図

    private var map: some View {
        Map(position: $camera) {
            ForEach(split.pinned) { item in
                // 題は MapKit がピンの下に字で描く（地図のタブの撮影スポットと同じ）
                Annotation(item.name, coordinate: coordinate(item)) {
                    pin(item)
                }
            }
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        // 地図そのものにラベルを付けない（1つの要素にまとまってピンに入れなくなりうる・`TripDayMapView` と同じ）
    }

    /// ピン。**選べる場所は押すと選ぶ／外す**。選べない場所（プランに入れる鍵の無い撮影地）は今までどおり開く
    private func pin(_ item: SavedSpotsMap.Item) -> some View {
        let selectable = SavedSpotsTrip.canSelect(item)
        let selected = selection.contains(item.key)
        let inPlans = SavedSpotsTrip.plans(containing: item, in: membership)
        return Button {
            if selectable { toggle(item) } else { open(item) }
        } label: {
            // 印は 32〜44pt、押せる範囲は 44pt（中心は変わらない）
            SavedSpotPin(photoURL: item.imageURL, selected: selected, inPlan: !inPlans.isEmpty)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 作っている最中は選び直させない（送った日程と画面の選択が食い違う）
        .disabled(isBusy)
        // 選ばずに開く口（長押し・VoiceOver の操作）。**上限に達していても開ける**
        .contextMenu {
            if item.canOpen {
                Button { open(item) } label: {
                    Label(L("開く", "Open"), systemImage: "arrow.up.right.square")
                }
            }
        }
        .accessibilityAction(named: L("開く", "Open")) { open(item) }
        .accessibilityLabel(pinLabel(item, inPlans: inPlans))
        // 選択の状態は値と特性の両方で伝える（VoiceOver は「選択中」と読む）
        .accessibilityValue(selectable ? (selected ? L("選択中", "Selected") : L("未選択", "Not selected")) : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selectable
            ? (selected ? L("押すと選択を外します", "Double-tap to deselect")
                        : L("押すと旅行プランに入れる場所として選びます", "Double-tap to select for a trip"))
            : SavedSpotsMap.openHint(item))
        .accessibilityIdentifier("savedMap.pin")
    }

    private func pinLabel(_ item: SavedSpotsMap.Item, inPlans: [String]) -> String {
        var parts = [SavedSpotsMap.spokenLabel(item)]
        if let phrase = SavedSpotsTrip.membershipPhrase(inPlans) { parts.append(phrase) }
        return parts.joined(separator: " · ")
    }

    private func toggle(_ item: SavedSpotsMap.Item) {
        let wasSelected = selection.contains(item.key)
        guard !isBusy else { return }
        guard selection.toggle(item.key) else {
            // 写真から選ぶ板（`TripPickerView.choose`）と同じ知らせ方。一覧の下の文字では
            // 地図を見ている人に見えない
            toasts.show(limitText, kind: .failure)
            return
        }
        createError = nil
        announce(wasSelected ? removedText(item) : L("\(item.name) を選びました。選んだ場所 \(selection.count) か所",
                                                     "Selected \(item.name). \(selection.count) selected"))
    }

    private func removedText(_ item: SavedSpotsMap.Item) -> String {
        L("\(item.name) を外しました。選んだ場所 \(selection.count) か所",
          "Removed \(item.name). \(selection.count) selected")
    }

    private var limitText: String {
        L("一度に選べるのは \(SavedSpotsTrip.selectMax) か所までです",
          "You can select up to \(SavedSpotsTrip.selectMax) places at a time")
    }

    /// 読み上げ（選んだ・外したを、焦点を動かさずに伝える）
    private func announce(_ text: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    private func coordinate(_ item: SavedSpotsMap.Item) -> CLLocationCoordinate2D {
        let coords = item.coords ?? Photo.Coords(lat: 0, lng: 0)
        return CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
    }

    /// 枠は全部が入る範囲（`SavedSpotsMap.frame`）。点が無ければ地図の既定のまま。
    ///
    /// 🔴 **ピンの集まりが変わったときだけ**決め直す。開いた画面から戻るたびに決め直すと、
    /// 利用者が寄せた・動かした地図が全体の枠へ戻った（レビュー）。行は積んだときの写しなので、
    /// ふだんは初回の1度だけ。行が差し替わった（索引が後から届いた）ときは決め直す
    private func frameIfNeeded() {
        let keys = split.pinned.map(\.key)
        guard framedKeys != keys else { return }
        framedKeys = keys
        guard let frame = SavedSpotsMap.frame(for: split.pinned.compactMap(\.coords)) else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: frame.latitude, longitude: frame.longitude),
            span: MKCoordinateSpan(latitudeDelta: frame.latitudeSpan,
                                   longitudeDelta: frame.longitudeSpan)
        ))
    }

    // MARK: - 選んだ場所（近い順の案）

    /// 地図の下。選ぶ前は使い方の一行、選んだら**近い順の案**で並べる（番号は回る順・等幅の数字）。
    /// 行を押すとその場所を開く。× は選択から外すだけ（「行きたい」には残る）
    private var selectionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selection.isEmpty {
                Text(L("ピンを押して場所を選ぶと、旅行プランを作れます。複数えらべます。押し直すと外れます。開くには、選んだあと下の行を押します。",
                       "Tap pins to choose places for a trip. You can pick several; tap again to remove. To open a place, select it and tap its row below."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("選んだ場所 · 近い順の案", "Selected · nearest-first"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
                // **何をしたかを正直に書く**（移動時間・道のりは計算していない・`TripPlan` の約束）
                Text(L("直線の距離で近い順に並べた案です。移動時間や道のりは計算していません。作ったあと、日程の画面で入れ替えられます。",
                       "Ordered by straight-line distance. Travel time isn't calculated. You can rearrange it after creating."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(selectedItems.enumerated()), id: \.element.key) { offset, item in
                        if offset > 0 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        }
                        selectedRow(offset, item)
                    }
                }
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
    }

    private func selectedRow(_ offset: Int, _ item: SavedSpotsMap.Item) -> some View {
        let inPlans = SavedSpotsTrip.plans(containing: item, in: membership)
        let detail = SavedSpotsTrip.membershipPhrase(inPlans) ?? item.subtitle
        return HStack(spacing: 8) {
            Button { open(item) } label: {
                HStack(spacing: 12) {
                    // 回る順の番号（数は合図ではないので白・等幅の数字）
                    Text("\(offset + 1)")
                        .font(JPFont.mono(13, medium: true))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(minWidth: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.foreground)
                            .lineLimit(2)
                        if let detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(WebTheme.faint)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .accessibilityHidden(true)
                }
                .padding(.leading, 14)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(offset + 1) 番目 · ", "Stop \(offset + 1) · ") + pinLabel(item, inPlans: inPlans))
            .accessibilityHint(SavedSpotsMap.openHint(item))
            .accessibilityIdentifier("savedMap.selected")

            Button {
                guard !isBusy else { return }
                selection.remove(item.key)
                announce(removedText(item))
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(L("「\(item.name)」を選択から外す", "Deselect \(item.name)"))
        }
        .padding(.trailing, 4)
    }

    // MARK: - 旅行プランを作る

    /// 作っている最中か（この画面の印か、プランの書き込み中）。ピン・× ・主ボタンを止める
    private var isBusy: Bool { creating || plans.busy != nil }
    private var canCreate: Bool { !selection.isEmpty && !isBusy }

    /// **写真の無い画面の主ボタン1つ＝真鍮の塗り＋墨の字**（デザインシステム・CLAUDE.md）。
    /// 形は板 WishlistTab「この3か所で旅行プランを作る」（高さ 52・角は丸）
    private var createBar: some View {
        VStack(spacing: 6) {
            if let createError {
                Text(createError)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("savedMap.createError")
            }
            Button { create() } label: {
                HStack(spacing: 8) {
                    if isBusy { ProgressView().tint(WebTheme.accentText) }
                    Text(SavedSpotsTrip.createLabel(count: selection.count))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(WebTheme.accentText)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WebTheme.accentFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
            .opacity(canCreate ? 1 : 0.5)
            .accessibilityHint(L("近い順に並べた日程で旅行プランを作り、日程の画面を開きます。日付は次の画面で入れます",
                                 "Creates a trip in nearest-first order and opens it. Set dates on the next screen."))
            .accessibilityIdentifier("savedMap.createTrip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WebTheme.background)
    }

    /// 既存の作成の口（`TripPlansModel.create`・題と日程を1回で送る）。日付は送らない（日程の画面で入れる）
    private func create() {
        guard canCreate, let draft = SavedSpotsTrip.draft(selectedItems) else { return }
        // **同期で立てる**（次の押下はこれを見て止まる）
        creating = true
        createError = nil
        Task {
            defer { creating = false }
            guard let made = await plans.create(title: draft.title, days: draft.days, environment: environment) else {
                let message = plans.errorMessage
                    ?? L("旅行プランを作れませんでした。もう一度お試しください。", "Couldn't create the trip. Please try again.")
                createError = message
                // 文はこの画面で出す（model に残すと、開いた日程の画面の上に赤い行が残る）
                plans.clearError()
                // 下の帯の赤い行は VoiceOver の焦点の外にあるので、読み上げでも伝える
                announce(message)
                return
            }
            createError = nil
            selection = SavedSpotsTrip.Selection()
            createdPlanId = made.planId
        }
    }

    // MARK: - 座標の無いもの

    private var unplacedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("地図に置けない場所", "Not on the map"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(L("場所（座標）が分からないため、地図には出していません。",
                   "These don't have a known location, so they aren't on the map."))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .padding(.top, 4)
                .padding(.bottom, 6)
            ForEach(split.unplaced) { item in
                if item.canOpen {
                    Button { open(item) } label: { unplacedRow(item) }
                        .buttonStyle(.plain)
                        .accessibilityHint(SavedSpotsMap.openHint(item))
                } else {
                    unplacedRow(item)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func unplacedRow(_ item: SavedSpotsMap.Item) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if item.canOpen {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(WebTheme.faint)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SavedSpotsMap.spokenLabel(item))
        .accessibilityIdentifier("savedMap.unplaced")
    }

    // MARK: - 0件

    /// 板 WishlistTab の B1（空）と同じ言い方。行は積んだときの写しなので、開いている間に
    /// 外してもここへは変わらない。一覧が空なら「地図で見る」は出ないので、ふだんは来ない
    /// （空の写しで積まれたときの守り）
    private var emptyArea: some View {
        VStack(spacing: 4) {
            EmptyState(message: L("行きたい場所はまだありません。撮影スポットで「行きたい」を押すと、ここの地図に並びます。",
                                  "No places yet. Tap “Want to go” on a photo spot to see it on this map."))
            FindSpotsButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - 開く先

    private func open(_ item: SavedSpotsMap.Item) {
        guard item.canOpen else { return }
        opened = item.key
    }

    @ViewBuilder
    private func destination(for key: String) -> some View {
        let item = split.pinned.first { $0.key == key } ?? split.unplaced.first { $0.key == key }
        switch item?.target {
        case .place(let place):
            SpotDetailView(spot: place, photos: photos)
        case .official(let row):
            if let spot = row.spot {
                OfficialSpotView(spot: spot, spots: officialSpots, photos: photos, photosKnown: photosKnown)
            } else {
                EmptyState(message: L("この撮影スポットは開けません", "This spot can't be opened"))
            }
        case nil:
            EmptyState(message: L("この場所は開けません", "This place can't be opened"))
        }
    }
}

/// 「行きたい場所」が0件のときの出口（板 WishlistTab の B1「撮影スポットを探す」）。
/// 撮影スポットを名前・近い順で探せるのは地図のタブ（`OfficialPins` の注記——検索の画面には節を足さない）。
/// **写真の無い画面の主ボタン1つ＝真鍮の塗り＋墨の字**（デザインシステム・CLAUDE.md）
struct FindSpotsButton: View {
    var body: some View {
        Button {
            TabRouter.shared.openMap()
        } label: {
            Text(L("撮影スポットを探す", "Find photo spots"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.accentText)
                .padding(.horizontal, 24)
                .frame(minHeight: 48)
                .background(WebTheme.accentFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("マップのタブを開きます", "Opens the Map tab"))
        .accessibilityIdentifier("wishlist.findSpots")
    }
}

/// 「行きたい場所」の地図のピン。選んでいないときは撮影スポットと同じ印（`SpotMapMarker`）。
///
///     選択中  accent-deep の丸 44pt・白 3pt の縁・黒 1pt の輪・白のチェック（板 MapPlace の選択中）。
///             **色だけで状態を言わない**（デザインシステム「選択は必ず形も変える」）——拡大＋チェック
///     プラン  右上に白い丸 18pt・墨のスーツケース・黒 2pt の縁。地図の上（黒地ではない）なので白。
///             真鍮の小さな丸は未読・件数の合図と紛れる
///
/// 押せる範囲と読み上げは呼ぶ側のボタンが付ける（ここは絵だけ）
struct SavedSpotPin: View {
    let photoURL: URL?
    let selected: Bool
    let inPlan: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(WebTheme.accentDeep, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                    .overlay(Circle().stroke(Color.black, lineWidth: 1))
                    .shadow(color: .black.opacity(0.65), radius: 10, y: 8)
                    .accessibilityHidden(true)
            } else {
                SpotMapMarker(photoURL: photoURL)
                    .frame(width: 44, height: 44)
            }
            if inPlan {
                Image(systemName: "suitcase.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(width: 18, height: 18)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44)
    }
}
