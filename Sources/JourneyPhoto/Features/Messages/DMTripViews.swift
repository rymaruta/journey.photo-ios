import SwiftUI

// DM の会話から旅行プランを作る（2026-11-12 判断・資料「SNS をもっと SNS に」2a の段①と段②・1.1.83）。
//
// 押す回数: 今 約14回（写真ごとに開く→行きたい ×3、マイページ→旅行プラン→作る→3つ選ぶ→日付→作る）→ 4 回
// （帯 → 日付を選ぶ → 休みの組 → 旅行プランを作る）。
//
// - 帯は**場所が1つでも出た会話にだけ**出す（設定なし）。地は案内の帯（真鍮 8%・`WebTheme.accentSoft`）に真鍮の縁と字
// - 下書きは送られた写真・送った写真の撮影地と、吹き出しから入れた撮影スポット。押すと外れる・押し直すと戻る。
//   閉じれば消える（確かめのダイアログは出さない）
// - 日付から先は旅行プランを作る流れの日付の段（`TripCreateDatesStep`）をそのまま使い、この段で保存する
// - **相手と共有する口は出さない**（2b の「プランの仲間」は DB の変更が要る・owner の承認待ち）。AI でまとめる段③も作らない

/// 会話の旅行プランの状態（索引・別名・公開の写真と、吹き出しから入れた場所）。会話の画面の外に持つ
@MainActor
final class DMTripModel: ObservableObject {

    @Published private(set) var index: [OfficialSpot] = []
    @Published private(set) var aliases: [String: [String]] = [:]
    /// 公開の写真（ID → 写真・読んだときに1回だけ作る）
    @Published private(set) var photosById: [String: Photo] = [:]
    /// 吹き出しから入れた場所（入れた順）。会話を閉じれば消える
    @Published private(set) var added: [DMTripPlaces.Found] = []
    @Published private(set) var loaded = false
    /// 揃えた名前の表（索引を読んだときに1回だけ作る・会話の画面は打つたびに描き直す）
    private var names = DMTripPlaces.NameTable.empty
    /// 索引を読めなかった（文から拾えない・候補を出せない）
    @Published private(set) var failed = false
    private var loading = false
    /// 公開の写真を読めた（座標を引く表）。読めなかった回は次に呼ばれたとき読み直す
    private var photosLoaded = false

    /// 索引・別名・公開の写真を読む（どれも控えを使う口）。一度読めたら読み直さない
    func load(environment: AppEnvironment) async {
        // 一度読めたら読み直さない。読めなかった回は、呼ばれるたびに読み直す（電波が戻ったとき・長押ししたとき）
        guard !(loaded && photosLoaded), !loading else { return }
        loading = true
        defer { loading = false }
        var fetchedIndex: [OfficialSpot]?
        var fetchedAliases = aliases
        if !loaded {
            fetchedIndex = try? await environment.spots.fetchIndex()
            fetchedAliases = await environment.spots.fetchAliases()
        }
        var fetchedPhotos: [Photo]?
        if !photosLoaded { fetchedPhotos = try? await environment.gallery.fetchPhotos() }
        apply(index: fetchedIndex, aliases: fetchedAliases, photos: fetchedPhotos)
    }

    /// 読んだ結果を映す。**読めなかった分は前の表を残す**（空の表で上書きしない・2026-11-12 確かめ役の指摘）
    func apply(index fetchedIndex: [OfficialSpot]?, aliases fetchedAliases: [String: [String]], photos fetchedPhotos: [Photo]?) {
        if let fetchedIndex {
            index = fetchedIndex
            aliases = fetchedAliases
            names = DMTripPlaces.NameTable(fetchedIndex, aliases: fetchedAliases)
            loaded = true
        }
        if let fetchedPhotos {
            photosById = DMTripPlaces.byId(fetchedPhotos)
            photosLoaded = true
        }
        failed = !loaded
    }

    /// 下書きに出す場所（写真が先・吹き出しから入れた場所が後）
    func places(_ messages: [DMMessage], blocked: Set<String>) -> [DMTripPlaces.Found] {
        DMTripPlaces.merged(photos: DMTripPlaces.photoPlaces(messages, names: names, photosById: photosById, blocked: blocked),
                            added: added)
    }

    /// 文から拾った撮影スポット（拾えなければ空）
    func spots(in text: String) -> [OfficialSpot] {
        DMTripPlaces.spotsInText(text, index: index, aliases: aliases)
    }

    func candidates(for text: String) -> [OfficialSpot] {
        DMTripPlaces.candidates(for: text, index: index, aliases: aliases)
    }

    func add(_ spots: [OfficialSpot], source: DMTripPlaces.Source) {
        for spot in spots {
            let found = DMTripPlaces.Found(place: TripDraft.place(spot: spot), source: source)
            if !added.contains(where: { $0.id == found.id }) { added.append(found) }
        }
    }
}

/// 吹き出しの文から候補を選ぶシートを開く印
struct DMTripCandidateTarget: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

// MARK: - 帯

/// 会話の上の帯「この会話から旅行プランを作る　2 か所 ›」（案内の帯: 真鍮 8% の地・真鍮の縁と字）
struct DMTripBand: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: JPSpace.xs) {
                Image(systemName: "map")
                    .font(JPFont.footnote)
                    .accessibilityHidden(true)
                Text(DMTripPlaces.bandTitle)
                    .font(JPFont.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: JPSpace.xs)
                Text(DMTripPlaces.countLabel(count))
                    .font(JPFont.caption.monospacedDigit())
                Image(systemName: "chevron.right")
                    .font(JPFont.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.accent, lineWidth: JPStroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, JPSpace.gutter)
        .padding(.vertical, JPSpace.xxs)
        .accessibilityLabel("\(DMTripPlaces.bandTitle)\u{2002}\(DMTripPlaces.countLabel(count))")
        .accessibilityHint(L("会話に出た場所で旅行プランの下書きを開きます", "Opens a trip draft with the places from this chat"))
        .accessibilityIdentifier("dm.tripBand")
    }
}

// MARK: - 下書き → 日付 → 作る

/// 全画面の板。①下書き（会話に出た場所・押すと外す）→ ②日付（`TripCreateDatesStep`・この段で保存）
struct DMTripCreateView: View {

    let peerName: String
    let found: [DMTripPlaces.Found]
    @ObservedObject var plans: TripPlansModel
    let onSaved: (String) -> Void

    @StateObject private var model: TripCreateModel
    @State private var showDates = false
    @EnvironmentObject private var environment: AppEnvironment

    init(peerName: String, found: [DMTripPlaces.Found], plans: TripPlansModel, onSaved: @escaping (String) -> Void) {
        self.peerName = peerName
        self.found = found
        self.plans = plans
        self.onSaved = onSaved
        _model = StateObject(wrappedValue: TripCreateModel(initial: found.map(\.place)))
    }

    var body: some View {
        NavigationStack {
            DMTripDraftStep(peerName: peerName, found: found, model: model, next: { showDates = true })
                .navigationDestination(isPresented: $showDates) {
                    TripCreateDatesStep(model: model, next: save, finishTitle: L("旅行プランを作る", "Create trip"))
                }
        }
        .sheetSwipeGuard(.busy(model.saving))
        .overlay(alignment: .bottom) {
            ToastOverlay().padding(.bottom, 84)
        }
    }

    private func save() {
        Task {
            if let made = await model.save(plans: plans, environment: environment) { onSaved(made) }
        }
    }
}

/// ① 下書き（模型「旅行プランの下書き」: 眉ラベル「[名前] との会話から」・題・案内の1行・場所の行・「2 か所で 日付を選ぶ」）
struct DMTripDraftStep: View {

    let peerName: String
    let found: [DMTripPlaces.Found]
    @ObservedObject var model: TripCreateModel
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    Text(L("\(peerName) との会話から", "From your chat with \(peerName)"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                    // 題（行き先から案を出す・直せる。作る流れの下書きの段と同じ）
                    JPTextField(model.suggestedTitle, text: $model.title)
                        .font(JPFont.screenTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .submitLabel(.done)
                        .onChange(of: model.title) { old, new in
                            let kept = PostLimits.limited(old: old, new: new, limit: TripPlanService.titleMax)
                            if kept != new { model.title = kept }
                        }
                        .accessibilityLabel(L("旅行プランのタイトル", "Trip title"))
                        .accessibilityIdentifier("dmTrip.title")
                    Text(L("会話に出た場所です。外したい所は押して外せます", "Places from this chat. Tap one to leave it out."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(found) { item in
                        TripChoiceRow(place: item.place, isOn: model.isSelected(item.id), locked: false,
                                      detail: item.detail) {
                            model.toggle(item.place)
                        }
                    }
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .navigationTitle(L("旅行プランの下書き", "Trip draft"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 閉じるは左上（2026-11-13 owner 承認・#187・旅行プランを作る流れと同じ位置・画面ごとに割らない）
            ToolbarItem(placement: .cancellationAction) {
                SheetCloseButton().disabled(model.saving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: next) {
                Text(DMTripPlaces.nextTitle(count: model.count))
                    .jpPillButton(.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .disabled(model.count == 0)
            .opacity(model.count == 0 ? TripStyle.disabledOpacity : 1)
            .accessibilityIdentifier("dmTrip.next")
            .jpBottomBar()
        }
    }
}

// MARK: - 段②: 候補から選ぶ

/// 吹き出しの文から撮影スポットを拾えなかったときの候補（撮影地の欄の候補 `PlaceSpotSuggestions` と同じ形: 3件・
/// 打った語で探し直せる）。選ぶと下書きに入る
struct DMTripCandidatesSheet: View {

    let text: String
    @ObservedObject var trip: DMTripModel
    /// 近くを先に出す基準（下書きの最初の座標）
    let near: Photo.Coords?
    let onPick: (OfficialSpot) -> Void

    @State private var query = ""
    /// 文からの候補。**開いたとき（索引が読めたとき）に1回だけ作る**（索引の全部と文を比べるので重い・2026-11-12）
    @State private var suggested: [OfficialSpot] = []

    private func rows(_ typed: String) -> [OfficialSpot] {
        if typed.isEmpty { return suggested }
        return PlaceSpotSuggestions.suggestions(query: typed, near: near, index: trip.index, aliases: trip.aliases)
    }

    var body: some View {
        // 描き直し1回で1度だけ並べる
        let shown = rows(typedQuery)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JPSpace.m) {
                    Text("「\(text)」")
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .lineLimit(3)
                    Text(L("文の中の観光スポットが分かりませんでした。候補から選ぶか、名前で探してください",
                           "We couldn't find a photo spot in this message. Pick one below or search by name."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    JPTextField(L("観光スポットの名前", "Photo spot name"), text: $query)
                        .font(JPFont.body)
                        .submitLabel(.search)
                        .jpFieldBox()
                        .accessibilityIdentifier("dmTrip.search")
                    if trip.failed {
                        ErrorBanner(message: L("観光スポットの一覧を読み込めませんでした。通信を確かめて、開き直してください",
                                               "Couldn't load photo spots. Check your connection and try again."))
                    } else if !trip.loaded {
                        JPLoadingState(kind: .rows)
                    } else if shown.isEmpty {
                        Text(L("候補はありません。名前で探してください", "No suggestions. Try searching by name."))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text3)
                            .accessibilityIdentifier("dmTrip.noCandidates")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(shown) { spot in
                                TripChoiceRow(place: TripDraft.place(spot: spot), isOn: false, locked: false) {
                                    onPick(spot)
                                }
                                .accessibilityIdentifier("dmTrip.candidate")
                            }
                        }
                    }
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.top, JPSpace.xs)
                .padding(.bottom, JPSpace.xl)
            }
            .webScreen()
            .navigationTitle(L("旅行プランに入れる", "Add to a trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
            }
            .task(id: trip.loaded) {
                if trip.loaded { suggested = trip.candidates(for: text) }
            }
        }
    }

    private var typedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
}
