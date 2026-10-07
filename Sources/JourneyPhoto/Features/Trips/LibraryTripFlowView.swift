import SwiftUI
import UIKit
import Photos

/// 「旅の写真からまとめて」の流れ（投稿の選択の3つ目の行から全画面で開く）。
///
/// 写真へのアクセスの説明 → 見つかった旅の一覧 → 旅の写真を日ごとに選ぶ → 投稿画面。
/// **投稿画面はこの流れが閉じきってから呼び手（`RootView`）が開く**——ふだんの投稿と
/// 同じシートで開けば、閉じたあとのマイページの読み直し（`postSheetClosed`）や
/// 書きかけの確認がそのまま効く。
struct LibraryTripFlowView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = LibraryTripModel()

    /// 選んだ写真を整えたもの（読めたぶん・旅の並び）。渡してから閉じる
    let onDone: ([ImagePreparer.Prepared]) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if PhotoLibrary.canRead(model.status) {
                    LibraryTripListView(model: model) { photos in
                        // **渡してから閉じる。** 呼び手は「流れが開いている間だけ受ける」
                        // （`TripImportHandoff.received`）。投稿画面は閉じきってから呼び手が開く
                        onDone(photos)
                        dismiss()
                    }
                } else {
                    LibraryTripIntroView(status: model.status,
                                         onAllow: { Task { await model.requestAccess() } },
                                         onLater: { dismiss() })
                }
            }
            // 設定アプリで許可して戻ってきたら見直す
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.refreshStatus() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(WebTheme.foreground)
                            .webTappable()
                    }
                    .accessibilityLabel(Labels.Common.close)
                }
            }
        }
    }
}

/// 流れ全体で持つもの（許可・見つけた旅・投稿済みの日・引いた地名）
@MainActor
final class LibraryTripModel: ObservableObject {

    @Published private(set) var status: PHAuthorizationStatus = PhotoLibrary.status
    @Published private(set) var trips: [LibraryTrip] = []
    /// 読んでいる最中（輪を出す）
    @Published private(set) var isLoading = false
    /// 一度読み終えた（0件の言葉を出してよい）
    @Published private(set) var loaded = false
    /// 自分の投稿の撮影日（`YYYY-MM-DD`）と撮影地（`LibraryTrips.postedDays` の突き合わせ）
    @Published private(set) var posted: [LibraryTrips.PostedShot] = []
    /// 引いた地名。鍵は `LibraryTrips.lookupKey`。**流れをまたいで控える**（`knownNames`）
    @Published private(set) var names: [String: String] = [:]
    /// 選び足しの画面を出している（二度押しで画面が重ならないように）
    @Published private(set) var isPickingMore = false

    /// 引けた地名（流れをまたいで使う）
    private static var knownNames: [String: String] = [:]
    /// 地名と一緒に分かった土地の時間帯（鍵は `LibraryTrips.lookupKey`）。旅の日を
    /// 撮った土地の暦で切り直すのに使う（`LibraryTrips.applyingZones`）。流れをまたいで控える
    private static var knownZones: [String: TimeZone] = [:]
    /// 引けなかった座標と、その時刻。**`LibraryTrips.nameRetryAfter` の間は引き直さない**
    /// （断られた直後に開き直すたびに Apple の地図へ問い合わせない）。流れをまたいで控える
    private static var failedAt: [String: Date] = [:]

    /// 地名の控えを消す（サインアウト・退会。`AuthStore.settleSignedOut`）
    static func forgetPlaceNames() {
        knownNames = [:]
        knownZones = [:]
        failedAt = [:]
    }

    init() {
        names = Self.knownNames
    }

    func requestAccess() async {
        status = await PhotoLibrary.requestAccess()
    }

    /// 設定アプリから戻ったときに見直す
    func refreshStatus() {
        status = PhotoLibrary.status
    }

    /// ライブラリを読んで旅を探す。**一度だけ**（一覧へ戻るたびに読み直さない）
    func load(myPhotos: @escaping () async -> [Photo]) async {
        guard !loaded, !isLoading, PhotoLibrary.canRead(status) else { return }
        isLoading = true
        async let posted = myPhotos()
        trips = await Self.findTrips()
        self.posted = LibraryTrips.postedShots(of: await posted)
        isLoading = false
        loaded = true
    }

    /// 一部だけ許可した人が写真を選び足したあと、探し直す（投稿済みの日はそのまま）
    func addMorePhotos() async {
        // **印を立ててから出す**（二度押しで選び足しの画面が重なっていた）
        guard !isLoading, !isPickingMore else { return }
        isPickingMore = true
        let presented = await PhotoLibrary.presentLimitedPicker()
        isPickingMore = false
        // 出せなかったら何もしない（黙って探し直さない）
        guard presented else { return }
        isLoading = true
        trips = await Self.findTrips()
        isLoading = false
    }

    private static func findTrips() async -> [LibraryTrip] {
        let shots = await PhotoLibrary.shots()
        // 探すのも画面の処理の外で（数万枚を升に分ける）
        let found = await Task.detached(priority: .userInitiated) { LibraryTrips.find(shots) }.value
        // 前に引いて分かった土地の時間帯で日を切り直す（分からない旅は経度の目安のまま）
        return LibraryTrips.applyingZones(found, zones: knownZones)
    }

    /// 地名（無い・まだ引いていなければ nil）
    func name(for coords: Photo.Coords?) -> String? {
        guard let coords else { return nil }
        return names[LibraryTrips.lookupKey(coords)]
    }

    /// 地名を**1つずつ順に**引く（Apple の地名引きは短い間に何度も呼ぶと断られる）。
    /// 引けなかった座標は、時刻を控えて `LibraryTrips.nameRetryAfter` の間は引き直さない
    func resolveNames(_ points: [Photo.Coords?]) async {
        var tried: Set<String> = []
        for case let coords? in points {
            let key = LibraryTrips.lookupKey(coords)
            guard names[key] == nil, tried.insert(key).inserted,
                  LibraryTrips.shouldLookUpName(failedAt: Self.failedAt[key], now: Date()) else { continue }
            if Task.isCancelled { return }
            let place = await PhotoLibrary.place(near: coords)
            if let zone = place.timeZone {
                Self.knownZones[key] = zone
                // 撮った土地の時間帯が分かった: その旅の日を切り直す（2026-10-07 判断）。
                // **分かっている時間帯を全部渡す**——旅の代表点の時間帯が日の代表点より先
                trips = LibraryTrips.applyingZones(trips, zones: Self.knownZones)
            }
            if let name = place.name {
                names[key] = name
                Self.knownNames[key] = name
                Self.failedAt[key] = nil
            } else {
                Self.failedAt[key] = Date()
            }
        }
    }
}

/// 写真へのアクセスの説明（許可がまだ決まっていない・断られたとき）。
/// **写真の無い画面**なので主ボタンは真鍮の塗りに墨
struct LibraryTripIntroView: View {

    @Environment(\.openURL) private var openURL

    let status: PHAuthorizationStatus
    let onAllow: () -> Void
    let onLater: () -> Void

    private var refused: Bool { status == .denied || status == .restricted }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("撮りためた旅を、まとめて残す", "Keep the trips you've shot, all at once"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 18) {
                    point("iphone",
                          L("写真はどこにも送りません。旅を探すのは端末の中だけです",
                            "Your photos stay on this iPhone. Trips are found on the device."))
                    point("location",
                          L("地名を引くため、おおよその位置（約1km）だけを Apple の地図に渡します",
                            "Only a rough location (about 1 km) is sent to Apple Maps to look up place names."))
                    point("photo.on.rectangle",
                          L("一部の写真だけを許可しても使えます",
                            "It works even if you allow only some photos."))
                }
                if refused {
                    Text(L("写真へのアクセスが許可されていません。設定アプリで「写真」を許可してください。",
                           "Photo access is off. Allow Photos in the Settings app."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button {
                    if refused {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } else {
                        onAllow()
                    }
                } label: {
                    Text(refused ? L("設定を開く", "Open Settings") : L("写真へのアクセスを許可", "Allow photo access"))
                        .jpPillButton(.accent)
                }
                .buttonStyle(.plain)
                Button(action: onLater) {
                    Text(L("あとで", "Not now"))
                        .font(.callout)
                        .foregroundStyle(WebTheme.muted2)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .webScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                // 真鍮は眉ラベルとオンだけ（板）。印は白
                .foregroundStyle(WebTheme.foreground)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(WebTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
