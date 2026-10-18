import SwiftUI
import Photos

/// マイページの「旅の記録」の、**端末の写真の一冊**の段（2026-10-16 owner 決定・決まりは `DeviceTrips`）。
///
/// - まだ許可を尋ねていなければ、説明の札（何に使うか・端末の中だけ・どこにも送らない）と許可の主ボタン
/// - 許されていれば、見つかった旅を「端末の中だけ」の印つきの行で並べる（見つかった順に増える）
/// - 断られていれば何も出さない（今までどおり投稿した写真の一冊だけ）
///
/// **本人のマイページだけに置く**（人のプロフィールには置かない・`DeviceTrips.books(isMine:)`）。
/// 黒地の上なので、眉ラベルと文字のリンクは真鍮、主ボタンは真鍮の塗りに墨（写真の無い札・CLAUDE.md）
struct DeviceTripSection: View {

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: DeviceTripShelfStore
    /// 自分の投稿（投稿済みの日がある旅を外す・`LibraryTrips.postedDays`）
    let posted: [LibraryTrips.PostedShot]

    var body: some View {
        let books = store.books(posted: posted, isMine: true)
        Group {
            if PhotoLibrary.canRead(store.status) {
                shelf(books)
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

    private func shelf(_ books: [LibraryTrip]) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            HStack(spacing: JPSpace.xs) {
                Text(L("端末の中だけ", "On this iPhone only"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if store.isScanning {
                    ProgressView().tint(WebTheme.text3).controlSize(.small)
                    Text(L("写真から旅を探しています", "Looking for trips in your photos"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            Text(L("端末の写真の撮影日時と場所から見つけた旅です。どこにも送らず、ほかの人には見えません。投稿は任意です",
                   "Trips found from when and where your photos were taken. Nothing is uploaded and no one else can see them. Posting is up to you."))
                .font(JPFont.caption)
                .lineSpacing(3)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if store.status == .limited { limitedBar }
            if books.isEmpty {
                if store.hasCompleted && !store.isScanning {
                    Text(L("家から50km以上離れた場所で撮った写真のまとまりは、まだ見つかっていません",
                           "No groups of photos taken 50 km or more from home yet."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, JPSpace.xxs)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(books) { trip in
                        NavigationLink {
                            DeviceTripBookView(trip: trip, name: store.names[trip.id])
                        } label: {
                            DeviceTripRow(trip: trip, name: store.names[trip.id])
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trips.deviceBook")
                    }
                }
            }
        }
        .padding(.horizontal, JPSpace.gutter)
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

/// 「端末の中だけ」の線の札（黒地の上: text-2 の字に白 14% の線・`UploadDateChip` と同じ形）。
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

/// 端末の一冊の行（投稿した一冊の行 `TripShelfRow` と同じ寸法: 高さ 72・左に 72×56 の写真）。
/// 表紙は**画面に出たときに小さく読む**（`LibraryThumbView`）
struct DeviceTripRow: View {

    let trip: LibraryTrip
    let name: String?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let cover = trip.cover {
                    LibraryThumbView(id: cover.id, side: TripStyle.rowThumb.width)
                } else {
                    WebTheme.card
                }
            }
            .frame(width: TripStyle.rowThumb.width, height: TripStyle.rowThumb.height)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(DeviceTrips.title(of: trip, name: name))
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                Text(DeviceTripText.line(trip, name: name))
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(WebTheme.minimumScale(forTextSize: JPTypeScale.meta))
                DeviceOnlyChip()
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, JPSpace.xs)
        .frame(minHeight: TripStyle.rowMinHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 端末の一冊の字
enum DeviceTripText {
    /// 行の等幅の1行。地名が題なら「期間 · 日数・枚数」、期間が題なら「日数・枚数」
    static func line(_ trip: LibraryTrip, name: String?) -> String {
        let count = LibraryTrips.countText(trip)
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return count }
        return LibraryTrips.periodText(trip) + " · " + count
    }
}

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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                ForEach(trip.days) { day in
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
                }
            }
            .padding(.vertical, JPSpace.m)
        }
        .webScreen()
        .navigationTitle(DeviceTrips.title(of: trip, name: name))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                TabRouter.shared.openTripImport(trip)
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
            Text(DeviceTrips.title(of: trip, name: name))
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // 題が期間でも、開いた画面では期間と枚数をそろえて出す
            Text(LibraryTrips.periodText(trip) + " · " + LibraryTrips.countText(trip))
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
