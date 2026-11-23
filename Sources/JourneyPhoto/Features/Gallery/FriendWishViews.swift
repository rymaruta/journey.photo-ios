import SwiftUI

// 友達が、あなたの行きたい場所で撮った（札 #710 の案9・`FriendWish`）の画面の部品。
// ホームの上の札の「話す」と ⋯、写真の詳細の1行、「話す」で開くメッセージのシート

extension FriendWish.Hit: Identifiable {
    var id: String { photo.id }
}

extension View {
    /// 札の右上の ⋯（「この知らせは出さない」）と右下の「話す」。当たりはどちらも 44
    func friendWishActions(inCarousel: Bool, talk: @escaping () -> Void, mute: @escaping () -> Void) -> some View {
        self
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button(FriendWish.muteTitle, action: mute)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.text2)
                        .padding(.trailing, JPSpace.s)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("この札のメニュー", "Card menu"))
                .accessibilityIdentifier("home.friendWish.menu")
                .padding(.trailing, inCarousel ? 0 : JPSpace.gutter)
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: talk) {
                    // 行の中の小ボタン（見た目 36・当たり 44・線 白 14%）。札は黒地なので白の字
                    Text(FriendWish.talk)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: JPStroke.hairline))
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.friendWish.talk")
                .padding(.trailing, (inCarousel ? 0 : JPSpace.gutter) + JPSpace.xs)
            }
    }
}

/// 写真の詳細の1行「あなたの行きたい場所です　話す ›」（札 #710 の案9）。**人の写真で、行きたい場所に当たるときだけ**。
/// 押すと（行全体）その観光スポットの頁ではなく、持ち主への「話す」のシートを開く——行き先を1つにする
struct FriendWishPhotoLine: View {
    let photo: Photo

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var spots: [OfficialSpot] = []
    @State private var talking = false

    var body: some View {
        Group {
            if let owner = photo.userId ?? photo.uploadedBy,
               FriendWish.wishedKey(of: photo, keys: wishlist.spotIds, spots: spots, me: auth.userId) != nil {
                Button { talking = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.footnote)
                            .accessibilityHidden(true)
                        Text(FriendWish.yourPlace)
                            .font(.footnote)
                        Spacer(minLength: 8)
                        Text(FriendWish.talk + " ›")
                            .font(.footnote)
                            .foregroundStyle(WebTheme.text2)
                    }
                    // 黒地の上の手がかりなので真鍮（行きたい＝旗・owner の好み「デザインの箇所は白より真鍮」）
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .overlay(alignment: .top) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photo.friendWish")
                .sheet(isPresented: $talking) {
                    FriendWishTalkSheet(photo: photo, place: LocationMatch.display(photo.location), peerId: owner)
                }
            }
        }
        // 観光スポットの鍵（`SPOT-<slug>`）を当てるための索引。行きたい場所に観光スポットが無ければ読まない
        .task(id: wishlist.spotIds.contains(where: SavedSpotKey.isOfficial)) {
            guard spots.isEmpty, wishlist.spotIds.contains(where: SavedSpotKey.isOfficial), photo.spotId != nil else { return }
            if let index = try? await environment.spots.fetchIndex() { spots = index }
        }
    }
}

/// 「話す」で開くメッセージのシート（札 #710 の案9）。今の写真を引用するメッセージの道（`DMPhotoSend`）をそのまま使う。
/// 言葉の候補は決まった3つで、押すと欄に入るだけ（勝手に送らない・AI は使わない）。写真は持ち主の写真への引用だけで、
/// 保存や書き出しの道は作らない（CLAUDE.md「他人の写真は、その人のもの」）
struct FriendWishTalkSheet: View {
    let photo: Photo
    let place: String
    let peerId: String

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                Spacer(minLength: 0)
                // 引用の札（写真の小さな絵と場所の名前。押しても何も持ち出さない）
                HStack(spacing: 10) {
                    DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                           aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                           assumedRatioLimit: PhotoFrame.assumedRatioLimit)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place)
                            .font(.footnote)
                            .foregroundStyle(WebTheme.foreground)
                            .lineLimit(1)
                        Text(L("\(photo.displayName ?? "") さんの写真", "Photo by \(photo.displayName ?? "")"))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
                // 言葉の候補（押すと欄に入るだけ）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JPSpace.xs) {
                        ForEach(Array(zip(FriendWish.suggestionChips, FriendWish.suggestions)), id: \.0) { chip, line in
                            Button { text = line } label: {
                                Text(chip)
                                    .font(.footnote)
                                    .foregroundStyle(WebTheme.chipText)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(Color.white.opacity(0.07), in: Capsule())
                                    .overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("friendWish.suggestion")
                        }
                    }
                }
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                }
                HStack(spacing: JPSpace.xs) {
                    TextField(L("メッセージを書く", "Write a message"), text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(WebTheme.outline, lineWidth: JPStroke.hairline))
                        .accessibilityIdentifier("friendWish.field")
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WebTheme.accentText)
                            .frame(width: 44, height: 44)
                            .background(WebTheme.accentBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(sending)
                    .accessibilityLabel(L("送る", "Send"))
                    .accessibilityIdentifier("friendWish.send")
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.bottom, JPSpace.s)
            .background(Color.black)
            .navigationTitle(photo.displayName ?? FriendWish.talk)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 写真の引用と文を1通で送る（相手には「行きたい場所と合った」とは知らせない）
    private func send() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        failure = nil
        do {
            try await DMPhotoSend.send(service: environment.dm, me: auth.userId, peerId: peerId, photoId: photo.id, text: text)
            toasts.show(L("送りました", "Sent"))
            dismiss()
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send")
        }
    }
}
