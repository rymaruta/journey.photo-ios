import SwiftUI
import UIKit

/// 投稿の前のプレビューのシート（札 #409・案A・決まりと理由は `PostPreview`）。
///
/// 上に下線の札「詳細・ホーム・マイページ」（アプリの下線の札 `ProfileTabBar`）、その下に公開範囲の1行、
/// 中は左右に払うページ（`ProfileTabPager`・マイページと同じ払い）。ページの中は**投稿したあとの部品**を
/// 0.8 倍に縮めて置く（押せない・行き先の画面だと分かる形）。下の帯の主ボタンで、そのまま投稿できる。
///
/// - 閉じるは左上のシートの「閉じる」（2026-11-13 owner 承認・#187）。閉じれば書きかけのまま投稿の画面へ戻る
/// - 写真・題・撮影地・公開範囲は、いま投稿の画面で入力中のもの（`UploadViewModel`）
/// - 画像の一時ファイルを書いている間と、ほかの札（ホームのほかの人・マイページの自分の写真）を読んでいる間は
///   読み込み中を出す（`JPLoadingState`・`ProgressView`）
struct PostPreviewSheet: View {

    @ObservedObject var model: UploadViewModel
    /// 「投稿する」を押した。**シートを閉じてから投稿の画面が送る**（送り終わりの共有カードは投稿の画面のシートで、
    /// このシートが開いたままだと出せない）
    let onPost: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.dismiss) private var dismiss

    /// 札の行の字の上限（大きくできない帯・長押しで大きく見せる。`PhotoEditView.typeLimit` と同じ段）
    static let tabTypeLimit = DynamicTypeSize.xxxLarge

    @State private var page: PostPreview.Page = .detail
    /// 投稿したあとの写真の行。nil は一時ファイルを書いている間（読み込み中）
    @State private var photos: [Photo]?
    /// 今回の投稿の `createdAt` を作った時刻。ホームの並びの「新しい投稿」もこの時刻で数える（`PostPreview.homeGroups`）
    @State private var clock = Date()
    /// ホームのほかの人の写真（公開の一覧）。nil は読み込み中
    @State private var neighbors: [Photo]?
    /// マイページの自分の写真。nil は読み込み中
    @State private var mine: [Photo]?
    /// 自分のピン留め（マイページの格子の先頭・`PhotoPinning.pinnedFirst`）
    @State private var pinned: [String] = []
    /// この回の一時ファイルの置き場（開くたびに別の場所・`PostPreview.directory`）
    @State private var directory = PostPreview.directory()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProfileTabBar(tabs: PostPreview.Page.allCases, selection: $page)
                    // 札の行は大きくできない帯。字は上限で止め、長押しで大きく見せる（写真の編集の帯と同じ・
                    // 2026-11-15 Mac run 1341 の絵: AX5 で「詳細」「ホーム」「マイページ」が「…」に切れていた）
                    .dynamicTypeSize(...Self.tabTypeLimit)
                    .accessibilityShowsLargeContentViewer()
                audienceRow
                GeometryReader { geo in
                    // 🔴 **縦の送りの中に置く**（送らない）。左右の払いは祖先の `UIScrollView` にパンを足す作り
                    // （`ProfileSwipePanHost.attach`: いちばん近い祖先の `UIScrollView` を探し、無ければ付けない）。
                    // 送りの外に置いた回（Mac run 1341）は、ページの上を払っても札が替わらなかった
                    ScrollView {
                        ProfileTabPager(tabs: PostPreview.Page.allCases, selection: $page) { option in
                            pageFrame(option, size: geo.size)
                        }
                    }
                    .scrollDisabled(true)
                    .overlay(alignment: .topLeading) {
                        ProfileTabSwipeProbeView(selection: page.rawValue)
                        // UI テストだけ（`-JPPreviewTabSwipeProbe`・Debug）: この回の一時ファイルの置き場。開き直すたびに
                        // 別の場所（＝縮めた絵の控えの鍵が別）になっているかを、試験が値で確かめる
                        if PreviewSession.tabSwipeProbe {
                            Text(".")
                                .font(.caption2)
                                .foregroundStyle(Color.clear)
                                .allowsHitTesting(false)
                                .accessibilityIdentifier("postPreview.probe")
                                .accessibilityValue(directory.lastPathComponent)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { submitBar }
            .webScreen()
            .navigationTitle(PostPreview.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
            }
        }
        .task { await prepare() }
        .onDisappear { removeFiles() }
    }

    // MARK: - 上と下

    /// 公開範囲の1行（模型: 12pt の text-3・印は text-2）。押す前に誰に見えるかを言う
    private var audienceRow: some View {
        let line = PostPreview.audienceLine(published: model.published, audience: model.audience)
        return HStack(spacing: 6) {
            Image(systemName: line.symbol)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .accessibilityHidden(true)
            Text(line.text)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.m)
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("postPreview.audience")
    }

    /// 下の帯（投稿の画面と同じ帯・同じ主ボタンの字）。押すと閉じて、投稿の画面が送る
    private var submitBar: some View {
        Button {
            onPost()
            dismiss()
        } label: {
            Text(UploadSubmitBar.title(count: model.items.count))
                .jpPillButton(.primary)
        }
        .buttonStyle(.plain)
        .opacity(model.canSubmit ? 1 : UploadSubmitBar.disabledOpacity)
        .disabled(!model.canSubmit)
        .accessibilityIdentifier("postPreview.submit")
        .jpBottomBar()
    }

    // MARK: - ページ

    /// 1ページの枠。中の画面を画面の幅で組んでから 0.8 倍に縮め、角 24・白 14% の線で囲む（模型の 312×548）。
    /// **中は押せない**（押すと本物の画面へ行ってしまう）。払いは枠（`contentShape`）が受けて、入れ物の払いに渡る
    private func pageFrame(_ option: PostPreview.Page, size: CGSize) -> some View {
        let scale = CGFloat(PostPreview.pageScale)
        let outer = CGSize(width: size.width * scale, height: max(0, size.height - JPSpace.xs))
        let inner = CGSize(width: size.width, height: outer.height / scale)
        return pageContent(option)
            .frame(width: inner.width, height: inner.height, alignment: .top)
            // 🔴 **中は読み上げからも外す**（2026-11-15 確かめ役の指摘）。押す指は `allowsHitTesting` で止まるが、
            // VoiceOver の操作（保存・送る・ストーリーで紹介・いいね）は中の本物の部品に届いてしまう。
            // 何が見えるかは、ページのまとめの言葉（`PostPreview.pageSummary`）で言う
            .accessibilityHidden(true)
            .background(Color.black)
            .allowsHitTesting(false)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: outer.width, height: outer.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(PostPreview.pageCorner)))
            .overlay(RoundedRectangle(cornerRadius: CGFloat(PostPreview.pageCorner))
                .strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .padding(.top, JPSpace.xxs)
            .frame(height: size.height, alignment: .top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary(option))
            .accessibilityIdentifier("postPreview.page.\(option.rawValue)")
    }

    @ViewBuilder
    private func pageContent(_ option: PostPreview.Page) -> some View {
        if let photos, let first = photos.first {
            switch option {
            case .detail:
                PhotoDetailView(photo: first, fromPublicFeed: false, context: photos, postPreview: true)
            case .home:
                homePage(photos)
            case .myPage:
                myPage(photos)
            }
        } else {
            // 一時ファイルを書いている間（大きい写真は少しかかる）
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("postPreview.loading")
        }
    }

    /// ページのまとめの読み上げ（`PostPreview.pageSummary`）
    private func summary(_ option: PostPreview.Page) -> String {
        guard let photos, let first = photos.first else { return PostPreview.loadingSpoken }
        let position: Int?
        switch option {
        case .detail: position = nil
        case .home: position = homeGroups(photos).firstIndex { PostPreview.isPreview($0.cover) }.map { $0 + 1 }
        case .myPage: position = myGrid(photos).firstIndex { PostPreview.isPreview($0) }.map { $0 + 1 }
        }
        return PostPreview.pageSummary(option, title: first.displayTitle, location: first.location ?? "",
                                       published: model.published, position: position)
    }

    private func homeGroups(_ photos: [Photo]) -> [PhotoGroups.Group] {
        PostPreview.homeGroups(preview: photos, published: model.published, neighbors: neighbors ?? [],
                               viewerId: auth.userId, now: clock)
    }

    private func myGrid(_ photos: [Photo]) -> [Photo] {
        PostPreview.myGrid(preview: photos, mine: mine ?? [], pinned: pinned)
    }

    /// ホーム: 本物のホームと同じ並べ方（`PostPreview.homeGroups`・`HomeFeedPageMemo.make`）で、今回の投稿の札に白 2pt の枠と
    /// 「あなたの投稿」（ホームと同じ `HomeMosaic`）。非公開なら札は出ず、頭に「ホームには出ません」、ほかの札は 50% に沈める
    private func homePage(_ photos: [Photo]) -> some View {
        let published = model.published
        let groups = homeGroups(photos)
        return ScrollView {
            VStack(spacing: 0) {
                if !PostPreview.showsOnHome(published: published) {
                    EmptyState(icon: nil, title: PostPreview.homeHiddenTitle, message: PostPreview.homeHiddenBody)
                        .accessibilityIdentifier("postPreview.homeHidden")
                }
                HomeMosaic(groups: groups, marked: Set(photos.map(\.id)))
                    .opacity(PostPreview.showsOnHome(published: published) ? 1 : PostPreview.homeHiddenDimOpacity)
                    .padding(.top, JPSpace.xs)
                if neighbors == nil { JPLoadingState(kind: .grid) }
            }
        }
    }

    /// マイページ: 投稿の札の行と、3列 4:5 の格子（マイページと同じ `MyPageGridCell`）。ピン留めの後ろに今回の投稿、白 2pt の枠
    private func myPage(_ photos: [Photo]) -> some View {
        let grid = myGrid(photos)
        let multiple = PhotoGroups.multiPhotoIds(grid)
        let previewIds = Set(photos.map(\.id))
        return ScrollView {
            VStack(spacing: 0) {
                ProfileTabBar(tabs: ProfileTab.tabs(isMe: true), selection: .constant(.posts), iconColumns: true)
                LazyVGrid(columns: ProfileV2.gridItems, spacing: ProfileV2.gridSpacing) {
                    ForEach(grid) { photo in
                        MyPageGridCell(photo: photo, multiple: multiple.contains(photo.id),
                                       pinned: pinned.contains(photo.id))
                            .overlay {
                                if previewIds.contains(photo.id) {
                                    Rectangle().strokeBorder(Color.white,
                                                             lineWidth: CGFloat(PostPreview.yoursFrameWidth))
                                }
                            }
                    }
                }
                if mine == nil { JPLoadingState(kind: .grid) }
            }
        }
    }

    // MARK: - 用意と片付け

    /// 画像を一時ファイルに書いて写真の行を作り、ほかの札を読む（読めなくてもプレビューは出す）
    private func prepare() async {
        guard let userId = auth.userId else { return }
        let directory = directory
        // 1組だけ書いている間（案 B3）は、送るときと同じく先頭の撮影地・題・説明を全部の写真に見せる
        let lead = model.items.first
        let shares = model.sharesFields
        let sources = model.items.map { item in
            let fields = shares ? (lead ?? item) : item
            return (data: item.prepared.data, thumbnail: item.prepared.thumbnail, title: fields.title, caption: fields.caption,
                    location: fields.location, takenOn: item.prepared.takenOn, color: item.prepared.dominantColor,
                    exif: item.prepared.exif)
        }
        // 書くのは画面の外の仕事（大きい写真）。書き終えた時点で閉じていたら、書いたものを消す（下の `isCancelled`）
        let items: [PostPreview.Item] = await Task.detached(priority: .userInitiated) {
            // 前の回の残り（落ちた・消し損ねた）もまとめて消してから書く
            try? FileManager.default.removeItem(at: PostPreview.root())
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return sources.enumerated().compactMap { index, source in
                let body = directory.appendingPathComponent("\(index).jpg")
                guard (try? source.data.write(to: body)) != nil else { return nil }
                var thumbURL: URL?
                if let thumbnail = source.thumbnail {
                    let url = directory.appendingPathComponent("\(index)_thumb.jpg")
                    if (try? thumbnail.write(to: url)) != nil { thumbURL = url }
                }
                // 縦横比は小さい方の画像から読む（展開が軽い）
                let size = UIImage(data: source.thumbnail ?? source.data)?.size ?? .zero
                return PostPreview.Item(title: source.title, caption: source.caption, location: source.location,
                                        imageURL: body, thumbnailURL: thumbURL,
                                        pixelWidth: size.width > 0 ? Double(size.width) : nil,
                                        pixelHeight: size.height > 0 ? Double(size.height) : nil,
                                        takenOn: source.takenOn, dominantColor: source.color, exif: source.exif)
            }
        }.value
        // 2026-11-15（確かめ役の指摘）: 書いている間に閉じた回は、`onDisappear` の片付けが書く前に走って、
        // 書いたファイルが残っていた。書き終えた所でもう一度片付ける
        guard !Task.isCancelled else { removeFiles(); return }
        let profile = try? await environment.profiles.publicProfile(userId: userId)
        guard !Task.isCancelled else { return }
        pinned = profile?.pinnedPhotoIds ?? []
        let made = Date()
        clock = made
        photos = PostPreview.photos(items, userId: userId, displayName: AuthorName.real(profile),
                                    published: model.published, audience: model.audience,
                                    grouped: model.groupsForSubmit, category: model.category,
                                    tags: TagInput.parse(model.tagsText), song: model.song, now: made)
        async let feed = try? environment.gallery.fetchPhotos()
        async let own = ProfileImageFromPhoto.myPhotos(environment: environment)
        let (feedPhotos, ownPhotos) = await (feed, own)
        guard !Task.isCancelled else { return }
        neighbors = hidden.visible(feedPhotos ?? [])
        mine = ownPhotos ?? []
    }

    /// この回の一時ファイルと、その URL の縮めた絵の控えを消す（端末に投稿前の写真を残さない・次に開いた回に前の写真を出さない）
    private func removeFiles() {
        for url in PostPreview.fileURLs(photos ?? []) { DownsampledRemoteImage.memory.remove(url) }
        try? FileManager.default.removeItem(at: directory)
    }
}
