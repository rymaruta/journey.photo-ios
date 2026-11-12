import SwiftUI
import Photos

/// 写真ライブラリから見つかった旅の一覧。
///
/// 2026-11-12 判断（1.1.83・案「投稿まわりのデザイン」04）: 旅の記録と同じ**写真の札**（高さ 120・先頭は 150・角 14・
/// 下から黒の溶けに明朝 18 の白の題・等幅の期間・日数と枚数）。**投稿済みの日がある旅は下に分け**、札の左上に
/// 白のガラスの札「投稿済み n日」。薄くしない（写真の上の白は読める）——もう残した旅をまた上げる手間を減らす
/// （消しはしない。1日だけ上げた旅の残りを出したい人もいる）
struct LibraryTripListView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject var model: LibraryTripModel
    /// 開いたらすぐ選ぶ画面へ進む旅（端末の写真の一冊から・2026-10-16）
    var opening: LibraryTrip? = nil
    /// 選んだ写真を整えたものを渡す（投稿画面へ）
    let onDone: ([ImagePreparer.Prepared]) -> Void
    /// 旅が見つからなかったときの「1枚ずつ投稿する」（この流れを閉じて、ふつうの投稿の画面へ・2026-11-12）
    var onPostSingly: (() -> Void)? = nil
    /// `opening` に当たる旅（見つかったら一度だけ押し込む）
    @State private var autoOpen: LibraryTrip?
    @State private var didAutoOpen = false

    private var fresh: [LibraryTrip] {
        model.trips.filter { LibraryTrips.postedDays(trip: $0, posted: model.posted) == 0 }
    }

    private var posted: [LibraryTrip] {
        model.trips.filter { LibraryTrips.postedDays(trip: $0, posted: model.posted) > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.status == .limited { limitedBar }
            content
        }
        .webScreen()
        // 題は入口（投稿のシートの行）と同じ言葉（2026-11-12 判断）
        .navigationTitle(L("旅の写真からまとめて", "From a trip in your photos"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 端末の一冊が引いた地名・時間帯を、探し直す前に写す（同じ場所を地図にもう一度聞かない）
            if let opening {
                model.adoptDevicePlace(of: opening, names: DeviceTripShelfStore.shared.names,
                                       zones: DeviceTripShelfStore.shared.zones)
            }
            // 投稿済みの日は自分の投稿から。ログインしていない・取れないときは無しで出す
            let signedIn = auth.userId != nil
            let photos = environment.photos
            await model.load {
                guard signedIn else { return [] }
                return (try? await photos.myPhotos()) ?? []
            }
            // 端末の一冊から来たら、その旅の選ぶ画面へ（一度だけ・見つからなければ一覧のまま）
            if let opening, !didAutoOpen {
                didAutoOpen = true
                autoOpen = DeviceTrips.matching(opening, in: model.trips)
            }
            // 旅の名前は新しい旅から順に（画面の上から埋まる）
            await model.resolveNames(model.trips.map(\.center))
        }
        .navigationDestination(item: $autoOpen) { trip in
            LibraryTripPickView(trip: trip, title: model.name(for: trip.center) ?? LibraryTrips.periodText(trip),
                                model: model, onDone: onDone)
        }
    }

    /// 一部だけ許可しているときの帯。**iOS の起動ごとの案内は止めている**
    /// （`PHPhotoLibraryPreventAutomaticLimitedAccessAlert`）ので、選び足す口はここ。
    /// 2026-11-12 判断: 写真の札と分けるため、案内の帯（真鍮 8% の地に真鍮の字・黒地の上）にした
    private var limitedBar: some View {
        HStack(spacing: JPSpace.xs) {
            Image(systemName: "info.circle")
                .font(JPFont.footnote)
                .accessibilityHidden(true)
            Text(L("一部の写真だけを許可しています", "You've allowed only some photos"))
                .font(JPFont.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { addMore() } label: {
                // 黒地の上の文字リンクなので真鍮（owner 2026-10-02）
                Text(L("追加で選ぶ", "Select more"))
                    .font(JPFont.footnote.weight(.semibold))
                    .webTappable()
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading || model.isPickingMore)
            .accessibilityLabel(L("写真を追加で選ぶ", "Select more photos"))
        }
        .foregroundStyle(WebTheme.accent)
        .padding(.horizontal, JPSpace.s)
        .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .padding(.horizontal, JPSpace.m)
        .padding(.bottom, JPSpace.xs)
    }

    private func addMore() {
        Task {
            await model.addMorePhotos()
            await model.resolveNames(model.trips.map(\.center))
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if model.isLoading || !model.loaded {
                searching
            } else if model.trips.isEmpty {
                notFound
            } else {
                list
            }
        }
    }

    /// 探している間（骨格の札・surface-4。回る印を出さない・2026-11-12）
    private var searching: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("写真から旅を探しています（端末の中だけで読みます）",
                   "Looking for trips in your photos (read on this device only)"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, JPSpace.xxs)
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: LibraryTripCard.radius)
                    .fill(WebTheme.surface4)
                    .frame(height: LibraryTripCard.height)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.m)
        .padding(.top, JPSpace.xxs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 見つからなかった（2026-11-12 判断）。何を探したかを言い、次の一手を2つ（一部だけ許可なら選び足す・
    /// 1枚ずつ投稿する）。全部を許可している人には「写真を追加で選ぶ」は出さない（選び足す画面が無い）
    private var notFound: some View {
        VStack(spacing: JPSpace.s) {
            Text(L("旅が見つかりませんでした", "No trips found"))
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(L("家から50km以上離れた所で、同じころに撮った写真のまとまりを探しています。",
                   "We look for groups of photos taken around the same time, 50 km or more from home."))
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if model.status == .limited {
                Button { addMore() } label: {
                    Text(L("写真を追加で選ぶ", "Select more photos")).jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 260)
                .disabled(model.isLoading || model.isPickingMore)
                .padding(.top, JPSpace.xs)
            }
            if let onPostSingly {
                Button(action: onPostSingly) {
                    Text(L("1枚ずつ投稿する", "Post photos one by one"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .padding(.horizontal, JPSpace.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("libraryTrips.postSingly")
            }
        }
        .padding(.horizontal, JPSpace.section)
        .padding(.top, JPSpace.emptyTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(fresh.enumerated()), id: \.element.id) { index, trip in
                    row(trip, lead: index == 0)
                }
                if !posted.isEmpty {
                    JPEyebrowLine(L("投稿済みの日がある旅", "Trips with days already posted"))
                        .padding(.top, JPSpace.s)
                    ForEach(posted) { trip in row(trip, lead: false) }
                }
            }
            .padding(.horizontal, JPSpace.m)
            .padding(.bottom, JPSpace.m)
        }
    }

    private func row(_ trip: LibraryTrip, lead: Bool) -> some View {
        let name = model.name(for: trip.center)
        let period = LibraryTrips.periodText(trip)
        let postedDays = LibraryTrips.postedDays(trip: trip, posted: model.posted)
        return NavigationLink {
            LibraryTripPickView(trip: trip, title: name ?? period, model: model, onDone: onDone)
        } label: {
            LibraryTripCard(trip: trip, title: DeviceTrips.title(of: trip, name: name),
                            period: name == nil ? nil : period, postedDays: postedDays, lead: lead)
        }
        .buttonStyle(.plain)
    }
}

/// 見つかった旅の写真の札（2026-11-12 判断・案「投稿まわりのデザイン」04。旅の記録の表紙の札 `TripShelf` と同じ形）。
///
/// 高さ 120（先頭の1枚は 150）・角 14、下から黒 82% の溶けに明朝 18 の白の題、等幅 12 の期間、右に日数と枚数。
/// 写真の上なので字は白だけ（真鍮を置かない）。投稿済みの日がある旅は左上に白のガラスの札「投稿済み n日」
struct LibraryTripCard: View {

    let trip: LibraryTrip
    let title: String
    /// 題が地名のときの期間（地名が引けず期間が題のときは nil）
    let period: String?
    let postedDays: Int
    /// 一覧の先頭（少し高く）
    let lead: Bool

    nonisolated static let height: CGFloat = 120
    nonisolated static let leadHeight: CGFloat = 150
    nonisolated static let radius: CGFloat = JPRadius.m
    /// 下の溶けの濃さ（案の `rgba(0,0,0,.82)`）
    nonisolated static let shade = 0.82

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let cover = trip.cover {
                    LibraryThumbView(id: cover.id, side: 400)
                } else {
                    WebTheme.surface4
                }
            }
            .frame(height: lead ? Self.leadHeight : Self.height)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
            LinearGradient(colors: [Color.black.opacity(Self.shade), Color.black.opacity(0)],
                           startPoint: .bottom, endPoint: .top)
                .frame(height: 96)
                .accessibilityHidden(true)
            HStack(alignment: .lastTextBaseline, spacing: JPSpace.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                    if let period {
                        Text(period)
                            .font(JPFont.mono(12))
                            .foregroundStyle(WebTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(LibraryTrips.countText(trip))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, JPSpace.m)
            .padding(.bottom, JPSpace.s)
        }
        .overlay(alignment: .topLeading) {
            if postedDays > 0 {
                Text(L("投稿済み \(postedDays)日", "Posted on \(postedDays) day(s)"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: JPStroke.hairline))
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius))
        .accessibilityElement(children: .combine)
    }
}
