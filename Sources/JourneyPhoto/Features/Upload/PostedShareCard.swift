import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **投稿したら共有カード**（資料「SNS をもっと SNS に」①・1.1.83・2026-11-12）。
///
/// 投稿が終わったら、その写真のカード（`SignatureShareCardRenderer`）をそのまま見せ、2回でインスタ・LINE へ
/// （「カードを共有」→ アプリ）。今までは投稿すると画面が閉じるだけで、カードは写真の詳細の ⋯ →「SNS に載せる」
/// からしか作れなかった（5回）。投稿画面の「SNS にも載せる」の切り替え（既定はオフ・渡るのは透かし入りの素の写真）は無くした。
///
/// - 出すのは**公開・全体に公開**の投稿だけ（`ThreadsShare.isEligible`・絞った写真を外の SNS に流さない）
/// - 何枚投稿しても先頭の1枚
/// - 写真は投稿に使った絵（`ImagePreparer` が位置などの EXIF を落としたもの・編集後）。カードの地図は約50km に丸めた位置
/// - カードの型を足す担当（第8章・`claude/183-share-cards`）の型は、同じ部品（`SignatureShareCardSheet`）の切り替えにそのまま並ぶ
struct PostedShareCard: Identifiable {
    let id = UUID()
    /// カードに描く写真（投稿に使った絵）
    let photoData: Data
    /// 保存できた写真（題・撮影地・位置・撮影情報）
    let photo: Photo
    /// 投稿の欄の題・説明・撮影地（共有の文に使う）
    let title: String
    let description: String
    let location: String

    /// 写真の**短縮リンク**（「リンクをコピー」と共有の文・owner 2026-10-02）。`/?p=<先頭8文字>` はトップが
    /// `/?photo=<id>` に置き換える。`/photo/<id>` は再ビルドのあと（数分）まで無く、すぐ載せると 404 を読む（`PhotoLink`）
    var link: URL? {
        PhotoLink.shortURL(photoId: photo.id) ?? PhotoLink.url(photoId: photo.id, isPublished: false)
    }

    /// 共有の画面に添える文（題・説明・撮影地・「Journey Photo」とリンク・`ThreadsShare.text`）
    var text: String {
        ThreadsShare.text(title: title, description: description, location: location, url: link)
    }
}

/// 投稿の完了で出すカードの画面。自分のプロフィール（名前・@・印・顔）を読んでから、写真の詳細と同じ
/// カードの画面（`SignatureShareCardSheet`）を「投稿しました」の形で開く。
/// プロフィールが読めなくても待たせすぎない（4秒で写真の名前だけのカードにする）
struct PostedShareCardSheet: View {
    let card: PostedShareCard

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @State private var me: UserProfile?
    @State private var loaded = false

    /// プロフィールを待つ上限（秒）
    static let profileWait: Double = 4

    var body: some View {
        Group {
            if loaded {
                SignatureShareCardSheet(photoData: card.photoData,
                                        credit: PostedShareCardCredit.make(photo: card.photo, me: me),
                                        shareText: card.text,
                                        avatarURL: me?.avatarURL(cacheBust: UUID().uuidString),
                                        posted: .init(photoId: card.photo.id, link: card.link,
                                                      storyTitle: SharedPhotoStoryCard.titleLine(
                                                        title: card.photo.title?.resolved(),
                                                        location: LocationMatch.shareCardDisplay(card.photo.location)),
                                                      onFinish: { PostedCardHabit.noteFinished(shared: $0) }))
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L("共有画像を準備しています…", "Preparing image…"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .accessibilityIdentifier("postedCard")
        .task {
            guard !loaded else { return }
            // 手元にある自分のプロフィール（起動時などに読んだもの・`MyProfileCache`）があれば待たない
            if let cached = MyProfileCache.shared.profile(for: auth.userId) {
                me = cached
                loaded = true
                return
            }
            let profiles = environment.profiles
            me = await withTaskGroup(of: UserProfile?.self) { group in
                group.addTask { try? await profiles.myProfile() }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(Self.profileWait * 1_000_000_000))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            loaded = true
        }
    }
}

/// カードに焼き込む名前と情報（写真の詳細の「SNS に載せる」と同じ組み立て・`PhotoDetailView.prepareThreads`）
enum PostedShareCardCredit {
    static func make(photo: Photo, me: UserProfile?) -> SignatureShareCardRenderer.Credit {
        SignatureShareCardRenderer.Credit(
            name: AuthorName.shown(profile: me, photoDisplayName: photo.displayName),
            username: me?.username,
            // 検索用の生住所は渡さず、表示向けに短縮した地名だけ
            location: LocationMatch.shareCardDisplay(photo.location),
            // 地図とピンは約50km単位に丸めた概略位置（原座標は渡さない）
            coords: SignatureShareCardRenderer.approximateShareCoordinate(photo.coords),
            camera: photo.exif?.camera,
            lens: photo.exif?.lens,
            exposure: photo.exif?.exposure,
            aperture: photo.exif?.aperture,
            iso: photo.exif?.iso,
            verified: me?.showsVerifiedMark ?? false,
            proStyle: me?.shownProMark,
            early: me?.showsEarlyMark ?? false,
            badge: me?.shownBadge,
            place: LocationMatch.shareCardPlace(photo.location))
    }
}

/// **投稿のたびのカードを、使わない人には出しすぎない**（確かめ役の指摘・2026-11-12 判断）。
///
/// カードを閉じるだけで共有しなかった回が**2回続いたら**、次からはカードの画面を出さず、投稿のあとに
/// 「カードにする」付きの短い知らせ（`ToastCenter`）だけを出す。**一度でも共有したら**（カードを共有・
/// ストーリーに載せる・リンクをコピー）、また毎回カードに戻す。端末の中だけで覚え、設定の行は足さない
/// （CLAUDE.md「直感的で簡単に」: 既定で動く・設定を入口にしない）
enum PostedCardHabit {
    static let defaultsKey = "postedCard.closedWithoutSharing"
    /// 続けて閉じた回数がこれに届いたら、知らせだけにする
    static let quietAfter = 2

    static func showsCard(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: defaultsKey) < quietAfter
    }

    /// カードの画面を閉じた（`shared`: そこで共有したか）
    static func noteFinished(shared: Bool, defaults: UserDefaults = .standard) {
        defaults.set(shared ? 0 : defaults.integer(forKey: defaultsKey) + 1, forKey: defaultsKey)
    }

    /// 知らせだけの回の言葉
    static var quietText: String { L("投稿しました", "Posted") }
    static var quietAction: String { L("カードにする", "Make a card") }
}

/// 知らせの「カードにする」で開くカード（投稿の画面はもう閉じているので、いちばん外の画面が開く・`RootView`）
@MainActor
final class PostedCardOffer: ObservableObject {
    static let shared = PostedCardOffer()
    /// 「カードにする」を押したら開くカード
    private(set) var pending: PostedShareCard?
    /// 開いているカード
    @Published var presented: PostedShareCard?

    func offer(_ card: PostedShareCard) { pending = card }

    func present() {
        presented = pending
        pending = nil
    }
}

/// 自分のプロフィールの手元の控え（`ProfileService.myProfile` が読めたら入れる）。カードの画面が通信で待たないため
final class MyProfileCache: @unchecked Sendable {
    static let shared = MyProfileCache()
    private let lock = NSLock()
    private var stored: UserProfile?

    func remember(_ profile: UserProfile) {
        lock.lock(); defer { lock.unlock() }
        stored = profile
    }

    /// その人の控え（人が替わっていれば nil）
    func profile(for userId: String?) -> UserProfile? {
        lock.lock(); defer { lock.unlock() }
        guard let userId, let stored, stored.userId == userId else { return nil }
        return stored
    }
}
