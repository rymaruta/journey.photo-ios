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
    /// 写真をつないだ線を開いているか。**初めは畳む**（`routeStartsFolded`）
    @State private var routeOpen = !Self.routeStartsFolded

    /// 🔴 **写真をつないだ線は初めは畳む**（2026-10-21 判断・全画面の点検）。線（高さ 100）が数の下に
    /// いつも開いていて、BGM・ハイライトと合わせて写真の格子が最初の画面の一番下にしか出なかった。
    /// 眉ラベルと数字（距離・国）はそのまま見せ、線は眉ラベルの右の「線を見る」で開く（開くと一度だけ引く）。
    /// マイページと人のページで同じ（同じ部品）。開いたかは覚えない——開いたままだと、次に来たとき
    /// また格子が下がる
    nonisolated static let routeStartsFolded = true

    var body: some View {
        TravelRecordView(kilometers: summary.kilometers,
                         countries: summary.countries,
                         coordinates: summary.coordinates,
                         firstYear: summary.firstYear,
                         onDistanceTap: { showDistanceNote = true },
                         onCountriesTap: { showCountriesNote = true },
                         routeShown: routeOpen,
                         onRouteToggle: {
                             withAnimation(.easeOut(duration: 0.25)) { routeOpen.toggle() }
                         })
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

/// 人のページの「旅」（板 UserProfile F33）。小見出し「旅」の下に札1枚。
///
/// この人の**公開写真だけ**を、マイページの「旅の記録」の棚と同じ規則で束ねた一冊
/// （`ProfileTravelRecord.othersShelf`）。いちばん新しい一冊を 44pt の札に畳み、
/// 表紙は開いた先（`TripBookView`）で見せる——写真の格子の1段目を一画面目に残すため（板の注記）。
/// 札（板の数値）: 角 12・白 5% の地・白 10% の縁・左に 44pt の表紙の小さな写真・明朝の題・
/// 等幅の数字の「2日間 · 22枚」・灰の矢印。小見出しは 12pt・白 60%。**板の 11pt の数字は 12pt に上げた**
/// （本文系の最小 12）。題は明朝の下限（`JPFont.rowTitle`・18）で、板の 15 より大きい。
/// 2冊以上あれば、札の下に「すべての旅」（棚はマイページと同じ `TripShelfList`）。
/// 開いた一冊・棚は**人の一冊**（`isMine: false`）——「この一冊を送る」を出さない（2026-10-16 判断）。
/// **一冊も無ければ呼ぶ側が節ごと出さない**
struct ProfileTripsLine: View {

    let shelf: ProfileTravelRecord.OthersShelf

    /// 板の札の地と縁（白 5%・白 10%）
    nonisolated static let cardFillOpacity = 0.05
    nonisolated static let cardStrokeOpacity = 0.10
    /// 板の札の高さと表紙の小さな写真の辺
    nonisolated static let cardHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text(L("旅", "Trips"))
                .font(JPFont.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .accessibilityAddTraits(.isHeader)
            if let latest = shelf.trips.first {
                NavigationLink {
                    TripBookView(trip: latest, isPublic: shelf.hasPage, isMine: false)
                } label: {
                    card(latest)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("旅 \(TripBook.title(of: latest))、\(Self.facts(latest))",
                                      "Trip \(TripBook.title(of: latest)), \(Self.facts(latest))"))
                .accessibilityIdentifier("profile.trip")
            }
            if shelf.trips.count > 1 {
                NavigationLink {
                    ProfileTripsScreen(shelf: shelf)
                } label: {
                    HStack(spacing: 6) {
                        Text(L("すべての旅 · \(shelf.trips.count)冊", "All trips · \(shelf.trips.count)"))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WebTheme.text3)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.trips.all")
            }
        }
        .padding(.horizontal, ProfileV2.gutter)
    }

    /// 「2日間 · 22枚」（板の等幅の数字の1行）
    nonisolated static func facts(_ trip: TripBook.Trip) -> String {
        "\(TripBook.daysLabel(trip.days)) · \(PhotoMapViewModel.photoCountLabel(trip.photos.count))"
    }

    private func card(_ trip: TripBook.Trip) -> some View {
        HStack(spacing: 10) {
            // 左に 44pt の表紙の小さな写真（板: 左の角だけ丸い・札の縁の内側）
            Color.clear
                .frame(width: Self.cardHeight, height: Self.cardHeight)
                .overlay {
                    if let cover = trip.cover {
                        RemoteImage(url: cover.gridImageURL, alignment: cover.gridAlignment)
                    }
                }
                .background(WebTheme.card)
                .clipped()
                .accessibilityHidden(true)
            // 🔴 題が長ければ題を「…」で省く。日数・枚数は切らない（`layoutPriority`・`fixedSize`）
            Text(TripBook.title(of: trip))
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.facts(trip))
                .font(JPFont.mono(12))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.trailing, 12)
        .frame(minHeight: Self.cardHeight)
        .background(Color.white.opacity(Self.cardFillOpacity))
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.field))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.field)
            .strokeBorder(Color.white.opacity(Self.cardStrokeOpacity), lineWidth: JPStroke.hairline))
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.field))
    }
}

/// 人の旅の棚（「すべての旅」から）。中身はマイページの「旅の記録」のタブと同じ `TripShelfList`。
/// **人の棚**（`isMine: false`）——本人向けの説明の後半と「この一冊を送る」を出さない
struct ProfileTripsScreen: View {

    let shelf: ProfileTravelRecord.OthersShelf

    var body: some View {
        ScrollView {
            TripShelfList(trips: shelf.trips, isPublic: shelf.hasPage, isMine: false)
                .padding(.vertical, JPSpace.m)
        }
        .webScreen()
        .navigationTitle(L("旅", "Trips"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
