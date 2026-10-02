import SwiftUI
import Photos

/// 写真ライブラリから見つかった旅の一覧。
///
/// 1行に、表紙・地名（明朝 18）・期間（等幅）・日数と枚数。**投稿済みの日がある旅は
/// 下に分けて、表紙を薄く出す**——もう残した旅をまた上げる手間を減らす（消しはしない。
/// 1日だけ上げた旅の残りを出したい人もいる）
struct LibraryTripListView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject var model: LibraryTripModel
    /// 選んだ写真を整えたものを渡す（投稿画面へ）
    let onDone: ([ImagePreparer.Prepared]) -> Void

    private var fresh: [LibraryTrip] {
        model.trips.filter { LibraryTrips.postedDays(trip: $0, postedDayKeys: model.postedDayKeys) == 0 }
    }

    private var posted: [LibraryTrip] {
        model.trips.filter { LibraryTrips.postedDays(trip: $0, postedDayKeys: model.postedDayKeys) > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.status == .limited { limitedBar }
            content
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

    /// 一部だけ許可しているときの1行。**iOS の起動ごとの案内は止めている**
    /// （`PHPhotoLibraryPreventAutomaticLimitedAccessAlert`）ので、選び足す口はここ
    private var limitedBar: some View {
        HStack(spacing: 8) {
            Text(L("一部の写真だけを許可しています", "You've allowed only some photos"))
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task {
                    await model.addMorePhotos()
                    await model.resolveNames(model.trips.map(\.center))
                }
            } label: {
                // 黒地の上の文字リンクなので真鍮（owner 2026-10-02）
                Text(L("写真を追加で選ぶ", "Select more photos"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading || model.isPickingMore)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var content: some View {
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
                    // 薄くするのは表紙だけ（行ごと薄くすると 12pt の注記が読めない）
                    ForEach(posted) { trip in row(trip) }
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
                .opacity(postedDays > 0 ? 0.45 : 1)
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
