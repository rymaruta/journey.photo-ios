import SwiftUI

/// ホームの写真の並び（板 01c）。
///
/// **大きく1枚 → 2枚 → 2枚 の繰り返し**（`EditorialLayout` と同じリズム）を、
/// 端から端まで・隙間 4pt・角なしで組む。撮影地と撮った人は写真の上に重ね、
/// いいねは右下のガラスの丸で押せる。
///
/// 以前は縦1列の札（作者・写真・題・説明・タグ・4つの操作）だった
/// （提案の絵・2026-09-21）。owner の「ホームをアーティファクト通りに・
/// 主に写真の表示部分」（2026-09-26）で板 01c の組みにした。
/// 題・説明・保存・共有・フォローは写真の詳細にある。**通報とブロックは
/// 各写真の「…」にも残す**（審査 1.2・審査メモの「各写真の『…』から」）
struct HomeMosaic: View {

    let groups: [PhotoGroups.Group]
    /// 「通報する」を押したとき。**シートは一覧（`GalleryView`）が出す。**
    /// 写真に付けると、通報で一覧が読み直されて写真ごと消え、
    /// 「受け付けました」やブロック失敗の文言を見る前にシートが閉じる
    var onReport: (Photo) -> Void = { _ in }

    /// 段どうし・段の中の隙間（板: 4px）
    private let gap: CGFloat = 4

    var body: some View {
        let byCover = Dictionary(groups.map { ($0.cover.id, $0) }, uniquingKeysWith: { first, _ in first })
        LazyVStack(spacing: gap) {
            ForEach(EditorialLayout.rows(groups.map(\.cover))) { row in
                switch row {
                case .hero(let photo):
                    tile(photo, byCover: byCover, large: true)
                case .pair(let first, let second):
                    if let second {
                        HStack(spacing: gap) {
                            tile(first, byCover: byCover, large: false)
                            tile(second, byCover: byCover, large: false)
                        }
                    } else {
                        // **相方が無い段は1枚で横いっぱい**（半分だけ写真がある段を作らない）
                        tile(first, byCover: byCover, large: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ photo: Photo, byCover: [String: PhotoGroups.Group], large: Bool) -> some View {
        let group = byCover[photo.id]
        HomeFeedTile(photo: photo, siblings: group?.photos ?? [photo], large: large, onReport: onReport)
    }
}

/// ホームの1枚（板 01c）。写真・撮影地と撮った人の重ね・右下のいいね・複数枚の印
struct HomeFeedTile: View {

    let photo: Photo
    /// 同じ投稿の写真（`photo` を含む）。2枚以上なら右上に印
    var siblings: [Photo] = []
    /// 大きい段（16:9・撮影地 22pt・投稿した時期も出す）か、2枚の段（1:1・18pt）か
    var large = false
    var onReport: (Photo) -> Void = { _ in }

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    /// 「…」のブロックの確認
    @State private var showBlockConfirm = false
    /// サーバーが答えたいいねの数（詳細画面で押したぶんもここに来る）
    @EnvironmentObject private var likeCounts: LikeCountStore
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink {
                PhotoDetailView(photo: photo, context: siblings.isEmpty ? [photo] : siblings)
            } label: {
                Color.clear
                    .aspectRatio(large ? 16.0 / 9.0 : 1, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: large ? photo.detailImageURL : photo.gridImageURL,
                                    alignment: photo.gridAlignment)
                    }
                    .clipped()
                    .overlay(alignment: .bottomLeading) { caption }
                    .overlay(alignment: .topTrailing) {
                        // 「…」の丸と重ならないよう、印はその左
                        multipleMark.padding(.trailing, showsMore ? 44 : 0)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 絵の上の文字（撮影地・撮った人・複数枚の印）も読む。題だけにすると、
            // 題のある写真では**画面に出ている撮影地と名前が読まれない**
            .accessibilityLabel(HomeTileText.readout(
                base: photo.accessibilityText,
                place: HomeTileText.place(photo.location),
                byline: byline,
                multiple: siblings.count > 1 ? L("複数枚の投稿", "Multiple photos") : nil))
            // **実機の絵の道しるべ。** 「一覧の1枚目」を位置で探すと、
            // 今日のテーマの「参加する」に当たって**ログイン画面を
            // 『写真の詳細』として撮って**いた（run 49 の絵で判明）
            .accessibilityIdentifier("feed.photo")

            likeButton
        }
        .overlay(alignment: .topTrailing) { moreMenu }
    }

    /// 自分の写真には出さない（編集は詳細で）
    private var showsMore: Bool { photo.userId == nil || photo.userId != auth.userId }

    /// 「…」（通報・ブロック）。中身は写真詳細の「…」と同じ。見た目はいいねと
    /// 同じガラスの丸（32pt）で、押せる範囲は 44pt
    @ViewBuilder
    private var moreMenu: some View {
        if showsMore {
            Menu {
                Button { onReport(photo) } label: {
                    Label(L("通報する", "Report"), systemImage: "flag")
                }
                if photo.userId != nil {
                    Button(role: .destructive) { showBlockConfirm = true } label: {
                        Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("この写真の操作", "More actions"))
            .confirmationDialog(L("この人をブロックしますか？", "Block this person?"),
                                isPresented: $showBlockConfirm, titleVisibility: .visible) {
                Button(L("ブロック", "Block"), role: .destructive) { Task { await block() } }
            } message: {
                Text(L("おたがいの投稿・ストーリー・通知が見えなくなります。", "You won't see each other's posts, stories, or notifications."))
            }
        }
    }

    private func block() async {
        guard let ownerId = photo.userId else { return }
        do {
            try await hidden.blockAndHide(ownerId, environment: environment)
            toasts.show(L("ブロックしました", "Blocked"))
        } catch {
            toasts.show((error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block"),
                        kind: .failure)
        }
    }

    private var byline: String {
        HomeTileText.byline(author: AuthorName.shown(profile: nil, photoDisplayName: photo.displayName),
                            ago: large ? StoryPlayback.ago(from: photo.createdAt) : nil)
    }

    /// 撮影地と撮った人（板: 明朝の撮影地、その下に 11pt）。**撮影地が無い写真は
    /// 文字を重ねず、下を薄く暗くするだけ**（いいねの丸を読ませるため）
    @ViewBuilder
    private var caption: some View {
        let place = HomeTileText.place(photo.location)
        if !place.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(place)
                    .font(JPFont.display(large ? 22 : 18, relativeTo: large ? .title2 : .title3))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 1)
                    .lineLimit(1)
                Text(byline)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }
            // いいねの丸と重ならないよう右を空ける
            .padding(.leading, 14)
            .padding(.trailing, 70)
            .padding(.bottom, 12)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(stops: [
                    .init(color: Color.black.opacity(0), location: 0),
                    .init(color: Color.black.opacity(0.78), location: 0.6),
                    .init(color: Color.black.opacity(0.78), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
        } else {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 56)
                .allowsHitTesting(false)
        }
    }

    /// 複数枚の印（板: 右上の重なった四角）
    @ViewBuilder
    private var multipleMark: some View {
        if siblings.count > 1 {
            Image(systemName: "square.on.square")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.5), radius: 3)
                .padding(8)
                .accessibilityLabel(L("複数枚の投稿", "Multiple photos"))
        }
    }

    /// いいね（板: 右下のガラスの丸・32pt・等幅の数）
    private var likeButton: some View {
        Button {
            Task { await toggleLike() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(likeCount)")
                    .font(JPFont.mono(11))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 32)
            .background(Color.black.opacity(0.55), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            // **押せる範囲は丸の外まで広げる**（見た目は 32pt のまま、押せる高さは
            // 44pt）。丸の縁の少し上を押すと、背後の写真が拾って詳細が開いていた
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("いいね \(likeCount)", "Like, \(likeCount)"))
        // 色で分けないので、押したかどうかは形と読み上げで伝える
        .accessibilityAddTraits(liked ? .isSelected : [])
    }

    private var liked: Bool { favorites.contains(photo.id) }

    /// いいね。**サーバーへ送る。**
    ///
    /// 🔴 ここは長いあいだ端末の控えを反転するだけで、**押しても
    /// サーバーには一度も届いていなかった**（詳細画面を開くと
    /// 押していない状態に戻る）。控えは送れたときだけ合わせる。
    private func toggleLike() async {
        // **答えを待っている間は押させない。** 二度目が古い `liked` を見て
        // 逆向きに飛ぶと、ハートと数が押した結果と食い違う（詳細画面の
        // `isLiking` と同じ）
        guard pendingDelta == 0 else { return }
        let wasLiked = liked
        // 先に画面を変える（押した手応えを待たせない）
        favorites.set(photo.id, favorite: !wasLiked)
        pendingDelta = wasLiked ? -1 : 1
        defer { pendingDelta = 0 }
        do {
            let result = wasLiked
                ? try await environment.social.unlike(photoId: photo.id)
                : try await environment.social.like(photoId: photo.id)
            // **返ってきた数と状態を使う。** 自分で数えない。
            // 数を返さない答えなら、押したあとに見えていた数で止める
            likeCounts.set(photo.id, count: result.likes ?? likeCount)
            favorites.set(photo.id, favorite: result.liked)
        } catch {
            // **届かなかったら戻す。** 画面だけ「いいね済み」にしない
            favorites.set(photo.id, favorite: wasLiked)
        }
    }

    /// 押して答えを待っている間だけの ±1。**答えが来たら 0 に戻す**
    @State private var pendingDelta = 0

    /// 出すいいねの数。
    ///
    /// 土台は、押した答え（`LikeCountStore`・ここで押した回も詳細で押した回も
    /// 入る）と一覧の数（いまの数に差し替え済み）の**新しい方**。
    /// 待っている間だけ ±1 を足す。
    ///
    /// 🔴 以前は「端末でいいね済みなら一覧の数に +1」だった。一覧の数には
    /// **自分のいいねが既に入っている**ので、押したことのある写真は
    /// いつも1つ多く出ていた（しかも一覧の数はサイトを建てた時点の古い数）。
    private var likeCount: Int {
        LiveLikes.displayCount(base: LiveLikes.base(for: photo, stored: likeCounts.entry(for: photo.id)),
                               pendingDelta: pendingDelta)
    }

}

/// ホームの1枚に重ねる文字（画面を持たない計算だけ）
enum HomeTileText {

    /// 撮影地の短い名前（板: 「金沢」）。**最初の区切りまで**
    /// （「パリ, フランス」→「パリ」）。無ければ空
    static func place(_ location: String?) -> String {
        let trimmed = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed.split(whereSeparator: { ",、，".contains($0) }).first.map(String.init) ?? trimmed
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 読み上げ（題 → 撮影地 → 撮った人 → 複数枚）。題が無い写真は
    /// `base` が既に撮影地を含む（「パリ, フランス の写真」）ので二度読まない
    static func readout(base: String, place: String, byline: String, multiple: String?) -> String {
        var parts = [base]
        if !place.isEmpty, !base.contains(place) { parts.append(place) }
        if !byline.isEmpty { parts.append(byline) }
        if let multiple, !multiple.isEmpty { parts.append(multiple) }
        return parts.joined(separator: ", ")
    }

    /// 撮影地の下の1行（板: 「名前 · 2日前」、2枚の段は名前だけ）
    static func byline(author: String, ago: String?) -> String {
        guard let ago, !ago.isEmpty else { return author }
        return "\(author) · \(ago)"
    }
}
