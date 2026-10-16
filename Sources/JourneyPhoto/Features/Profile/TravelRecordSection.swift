import SwiftUI

/// プロフィールの「旅の記録」の節（`TravelRecordView` と、押すと出る数え方の説明）。
///
/// **マイページと人のページで同じ部品**（2026-10-16 判断）。以前はマイページの中に直に
/// 書いてあった（中身・余白・説明の文は今までと同じ）。どの写真から作るかは呼ぶ側が
/// `ProfileTravelRecord` で決める。**空（`summary.isEmpty`）なら呼ぶ側が出さない**
/// ——空の部品を並びに置くと、上下の間だけが残る
struct TravelRecordSection: View {

    let summary: ProfileTravelRecord.Summary
    /// 自分の記録か（説明の文だけが変わる）
    let isMine: Bool

    @State private var showDistanceNote = false
    @State private var showCountriesNote = false

    var body: some View {
        TravelRecordView(kilometers: summary.kilometers,
                         countries: summary.countries,
                         coordinates: summary.coordinates,
                         firstYear: summary.firstYear,
                         onDistanceTap: { showDistanceNote = true },
                         onCountriesTap: { showCountriesNote = true })
        .padding(.horizontal, ProfileV2.gutter)
        .padding(.top, JPSpace.xs)
        .alert(L("訪れた国・地域", "Countries and regions"),
               isPresented: $showCountriesNote) {
            Button(Labels.Common.close, role: .cancel) {}
        } message: {
            // **数え方をそのまま書く。** 「思ったより少ない」の答えが
            // ここにある（国名を書いた写真しか数えていない）
            Text(ProfileTravelRecord.countriesNote(isMine: isMine))
        }
        .alert(L("写真をつないだ距離", "Distance between photos"),
               isPresented: $showDistanceNote) {
            Button(Labels.Common.close, role: .cancel) {}
        } message: {
            Text(ProfileTravelRecord.distanceNote(isMine: isMine))
        }
    }
}

/// 人のページの「旅」（板 UserProfile F33・v2: 名前と数の下に1行の札）。
///
/// この人の**公開写真だけ**を、マイページの「旅の記録」の棚と同じ規則で束ねた一冊
/// （`ProfileTravelRecord.othersTrips`）。いちばん新しい一冊を1行（見た目 48・押せる 44 以上）に畳み、
/// 表紙は開いた先（`TripBookView`）で見せる——写真の格子の1段目を一画面目に残すため（板の注記）。
/// 2冊以上あれば、下に「すべての旅」の行（棚はマイページと同じ `TripShelfList`）。
/// **一冊も無ければ呼ぶ側が節ごと出さない**
struct ProfileTripsLine: View {

    let trips: [TripBook.Trip]
    /// 写真に個別ページが在るか（`TripBookView.isPublic`）
    let isPublic: (Photo) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let latest = trips.first {
                NavigationLink {
                    TripBookView(trip: latest, isPublic: isPublic)
                } label: {
                    row(icon: "book.closed") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(L("旅 ·", "Trip ·"))
                                .font(JPFont.body)
                                .foregroundStyle(WebTheme.text2)
                            Text(TripBook.title(of: latest))
                                .font(JPFont.rowTitle)
                                .foregroundStyle(WebTheme.foreground)
                                .lineLimit(1)
                                .layoutPriority(1)
                            Text(Self.facts(latest))
                                .font(JPFont.meta)
                                .foregroundStyle(WebTheme.text3)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("旅 \(TripBook.title(of: latest))、\(Self.facts(latest))",
                                      "Trip \(TripBook.title(of: latest)), \(Self.facts(latest))"))
                .accessibilityIdentifier("profile.trip")
            }
            if trips.count > 1 {
                NavigationLink {
                    ProfileTripsScreen(trips: trips, isPublic: isPublic)
                } label: {
                    row(icon: "books.vertical") {
                        Text(L("すべての旅 · \(trips.count)冊", "All trips · \(trips.count)"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.trips.all")
            }
        }
        .overlay(alignment: .top) { divider }
        .padding(.horizontal, ProfileV2.gutter)
    }

    /// 「2日間 · 22枚」（板の等幅の1行）
    nonisolated static func facts(_ trip: TripBook.Trip) -> String {
        "\(TripBook.daysLabel(trip.days)) · \(PhotoMapViewModel.photoCountLabel(trip.photos.count))"
    }

    /// 板の札: 真鍮の本の印（黒地の上）・中身・灰の矢印、下に白 8% の線
    private func row<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(WebTheme.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { divider }
    }

    private var divider: some View {
        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
    }
}

/// 人の旅の棚（「すべての旅」から）。中身はマイページの「旅の記録」のタブと同じ `TripShelfList`
struct ProfileTripsScreen: View {

    let trips: [TripBook.Trip]
    let isPublic: (Photo) -> Bool

    var body: some View {
        ScrollView {
            TripShelfList(trips: trips, isPublic: isPublic)
                .padding(.vertical, JPSpace.m)
        }
        .webScreen()
        .navigationTitle(L("旅", "Trips"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
