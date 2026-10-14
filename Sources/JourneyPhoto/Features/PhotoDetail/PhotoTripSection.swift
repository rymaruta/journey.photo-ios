import SwiftUI

/// 写真の詳細の「行き先」の段（2026-10-14・写真から、次の旅へ）。
///
/// いいね・コメント・保存・共有の段の下に、**行きたい**（場所）と、台帳の撮影スポットのときだけ
/// **経路**と「いつ」の1行（次のゴールデンアワーか撮りどきの季節・`PhotoTrip.whenLine`）を出す。
/// 写真が主役なので1つの段に収め、多くしない。
///
/// **保存（写真のしおり）と分ける。** 保存は写真を手元に残す（しおりの印・上の段）。
/// 行きたいは**場所**を旅の候補に入れる（旗の印・文字つき）——押すと「行きたい」の一覧と旅のプランに並ぶ。
/// 鍵はスポットの頁・撮影地の頁と同じ（`PhotoTrip.Destination.wishKey`）なので、どこで押しても状態がそろう。
///
/// 見た目（デザインの板「黒塗りの真鍮」）: 写真の下の黒地の段なので、印（旗・経路・太陽）は真鍮
/// （黒地の上の手がかり・CLAUDE.md の owner の好み「デザインの箇所は白より真鍮」）、文字は白。
/// 札の地は surface（白 7%）。**選んだ状態は形でも伝える**——旗が塗りに変わり、縁が真鍮になり、
/// 読み上げは「選択中」。押せるものは高さ 44pt。
struct PhotoTripSection: View {

    let destination: PhotoTrip.Destination
    /// 「いつ」の1行（台帳のスポットで、座標か季節が分かるときだけ）
    let when: String?

    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var environment: AppEnvironment

    /// 「経路」を探している最中（連打で2つ開かない）・その仕事（離れたら取り消す）
    @State private var openingDirections = false
    @State private var directionsTask: Task<Void, Never>?
    /// 段が出ているか（「経路」を探している間に離れたら開かない・`SpotDirections`）
    @State private var onScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                wishButton
                if PhotoTrip.offersDirections(destination) {
                    directionsButton
                }
                Spacer(minLength: 0)
            }
            if let when {
                Label {
                    Text(when)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(WebTheme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sun.horizon")
                        .font(.caption)
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("photo.trip.when")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo.trip")
        .onAppear { onScreen = true }
        .onDisappear {
            onScreen = false
            directionsTask?.cancel()
            directionsTask = nil
        }
    }

    // MARK: - 行きたい

    private var wishButton: some View {
        let key = destination.wishKey
        let wanted = wishlist.contains(key)
        return Button {
            // ログイン中はサーバーへ送る。失敗したら戻して知らせる（`WishlistSync`・スポットの頁と同じ）
            Task {
                let outcome = await WishlistSync.toggle(key, store: wishlist, service: environment.savedSpots)
                if let notice = WishlistSync.notice(for: outcome) { toasts.show(notice.text, kind: notice.kind) }
            }
        } label: {
            chip(icon: wanted ? "flag.fill" : "flag", title: L("行きたい", "Want to go"), selected: wanted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("行きたい: \(destination.name)", "Want to go: \(destination.name)"))
        .accessibilityValue(wanted ? L("追加済み", "Added") : "")
        .accessibilityAddTraits(wanted ? .isSelected : [])
        .accessibilityHint(L("行きたい場所の一覧に入れます。写真の保存とは別です",
                             "Adds this place to your wishlist. Separate from saving the photo."))
        .accessibilityIdentifier("photo.trip.wish")
    }

    // MARK: - 経路（台帳のスポットだけ）

    private var directionsButton: some View {
        Button {
            openDirections()
        } label: {
            chip(icon: "arrow.triangle.turn.up.right.diamond", title: L("経路", "Directions"),
                 selected: false, busy: openingDirections)
        }
        .buttonStyle(.plain)
        .disabled(openingDirections)
        .accessibilityLabel(L("\(destination.name)への経路", "Directions to \(destination.name)"))
        .accessibilityValue(openingDirections ? L("開いています", "Opening") : "")
        .accessibilityHint(L("Apple のマップで開きます", "Opens in Apple Maps"))
        .accessibilityIdentifier("photo.trip.directions")
    }

    private func openDirections() {
        guard let spot = destination.spot, let coords = spot.coords, !openingDirections else { return }
        openingDirections = true
        let name = spot.name
        directionsTask = Task { @MainActor in
            defer { openingDirections = false }
            await SpotDirections.openDirections(name: name, coords: coords, stillWanted: { onScreen })
        }
    }

    // MARK: - 札

    /// 黒地の札（surface・角丸の丸み）。印は真鍮、字は白 15pt。選んだら縁を真鍮に（形でも伝える）
    private func chip(icon: String, title: String, selected: Bool, busy: Bool = false) -> some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView().tint(WebTheme.accent)
            } else {
                Image(systemName: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: WebTheme.minTapTarget)
        .background(WebTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? WebTheme.accent : WebTheme.outline, lineWidth: 1))
        .contentShape(Capsule())
    }
}
