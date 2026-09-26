import SwiftUI

/// 背表紙にあたる1枚。表紙の写真の上に、題と日数を置く。
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
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.place.isEmpty ? L("旅の記録", "A trip") : trip.place)
                    .font(JPFont.cardTitle)
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
}
