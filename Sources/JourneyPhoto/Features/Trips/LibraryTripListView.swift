import SwiftUI

/// 写真ライブラリから見つかった旅の一覧。
///
/// 1行に、表紙・地名（明朝 18）・期間（等幅）・日数と枚数。**投稿済みの日がある旅は
/// 下に分けて薄く出す**——もう残した旅をまた上げる手間を減らす（消しはしない。
/// 1日だけ上げた旅の残りを出したい人もいる）
struct LibraryTripListView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject var model: LibraryTripModel
    /// 選んだ写真の本体を渡す（投稿画面へ）
    let onDone: ([Data]) -> Void

    private var fresh: [LibraryTrip] {
        model.trips.filter { LibraryTrips.postedDays(trip: $0, postedDayKeys: model.postedDayKeys) == 0 }
    }

    private var posted: [LibraryTrip] {
        model.trips.filter { LibraryTrips.postedDays(trip: $0, postedDayKeys: model.postedDayKeys) > 0 }
    }

    var body: some View {
        Group {
            if model.isLoading || !model.loaded {
                VStack(spacing: 12) {
                    ProgressView().tint(WebTheme.foreground)
                    Text(L("写真から旅を探しています", "Looking for trips in your photos"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.trips.isEmpty {
                Text(L("家から50km以上離れた場所で撮った写真のまとまりが見つかりませんでした",
                       "No groups of photos taken 50 km or more from home were found."))
                    .font(.callout)
                    .foregroundStyle(WebTheme.muted2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .webScreen()
        .navigationTitle(L("旅の写真から", "From your trips"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 投稿済みの日は自分の投稿から。ログインしていない・取れないときは無しで出す
            let signedIn = auth.userId != nil
            let photos = environment.photos
            await model.load {
                guard signedIn else { return [] }
                return (try? await photos.myPhotos()) ?? []
            }
            // 旅の名前は新しい旅から順に（画面の上から埋まる）
            await model.resolveNames(model.trips.map(\.center))
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(fresh) { trip in row(trip) }
                if !posted.isEmpty {
                    Text(L("投稿済みの日がある旅", "Trips with days already posted"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .padding(.top, 20)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(posted) { trip in
                        row(trip).opacity(0.55)
                    }
                }
            }
            .padding(16)
        }
    }

    private func row(_ trip: LibraryTrip) -> some View {
        let name = model.name(for: trip.center)
        let period = LibraryTrips.periodText(trip)
        let postedDays = LibraryTrips.postedDays(trip: trip, postedDayKeys: model.postedDayKeys)
        return NavigationLink {
            LibraryTripPickView(trip: trip, title: name ?? period, model: model, onDone: onDone)
        } label: {
            HStack(spacing: 14) {
                Group {
                    if let cover = trip.cover {
                        LibraryThumbView(id: cover.id, side: 64)
                    } else {
                        WebTheme.surface
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    // 地名が引けなければ期間だけを題にする
                    Text(name ?? period)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    if name != nil {
                        Text(period)
                            .font(JPFont.mono(12))
                            .foregroundStyle(WebTheme.muted2)
                    }
                    Text(L("\(trip.days.count)日・\(trip.shots.count)枚",
                           "\(trip.days.count) days · \(trip.shots.count) photos"))
                        .font(JPFont.mono(12))
                        .foregroundStyle(WebTheme.faint)
                    if postedDays > 0 {
                        Text(L("投稿済みの日があります（\(postedDays)日）",
                               "Already posted on \(postedDays) day(s)"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
