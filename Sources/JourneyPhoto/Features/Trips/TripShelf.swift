import SwiftUI

/// 背表紙にあたる1枚。表紙の写真の上に、題・期間と日数を置く（板 16）。
/// マイページの「旅の記録」のタブに並べる
struct TripShelf: View {

    let trip: TripBook.Trip

    var body: some View {
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
            // 左に題と期間、右下に「3日間 · 12枚」（板 16）
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(TripBook.title(of: trip))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(2)
                    Text(TripBook.dateRange(from: trip.start, to: trip.end))
                        .font(JPFont.mono(11, relativeTo: .caption2))
                        .foregroundStyle(WebTheme.muted)
                }
                Spacer(minLength: 0)
                Text(L("\(TripBook.daysLabel(trip.days)) · \(trip.photos.count)枚",
                       "\(TripBook.daysLabel(trip.days)) · \(trip.photos.count) photos"))
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// 旅の記録の棚（背表紙の列＋下の説明文）。マイページの「旅の記録」のタブの中身。
///
/// **説明文は旅があっても出す**（板 16 は一覧の下に常に置いている）。
/// 0件のときだけ出すと、「なぜこの写真は旅になっていないのか」が
/// 1冊できた途端に分からなくなる
struct TripShelfList: View {

    let trips: [TripBook.Trip]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !trips.isEmpty {
                LazyVStack(spacing: 10) {
                    ForEach(trips) { trip in
                        NavigationLink {
                            TripBookView(trip: trip)
                        } label: {
                            TripShelf(trip: trip)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trips.book")
                    }
                }
            }
            Text(L("同じころに撮った写真が2枚たまると、ひとつの旅にまとまります",
                   "Two or more photos taken around the same time become a trip"))
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(WebTheme.faint)
                .frame(maxWidth: .infinity, alignment: trips.isEmpty ? .center : .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, trips.isEmpty ? 24 : 0)
        }
        .padding(.horizontal, 16)
    }
}
