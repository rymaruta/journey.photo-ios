import SwiftUI

/// 現在地の周りの写真（モック3-7）。
///
/// **現在地は端末の中だけ。** 送らないし、残さない（`CurrentLocation` の
/// 約束をここでも守る）。距離は手元の座標どうしで測る。
///
/// ⚠️ 座標は保存時に**約1kmへ丸めてある**ので、モックの「500m以内」は
/// 出せない。**持っていない精度を言わない**——出すのは「約Nkm」と件数。
///
/// **1.1.83 の案（2026-11-12 判断）**: 系統の List（灰の区切り・青の「閉じる」・灰のセグメント）をやめ、アプリの黒と
/// 真鍮にそろえた。写真は 3 列の格子（すき間 2・角なし）で、距離は写真の上のガラスの札（白の字）。範囲は絞り込みの
/// 丸チップ（板 03）、閉じるは白の字。0 件は「広げる」の一手、読めていないときは「無い」と分けて言う
struct NearbyPhotosSheet: View {

    let center: Photo.Coords
    let photos: [Photo]
    /// 地図がまだ読めていない・読むのに失敗した。**「無い」と分けるため**
    var couldNotLoad = true
    /// 読むのに失敗した回の「もう一度試す」（地図が読み直す）。nil なら出さない（読み込み中）
    var onRetry: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hidden: ModerationStore
    @State private var radius = NearbyPhotos.defaultRadius
    /// 🔴 シートの中の詳細でブロック／通報して戻ったら落とす。**戻ったとき
    /// （`onAppear`）だけ**写しを取り直す（見ている最中に絞ると詳細が閉じる）
    @State private var dropped: ModerationSnapshot?
    /// 戻るスワイプ途中の `onAppear` で行を消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    private var found: [(photo: Photo, km: Double)] {
        NearbyPhotos.photos(dropped?.visible(photos) ?? photos, near: center, withinKm: radius)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    chips
                    content
                }
                .padding(.bottom, JPSpace.xl)
            }
            .onAppear {
                switch front.appear() {
                case .first:
                    dropped = hidden.snapshot
                case .returning:
                    frontSettle?.cancel()
                    frontSettle = Task {
                        try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                        guard !Task.isCancelled, front.confirm() else { return }
                        dropped = hidden.snapshot
                    }
                }
            }
            .onDisappear {
                frontSettle?.cancel()
                frontSettle = nil
                front.disappear()
            }
            .webScreen()
            .navigationTitle(L("近くの写真", "Photos near me"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // 閉じるは白の字（板の3型・系統の青にしない）
                    Button { dismiss() } label: {
                        Text(Labels.Common.close)
                            .font(.body)
                            .foregroundStyle(WebTheme.foreground)
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    }
                    .accessibilityIdentifier("nearby.close")
                }
            }
        }
    }

    /// 範囲の丸チップ（絞り込みの形・板 03）
    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(NearbyPhotos.radiusChoices, id: \.self) { km in
                PillChip(title: L("約\(Int(km))km", "about \(Int(km)) km"), selected: radius == km) { radius = km }
                    .accessibilityIdentifier("nearby.radius.\(Int(km))")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.m)
        .padding(.top, JPSpace.xs)
    }

    @ViewBuilder
    private var content: some View {
        if photos.isEmpty && couldNotLoad {
            // 🔴 **「無い」と「取れていない」を分ける。**
            // 地図が1枚も持っていないのは「この範囲に無い」ではなく「まだ読めていない」——同じ文で出すと、
            // 圏外の人に「近くには何も無い」と言うことになる。地図に引き下げの読み直しは無い——「もう一度試す」で地図が読み直す。
            // 読み込み中（`onRetry` が nil）は骨格
            if let onRetry {
                ErrorBanner(title: L("写真をまだ読み込めていません", "Photos haven't loaded yet"),
                            message: L("地図が読み込めたら、ここに並びます", "They\u{2019}ll show here once the map loads."),
                            retry: onRetry)
            } else {
                JPLoadingState(kind: .grid)
                    .padding(.top, JPSpace.s)
            }
        } else if found.isEmpty {
            // ここまで来たら、測った結果として本当に無い。一手で広げる（広げられなければ一手なし）
            if let wider = NearbyPhotos.widerRadius(than: radius) {
                EmptyState(title: L("この範囲には、まだ写真がありません", "No photos in this range yet"),
                           message: L("範囲を広げると見つかることがあります", "Try a wider range."),
                           actionTitle: L("約\(Int(wider))kmに広げる", "Widen to about \(Int(wider)) km"),
                           actionIdentifier: "nearby.widen") { radius = wider }
            } else {
                EmptyState(title: L("この範囲には、まだ写真がありません", "No photos in this range yet"),
                           message: L("ほかの場所で開くと見つかることがあります", "Try again somewhere else."))
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(NearbyPhotos.heading(radiusKm: radius, count: found.count))
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                Spacer(minLength: 8)
                Text(L("距離は目安（約1kmの粗さ）", "Distances are approximate (about 1 km)"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .padding(.horizontal, JPSpace.m)
            .padding(.top, JPSpace.s)
            .padding(.bottom, JPSpace.xs)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(found, id: \.photo.id) { item in
                    NavigationLink {
                        PhotoDetailView(photo: item.photo, context: found.map(\.photo))
                    } label: {
                        cell(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 格子の1枚（正方形・角なし）。距離は写真の上のガラスの札（白の字・写真の上に真鍮は置かない）
    private func cell(_ item: (photo: Photo, km: Double)) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                DownsampledRemoteImage(url: item.photo.gridImageURL, contentMode: .fill,
                                       aspectRatio: item.photo.aspectRatio.map { CGFloat($0) },
                                       alignment: item.photo.gridAlignment,
                                       assumedRatioLimit: PhotoFrame.assumedRatioLimit)
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(NearbyPhotos.chipLabel(km: item.km))
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 20)
                    .jpGlass(in: Capsule())
                    .padding(6)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title(item.photo) + "、" + NearbyPhotos.label(km: item.km))
            .accessibilityAddTraits(.isButton)
    }

    private func title(_ photo: Photo) -> String {
        photo.displayTitle.isEmpty ? (photo.location.map { LocationMatch.display($0) } ?? L("写真", "Photo")) : photo.displayTitle
    }
}
