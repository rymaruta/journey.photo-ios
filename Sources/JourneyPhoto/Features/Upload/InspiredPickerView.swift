import SwiftUI

/// 投稿の「この写真を見て撮影」で、元の写真を選ぶ（2026-10-14・`InspiredBy`）。
///
/// **端末の控えから選ぶ。新しいサーバーの口は使わない。** 選べるのは3つの棚（みんなの写真は 2026-10-21 から）:
///
/// - **保存した写真**（しおり・`SavedPhotosStore`）——「あとで行きたい」と思った写真をしおりで残す人が多い
/// - **行きたい場所**（`WishlistStore`）——写真の詳細の「行きたい」で入れた場所の公開写真。
///   いま書いている撮影地と同じ場所の写真を先に並べる（その場所で撮って投稿しているのだから）
///
/// 閲覧の履歴は端末に残していない（2026-10-14 時点）ので「最近見た写真」の棚は無い。
/// 引き当て先は保存した写真の画面と同じ束（公開一覧＋自分の写真・`PhotoPools`）。
/// 付けられるのは公開で全員に見せている写真だけ（`InspiredBy.canAttach`）
struct InspiredPickerView: View {

    /// 投稿の画面でいま書いている撮影地（行きたい場所の棚の並びに使う）
    let currentLocation: String?
    /// いま選んでいる元の写真の id（印を付ける）
    let selectedId: String?
    let onPick: (InspiredBy.Pick) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedShelf: InspiredBy.Shelf = .saved
    /// 見えている高さ（札の中身の最低の高さ・`ProfileTabSection`）
    @State private var viewport: CGFloat = 0
    @State private var pools: PhotoPools.Loaded?
    @State private var spotIndex: [OfficialSpot]?
    /// 開いたときに保存した写真が無く、行きたい場所がある人は、行きたい場所の棚から始める（一度だけ）
    @State private var choseStartShelf = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("その場所へ行くきっかけになった写真を付けると、写真のページに「この写真を見て撮影」と出て、元の写真の作者にも知らせが届きます。",
                       "Attach the photo that made you go. Your photo page shows “Inspired by”, and the original photographer is notified."))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                // 保存した写真 / 行きたい場所 / みんなの写真。2026-10-31 判断（#426）: マイページと同じ札
                // （下線が滑る・当たりが広い・中身を横にめくる）。札の行は端から端まで、字と中身は左右 16
                ProfileTabSection(tabs: InspiredBy.Shelf.allCases, selection: $selectedShelf, viewport: viewport,
                                  spacing: 14) { shelf in
                    content(shelf)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if height != viewport { viewport = height }
        }
        .webScreen()
        .navigationTitle(L("元の写真を選ぶ", "Choose the original"))
        .navigationBarTitleDisplayMode(.inline)
        // 板: シートは右上の「閉じる」
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("閉じる", "Close")) { dismiss() }
                    .accessibilityIdentifier("inspiredPicker.close")
            }
        }
        .task { await load() }
    }

    // MARK: - 中身

    private func candidates(_ shelf: InspiredBy.Shelf) -> [Photo] {
        guard let pools else { return [] }
        let feed = pools.feed.map { hidden.visible($0) }
        let mine = pools.mine
        switch shelf {
        case .saved:
            return InspiredBy.savedCandidates(ids: savedPhotos.ids, feed: feed, mine: mine)
        case .wishlist:
            return InspiredBy.wishCandidates(keys: wishlist.spotIds, feed: feed, index: spotIndex,
                                             currentLocation: currentLocation)
        case .everyone:
            return InspiredBy.everyoneCandidates(feed: feed, viewerId: auth.userId, currentLocation: currentLocation)
        }
    }

    /// 棚ごとの中身。**`selectedShelf` ではなく渡された棚で分ける**——選んでいない棚も持ち続ける（`ProfileTabPager`）
    @ViewBuilder
    private func content(_ shelf: InspiredBy.Shelf) -> some View {
        if pools == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if candidates(shelf).isEmpty {
            VStack(spacing: JPSpace.s) {
                Text(pools?.feed == nil
                     ? L("写真を読み込めませんでした。通信の状態を確かめてください",
                         "Couldn't load photos. Check your connection.")
                     : shelf.emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // 押せる次の一手（2026-10-21・run 609 の 45b・45c: 説明だけで行き止まりだった）。
                // 写真の無い画面の主ボタン＝真鍮の塗りに墨。読めなかった回は出さない（移っても空）
                if pools?.feed != nil, let next = shelf.emptyNextShelf {
                    Button { selectedShelf = next } label: {
                        Text(next.chooseLabel).jpPillButton(.main(onPhoto: false))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inspiredPicker.emptyNext")
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(candidates(shelf)) { photo in
                    tile(photo)
                }
            }
        }
    }

    private func tile(_ photo: Photo) -> some View {
        let selected = photo.id == selectedId
        return Button {
            onPick(InspiredBy.Pick(photo: photo))
            dismiss()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { RemoteImage(url: photo.pinImageURL) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // 選んでいる1枚: 写真の上なので白（板: 写真の上は白だけ）。印の形（丸のチェック＋白い縁）で言う
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.white, Color.black.opacity(0.55))
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pickLabel(photo))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("inspiredPicker.photo")
    }

    /// 読み上げ（板の規則: 題 · 撮影地 · 作者）
    private func pickLabel(_ photo: Photo) -> String {
        [photo.accessibilityText, photo.displayName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: PhotoMetaLine.separator)
    }

    // MARK: - 読み込み

    private func load() async {
        // 手元の束（公開一覧は 60秒の記憶・控えがあればすぐ返る）。自分の写真はログイン中だけ
        let loaded = await PhotoPools.load(environment, signedIn: auth.userId != nil)
        guard !Task.isCancelled else { return }
        pools = loaded
        if !choseStartShelf {
            choseStartShelf = true
            if InspiredBy.savedCandidates(ids: savedPhotos.ids, feed: loaded.feed, mine: loaded.mine).isEmpty,
               !wishlist.spotIds.isEmpty {
                selectedShelf = .wishlist
            }
        }
        // 台帳のスポットの「行きたい」（`SPOT-…`）を写真に当てる索引。控えがあれば通信しない
        let index = await environment.spots.fetchIndexRows()
        guard !Task.isCancelled else { return }
        spotIndex = index
    }
}
