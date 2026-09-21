import SwiftUI

/// 旅の一冊。
///
/// **表紙 → ページ → 足取り**の順に、下へ流れる1本の読み物にする。
/// 写真を「並べる」のではなく「読ませる」——ここが一覧との違い。
struct TripBookView: View {

    let trip: TripBook.Trip

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                cover
                pages
                footer
            }
        }
        .webScreen()
        .navigationTitle(trip.place.isEmpty ? L("旅の記録", "A trip") : trip.place)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 表紙

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = trip.cover {
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: cover.detailImageURL, alignment: cover.gridAlignment)
                    }
                    .clipped()
            }
            // **下だけ暗くする。** 全面に膜を掛けると写真が濁る
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.85)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(period)
                    .font(.caption)
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(trip.place.isEmpty ? L("旅の記録", "A trip") : trip.place)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(WebTheme.foreground)
                Text(L("\(trip.days)日間 · \(trip.photos.count)枚",
                       "\(trip.days) days · \(trip.photos.count) photos"))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(20)
        }
    }

    // MARK: - ページ

    /// **時間順に、1枚ずつ大きく。** 一覧の格子と同じ見せ方にすると、
    /// 「一冊」にならない
    private var pages: some View {
        VStack(spacing: 28) {
            ForEach(Array(trip.photos.enumerated()), id: \.element.id) { index, photo in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink {
                        PhotoDetailView(photo: photo, context: trip.photos)
                    } label: {
                        RemoteImage(url: photo.detailImageURL, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    if !photo.displayTitle.isEmpty {
                        Text(photo.displayTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WebTheme.foreground)
                    }
                    if let first = photo.paragraphs.first {
                        Text(first)
                            .font(.callout)
                            .lineSpacing(4)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    HStack(spacing: 8) {
                        // 何日目かを出す。**旅の進み方が分かる**
                        Text(L("\(dayNumber(of: photo))日目", "Day \(dayNumber(of: photo))"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                        if let place = photo.location, !place.isEmpty {
                            Text("·").foregroundStyle(WebTheme.faint)
                            Text(place)
                                .font(.caption)
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                    // その日に聴いていた曲（付けてあれば）
                    if let song = photo.song {
                        SongRow(song: song)
                    }
                }
                .padding(.horizontal, 16)
                // **表紙とページの間は広く取る。** 詰まっていると、
                // 表紙が「1枚目の写真」に見えてページが始まらない
                .padding(.top, index == 0 ? 44 : 0)
            }
        }
    }

    // MARK: - 足取り

    @ViewBuilder
    private var footer: some View {
        let places = orderedPlaces
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("たどった場所", "Where you went"))
                    .font(.headline)
                    .foregroundStyle(WebTheme.foreground)
                // **線でつなぐ。** 点を並べるだけだと「足取り」に見えない
                ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(WebTheme.foreground)
                                .frame(width: 8, height: 8)
                            if index < places.count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 1, height: 26)
                            }
                        }
                        Text(place)
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.muted)
                        Spacer()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .padding(16)
            .padding(.top, 20)
        }
    }

    // MARK: - 計算

    private var period: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.preferredAppLanguage == "en" ? "en_US" : "ja_JP")
        formatter.dateFormat = Locale.preferredAppLanguage == "en" ? "MMM d, yyyy" : "yyyy年M月d日"
        return formatter.string(from: trip.start)
    }

    /// 旅の何日目か（1から数える）
    private func dayNumber(of photo: Photo) -> Int {
        guard let date = TripBook.day(of: photo) else { return 1 }
        return max(1, Int(date.timeIntervalSince(trip.start) / 86_400) + 1)
    }

    /// 足取り。規則は `TripBook.route` にある（画面を持たない層に置いて、
    /// Linux 上の `swift test` で検証できるようにしてある）。
    private var orderedPlaces: [String] { TripBook.route(of: trip.photos) }
}
