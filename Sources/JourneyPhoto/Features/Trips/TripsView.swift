import SwiftUI

/// 旅の本棚。
///
/// **開くと「まとまった旅」が並んでいる。** 投稿するたびに勝手に増え、
/// 何も指定しなくても一冊になる（`TripBook`）。一覧（格子）との違いは、
/// **写真ではなく旅が単位**であること。
struct TripsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore

    @State private var trips: [TripBook.Trip] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(40)
            } else if let errorMessage {
                ErrorBanner(message: errorMessage) { Task { await load() } }
            } else if trips.isEmpty {
                empty
            } else {
                LazyVStack(spacing: 20) {
                    ForEach(trips) { trip in
                        NavigationLink {
                            TripBookView(trip: trip)
                        } label: {
                            shelf(trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .webScreen()
        .navigationTitle(L("旅", "Trips"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    /// 背表紙にあたる1枚。表紙の写真の上に、題と日数を置く
    private func shelf(_ trip: TripBook.Trip) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = trip.cover {
                Color.clear
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: cover.gridImageURL, alignment: cover.gridAlignment)
                    }
                    .clipped()
            }
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.8)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.place.isEmpty ? L("旅の記録", "A trip") : trip.place)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WebTheme.foreground)
                Text(L("\(trip.days)日間 · \(trip.photos.count)枚",
                       "\(trip.days) days · \(trip.photos.count) photos"))
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(WebTheme.faint)
            Text(L("まだ旅がありません", "No trips yet"))
                .font(.headline)
                .foregroundStyle(WebTheme.muted)
            // **なぜ空なのかを言う。** 「写真はあるのに旅が無い」ときに
            // 黙っていると、壊れているようにしか見えない
            Text(L("同じころに撮った写真が2枚たまると、ひとつの旅にまとまります",
                   "Two or more photos taken around the same time become a trip"))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func load(force: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let photos = try await environment.gallery.fetchPhotos(force: force)
            trips = TripBook.trips(from: photos)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }
}
