import SwiftUI

/// いちばん新しい一冊の**大きな表紙の札**（v2 の板 Trips・2026-10-14）。
///
/// 高さ 190・角 16 の写真の札に、下から黒 72% の溶け、明朝の題と「期間 · 日数 · 枚数」。
/// **写真の上なので字は白だけ**（灰は透過の `muted`。真鍮は置かない・CLAUDE.md）
struct TripShelf: View {

    let trip: TripBook.Trip

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: TripStyle.coverCardHeight)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let cover = trip.cover {
                        RemoteImage(url: cover.gridImageURL, alignment: cover.gridAlignment)
                    }
                }
                .clipped()
            // 板: 下の黒 72% から、高さの 65% の所で 0 に
            LinearGradient(
                stops: [.init(color: Color.black.opacity(TripStyle.coverCardShade), location: 0),
                        .init(color: Color.black.opacity(0), location: 0.65)],
                startPoint: .bottom, endPoint: .top
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(TripBook.title(of: trip))
                    .font(JPFont.display(24, relativeTo: .title2))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                Text(TripStyle.tripLine(trip))
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 13))
                if TripStyle.groupedByUploadDate(trip.photos) {
                    // 写真の上なので、黒 45% の地に白の線（板 TripBook の表紙の札と同じ）
                    UploadDateChip(onPhoto: true)
                        .padding(.top, JPSpace.xxs)
                }
            }
            .padding(.horizontal, JPSpace.m)
            .padding(.bottom, 14)
        }
        // **自分だけの一冊に鍵**（非公開の写真が入っている）。写真の上なので白、
        // 読めるように黒の丸を敷く
        .overlay(alignment: .topTrailing) {
            if trip.isPrivate { PrivateTripMark().padding(10) }
        }
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l)
            .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .accessibilityElement(children: .combine)
    }
}

/// 2冊目からの**写真つきの行**（板 Trips: 高さ 72・左に 72×56 の写真・明朝の題・等幅の1行・下に区切り線）
struct TripShelfRow: View {

    let trip: TripBook.Trip

    var body: some View {
        HStack(spacing: 14) {
            Color.clear
                .frame(width: TripStyle.rowThumb.width, height: TripStyle.rowThumb.height)
                .overlay {
                    if let cover = trip.cover {
                        RemoteImage(url: cover.gridImageURL, alignment: cover.gridAlignment)
                    }
                }
                .background(WebTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
                .overlay(alignment: .topTrailing) {
                    if trip.isPrivate { PrivateTripMark(small: true).padding(4) }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // 板は 17 だが、明朝の下限 18（`JPTypeScale.title3`）を守る
                Text(TripBook.title(of: trip))
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                Text(TripStyle.tripLine(trip))
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(WebTheme.minimumScale(forTextSize: JPTypeScale.meta))
                if TripStyle.groupedByUploadDate(trip.photos) {
                    UploadDateChip()
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, JPSpace.xs)
        .frame(minHeight: TripStyle.rowMinHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 自分だけの一冊の鍵（写真の上なので白に黒の丸）
private struct PrivateTripMark: View {
    var small = false

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: small ? 10 : 12, weight: .semibold))
            .foregroundStyle(WebTheme.foreground)
            .frame(width: small ? 20 : 26, height: small ? 20 : 26)
            .background(Color.black.opacity(0.55), in: Circle())
            .accessibilityLabel(L("自分だけ", "Only you"))
    }
}

/// 「投稿日でまとめています」の線の札（板 Trips・TripBook: 撮影日の無い写真だけの旅）。
/// 黒地の上は text-2 の字に白 14% の線、写真の上は白の字に黒 45% の地・白 30% の線
struct UploadDateChip: View {
    var onPhoto = false

    var body: some View {
        Text(L("投稿日でまとめています", "Grouped by upload date"))
            .font(JPFont.caption)
            .foregroundStyle(onPhoto ? WebTheme.foreground : WebTheme.text2)
            .padding(.horizontal, JPSpace.xs)
            .padding(.vertical, 1)
            .background(onPhoto ? Color.black.opacity(0.45) : Color.clear, in: RoundedRectangle(cornerRadius: JPRadius.s))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.s)
                .strokeBorder(onPhoto ? Color.white.opacity(0.3) : WebTheme.line, lineWidth: JPStroke.hairline))
    }
}

/// 旅の記録の棚（表紙の札＋写真つきの行＋下の説明文）。マイページの「旅の記録」のタブの中身。
///
/// **v2（2026-10-14・板 Trips）**: いちばん新しい一冊だけ大きな表紙の札、残りは写真つきの行。
/// 0 冊のときは空の状態（明朝の見出し＋説明）。
///
/// **説明文は旅があっても出す**（板 16 は一覧の下に常に置いている）。
/// 0件のときだけ出すと、「なぜこの写真は旅になっていないのか」が
/// 1冊できた途端に分からなくなる
struct TripShelfList: View {

    let trips: [TripBook.Trip]
    /// 写真に個別ページが在るか（`TripBookView.isPublic`）
    var isPublic: (Photo) -> Bool = { _ in false }
    /// 自分の棚か。人の棚（人のプロフィールの「すべての旅」）は偽——説明文から本人向けの
    /// 後半を落とし、開いた一冊で「この一冊を送る」を出さない（2026-10-16 判断）
    var isMine = true

    nonisolated static var explanation: String { explanation(isMine: true) }

    /// 下の説明文。**「旅の写真からまとめて」は本人の操作**なので、人の棚では言わない
    nonisolated static func explanation(isMine: Bool) -> String {
        guard isMine else {
            return L("同じころに撮った公開写真が2枚たまると、ひとつの旅にまとまります",
                     "Two or more public photos taken around the same time become a trip")
        }
        return L("同じころに撮った公開写真が2枚たまると、ひとつの旅にまとまります。「旅の写真からまとめて」で入れた写真は、その束で一冊になります",
                 "Two or more public photos taken around the same time become a trip. Photos added with \"From a trip in your photos\" become one trip together")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if trips.isEmpty {
                // 空の状態（v2 Components 06: 明朝 20 の見出し → 説明）
                EmptyState(title: L("まだ旅はありません", "No trips yet"), message: Self.explanation(isMine: isMine))
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        NavigationLink {
                            TripBookView(trip: trip, isPublic: isPublic, isMine: isMine)
                        } label: {
                            if index == 0 {
                                TripShelf(trip: trip)
                            } else {
                                TripShelfRow(trip: trip)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trips.book")
                    }
                }
                Text(Self.explanation(isMine: isMine))
                    .font(JPFont.caption)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, JPSpace.xxs)
            }
        }
        .padding(.horizontal, JPSpace.gutter)
    }
}
