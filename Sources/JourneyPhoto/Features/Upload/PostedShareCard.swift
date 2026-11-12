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
                                                        location: LocationMatch.shareCardDisplay(card.photo.location))))
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
