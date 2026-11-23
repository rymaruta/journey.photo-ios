import SwiftUI
import Photos

/// マイページの「旅の記録」の、**端末の写真の一冊**の段（2026-10-16 owner 決定・決まりは `DeviceTrips`）。
///
/// - まだ許可を尋ねていなければ、説明の札（何に使うか・端末の中だけ・どこにも送らない）と許可の主ボタン
/// - 許されていれば、見つかった旅は**本棚に投稿した旅と一緒に並ぶ**（背に iPhone の印・`TripShelfList`）。
///   ここに出すのは、探している間の1行と、一部だけ許可しているときの「写真を追加で選ぶ」だけ
/// - 断られていれば何も出さない（今までどおり投稿した写真の一冊だけ）
///
/// 2026-11-23 owner 判断（札 #714）: 棚に説明の文を出さない。端末の旅のプライバシーの文は初めの許可の札
/// （`DeviceTripIntroCard`）に残し、「端末の中だけ」の眉、撮影日時と場所の説明、「家から50km」の文は外した。
///
/// **本人のマイページだけに置く**（人のプロフィールには置かない・`DeviceTrips.books(isMine:)`）。
/// 黒地の上なので文字のリンクは真鍮、主ボタンは真鍮の塗りに墨（写真の無い札・CLAUDE.md）
struct DeviceTripSection: View {

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: DeviceTripShelfStore

    var body: some View {
        Group {
            if PhotoLibrary.canRead(store.status) {
                status
            } else if store.status == .notDetermined && !store.introDismissed {
                DeviceTripIntroCard(onAllow: { Task { await store.requestAccess() } },
                                    onLater: { store.dismissIntro() })
            }
        }
        // 棚が出たら（まだなら）読み始める。設定アプリで許可して戻ってきたときも
        .onAppear { store.startIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.startIfNeeded() }
        }
    }

    @ViewBuilder
    private var status: some View {
        if store.isScanning || store.status == .limited {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                if store.isScanning {
                    HStack(spacing: JPSpace.xs) {
                        ProgressView().tint(WebTheme.text3).controlSize(.small)
                        Text(L("写真から旅を探しています", "Looking for trips in your photos"))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    }
                }
                if store.status == .limited { limitedBar }
            }
            .padding(.horizontal, JPSpace.gutter)
        }
    }

    /// 一部だけ許可しているときの1行（「旅の写真から」の一覧と同じ形）。黒地の文字リンクなので真鍮
    private var limitedBar: some View {
        HStack(spacing: JPSpace.xs) {
            Text(L("一部の写真だけを許可しています", "You've allowed only some photos"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await store.addMorePhotos() }
            } label: {
                Text(L("写真を追加で選ぶ", "Select more photos"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .disabled(store.isPickingMore)
        }
    }
}

/// 「端末の中だけ」の線の札（黒地の上: text-2 の字に白 14% の線）。開いた一冊の頭に出す。
/// **色だけで言わない**——印（iPhone）と字で、投稿した一冊と見分ける
struct DeviceOnlyChip: View {
    var body: some View {
        HStack(spacing: JPSpace.xxs) {
            Image(systemName: "iphone")
                .accessibilityHidden(true)
            Text(L("端末の中だけ", "On this iPhone only"))
        }
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.text2)
            .padding(.horizontal, JPSpace.xs)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: JPRadius.s)
                .strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
    }
}

/// 端末の一冊の字（説明の札の約束は下の extension）
enum DeviceTripText {}

/// 写真を許可する前の説明の札（**何に使うかを許可の前に言う**・2026-10-16）。
/// 写真の無い札なので主ボタンは真鍮の塗りに墨
struct DeviceTripIntroCard: View {

    let onAllow: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            Text(L("端末の写真から", "From your photos"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(L("撮りためた旅を、棚に並べる", "Line up the trips you've shot"))
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(L("写真の撮影日時と場所から、家から離れた旅を一冊ずつ見つけます。投稿しなくても、ここに並びます",
                   "We find each trip away from home from when and where your photos were taken. They appear here even if you don't post."))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: JPSpace.s) {
                point("iphone", DeviceTripText.introPrivacy)
                point("location", DeviceTripText.introPlaceNames)
                point("photo.on.rectangle", DeviceTripText.introLimited)
            }
            .padding(.top, JPSpace.xxs)
            // **自前の札のボタンは「続ける」**（2026-10-16 判断）。押すと iOS の許可のダイアログが出る。
            // 自前の札で「許可」と言うと、iOS の許可を先に押させる形に見える（Apple の手引きは
            // 確かめていないが、安全側に倒した）
            Button(action: onAllow) {
                Text(L("続ける", "Continue"))
                    .jpPillButton(.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, JPSpace.xxs)
            .accessibilityIdentifier("trips.deviceAllow")
            Button(action: onLater) {
                Text(L("今はしない", "Not now"))
                    .font(.callout)
                    .foregroundStyle(WebTheme.text2)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(JPSpace.m)
        .jpCardFace()
        .padding(.horizontal, JPSpace.gutter)
    }

    private func point(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension DeviceTripText {
    /// 説明の札の約束（**端末の中だけで読み、どこにも送らない**）
    static var introPrivacy: String { L("端末の中だけで読み、写真も位置もどこにも送りません。旅を探すのに読むのは撮影日時と場所だけです",
                                "Read on this iPhone only. Neither photos nor locations are uploaded. To find trips, only the date and place each photo was taken are read.") }
    static var introPlaceNames: String { L("旅の名前を引くため、一冊につき1回だけ、おおよその位置（約1km）を Apple の地図に渡します",
                                   "To name each trip, a rough location (about 1 km) is sent to Apple Maps once per trip.") }
    static var introLimited: String { L("一部の写真だけを許可しても使えます。ほかの人には見えません",
                                "Works even if you allow only some photos. No one else can see them.") }
}

/// 端末の一冊を開いた画面。日ごとの真鍮の眉ラベルと4列の格子（画面に出た升だけ小さく読む）。
///
/// **共有（この一冊を送る）は出さない**（`DeviceTrips.canShare`）。下の主ボタンで
/// 「旅の写真から」の流れへ進み、この旅の写真を選んで投稿できる（既存の流れ・写真のある画面なので白）
struct DeviceTripBookView: View {

    let trip: LibraryTrip
    let name: String?
    /// 開いたあとに地名・時間帯が分かっても、日の切り方を追う（`DeviceTrips.shown`）
    @ObservedObject private var store: DeviceTripShelfStore

    init(trip: LibraryTrip, name: String?, store: DeviceTripShelfStore = .shared) {
        self.trip = trip
        self.name = name
        _store = ObservedObject(wrappedValue: store)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
    /// 読む線を過ぎた日（めくる起点・`TripDayFlip`）
    @State private var passedDays: Set<String> = []

    /// いまの一冊（時間帯が分かっていれば、その土地の日）
    private var shown: LibraryTrip {
        DeviceTrips.shown(trip, trips: store.trips, zones: store.zones)
    }

    /// 棚が引いた地名。開いたときにまだ無ければ、あとから入ったものを使う
    private var shownName: String? {
        let resolved = store.names[trip.id]?.trimmingCharacters(in: .whitespaces) ?? ""
        return resolved.isEmpty ? name : resolved
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                ForEach(shown.days) { day in
                    VStack(alignment: .leading, spacing: JPSpace.xs) {
                        Text(LibraryTrips.dayLabel(day, place: nil))
                            .jpEyebrow()
                            .foregroundStyle(WebTheme.accent)
                            .padding(.horizontal, JPSpace.gutter)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(day.shots, id: \.id) { shot in
                                LibraryThumbView(id: shot.id, side: 96)
                                    .aspectRatio(1, contentMode: .fill)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .tripDayMark(id: day.id, passed: $passedDays)
                }
            }
            .padding(.vertical, JPSpace.m)
        }
        // 日のページを左右でめくる（札 #714・投稿した一冊と同じ `TripDayFlip`）。id は `ForEach` の日の id
        .modifier(TripDayFlip(dayIDs: shown.days.map(\.id), passed: passedDays))
        .webScreen()
        .navigationTitle(DeviceTrips.title(of: shown, name: shownName))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                TabRouter.shared.openTripImport(shown)
            } label: {
                Text(L("この旅の写真を投稿する", "Post photos from this trip"))
                    .jpPillButton(JPPillStyle.main(onPhoto: true))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, JPSpace.l)
            .padding(.bottom, JPSpace.xs)
            .accessibilityIdentifier("trips.devicePost")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            DeviceOnlyChip()
            Text(DeviceTrips.title(of: shown, name: shownName))
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // 題が期間でも、開いた画面では期間と枚数をそろえて出す
            Text(LibraryTrips.periodText(shown) + "\u{2002}" + LibraryTrips.countText(shown))
                .font(JPFont.meta)
                .foregroundStyle(WebTheme.text3)
            Text(L("端末の写真から見つけた旅です。投稿するまで、ほかの人には見えません",
                   "Found from the photos on this iPhone. No one else can see it until you post."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, JPSpace.gutter)
    }
}
