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

    @State private var page: PostPreview.Page = .detail
    /// 投稿したあとの写真の行。nil は一時ファイルを書いている間（読み込み中）
    @State private var photos: [Photo]?
    /// ホームのほかの人の写真（公開の一覧）。nil は読み込み中
    @State private var neighbors: [Photo]?
    /// マイページの自分の写真。nil は読み込み中
    @State private var mine: [Photo]?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProfileTabBar(tabs: PostPreview.Page.allCases, selection: $page)
                audienceRow
                GeometryReader { geo in
                    ProfileTabPager(tabs: PostPreview.Page.allCases, selection: $page) { option in
                        pageFrame(option, size: geo.size)
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
            .accessibilityElement(children: .contain)
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

    /// ホーム: 今回の投稿の札が先頭（白 2pt の枠と「あなたの投稿」）、後ろにほかの人の札（ホームと同じ `HomeMosaic`）。
    /// 非公開なら札は出ず、頭に「ホームには出ません」、ほかの札は 50% に沈める
    private func homePage(_ photos: [Photo]) -> some View {
        let published = model.published
        let groups = PostPreview.homeGroups(preview: photos, published: published,
                                            neighbors: neighbors ?? [], me: auth.userId)
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

    /// マイページ: 投稿の札の行と、3列 4:5 の格子（マイページと同じ `MyPageGridCell`）。今回の投稿が先頭で、白 2pt の枠
    private func myPage(_ photos: [Photo]) -> some View {
        let grid = PostPreview.myGrid(preview: photos, mine: mine ?? [])
        let multiple = PhotoGroups.multiPhotoIds(grid)
        let previewIds = Set(photos.map(\.id))
        return ScrollView {
            VStack(spacing: 0) {
                ProfileTabBar(tabs: ProfileTab.tabs(isMe: true), selection: .constant(.posts), iconColumns: true)
                LazyVGrid(columns: ProfileV2.gridItems, spacing: ProfileV2.gridSpacing) {
                    ForEach(grid) { photo in
                        MyPageGridCell(photo: photo, multiple: multiple.contains(photo.id))
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
        let directory = PostPreview.directory()
        let sources = model.items.map { item in
            (data: item.prepared.data, thumbnail: item.prepared.thumbnail, title: item.title, caption: item.caption,
             location: item.location, takenOn: item.prepared.takenOn, color: item.prepared.dominantColor)
        }
        let items: [PostPreview.Item] = await Task.detached(priority: .userInitiated) {
            try? FileManager.default.removeItem(at: directory)
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
                                        takenOn: source.takenOn, dominantColor: source.color)
            }
        }.value
        guard !Task.isCancelled else { return }
        let profile = try? await environment.profiles.publicProfile(userId: userId)
        photos = PostPreview.photos(items, userId: userId, displayName: AuthorName.real(profile),
                                    published: model.published, audience: model.audience,
                                    grouped: model.groupsForSubmit, category: model.category,
                                    tags: TagInput.parse(model.tagsText), now: Date())
        async let feed = try? environment.gallery.fetchPhotos()
        async let own = ProfileImageFromPhoto.myPhotos(environment: environment)
        let (feedPhotos, ownPhotos) = await (feed, own)
        guard !Task.isCancelled else { return }
        neighbors = hidden.visible(feedPhotos ?? [])
        mine = ownPhotos ?? []
    }

    /// 一時ファイルを消す（端末に投稿前の写真を残さない）
    private func removeFiles() {
        try? FileManager.default.removeItem(at: PostPreview.directory())
    }
}
