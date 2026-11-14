import SwiftUI
import UIKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// SNSに出す前に比率と焼き込まれる情報を確認する画面。
struct SignatureShareCardSheet: View {
    let photoData: Data
    let credit: SignatureShareCardRenderer.Credit
    let shareText: String
    let avatarURL: URL?
    /// 上に置く部品（「投稿 | ストーリー」の切り替え・`SocialShareSheet`・2026-11-12）
    var header: AnyView? = nil
    /// 投稿の完了で出すとき（1.1.83・資料「SNS をもっと SNS に」①・`PostedShareCard`）。nil なら写真の詳細の ⋯ から
    var posted: Posted? = nil

    /// 投稿の完了で出すときの足し。頭に「投稿しました」、下に「ストーリーに載せる」「リンクをコピー」「閉じる」
    struct Posted {
        let photoId: String
        /// 写真の短縮リンク（「リンクをコピー」）
        let link: URL?
        /// ストーリーの札に描く題（`SharedPhotoStoryCard.titleLine`）
        let storyTitle: String
        /// 閉じたとき（そこで共有したか・`PostedCardHabit`）
        var onFinish: ((Bool) -> Void)? = nil
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter
    /// 「ストーリーに載せる」で開く作る画面（写真の詳細の「送る」と同じ `StoryComposerView(sharing:)`）
    @State private var storySeed: StoryShareSeed?
    @State private var preparingStory = false
    /// この画面で共有したか（カードを共有・ストーリーに載せる・リンクをコピー）。閉じたときに `Posted.onFinish` へ
    @State private var didShare = false
    @State private var ratio: SignatureShareCardRenderer.Ratio = .portrait
    /// カードの型（帯／フェード）。前に選んだものを次も使う（2026-11-05 owner「ユーザが選べるように」）
    /// 2026-11-05: `@AppStorage` は使わない（Linux の SwiftUI 模型に無く、他の画面も UserDefaults を直に読む）
    private static let styleDefaultsKey = "signatureShare.style"
    @State private var styleRaw = UserDefaults.standard.string(forKey: SignatureShareCardSheet.styleDefaultsKey)
        ?? SignatureShareCardRenderer.Style.band.rawValue
    private var style: SignatureShareCardRenderer.Style {
        SignatureShareCardRenderer.Style(rawValue: styleRaw) ?? .band
    }

    /// 作った画像の置き場所の鍵（比率と型の組）
    private struct CardKey: Hashable {
        let ratio: SignatureShareCardRenderer.Ratio
        let style: SignatureShareCardRenderer.Style
    }
    @State private var output: Data?
    // 同じ共有画面内で比率を戻したときはJPEGの再生成を避ける。
    // 最大 3 比率 × 7 型のみ保持し、画面を閉じると破棄する。
    @State private var renderedByKey: [CardKey: Data] = [:]
    @State private var preparing = true
    @State private var showShare = false
    @State private var retryCount = 0
    @State private var avatarData: Data?
    @State private var avatarFetchAttempted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let header { header }
                if posted != nil { postedHeader }
                // 型は横に流れるチップの並び（2026-11-14: 7つになり、1行の切り替えには入らない）。
                // 押す回数は前と同じ1回。順は「いつもの帯」→ 写真を活かす順 → 新しい3つ（`ShareCardStyleChoice.order`）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JPSpace.xs) {
                        ForEach(ShareCardStyleChoice.order, id: \.rawValue) { option in
                            PillChip(title: ShareCardStyleChoice.title(option), selected: style == option) {
                                styleRaw = option.rawValue
                            }
                            .accessibilityIdentifier("signatureShare.style.\(option.rawValue)")
                        }
                    }
                    .padding(.horizontal)
                }
                // 札の押せる余白（上下 5）の分だけ詰め、並びの見た目の間隔は前のまま
                .padding(.vertical, -PillChip.tapSlack)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L("共有画像の型", "Share image style"))
                .accessibilityIdentifier("signatureShare.style")

                Picker(L("共有画像の比率", "Share image ratio"), selection: $ratio) {
                    Text("4:5").tag(SignatureShareCardRenderer.Ratio.portrait)
                    Text("9:16").tag(SignatureShareCardRenderer.Ratio.story)
                    Text("1:1").tag(SignatureShareCardRenderer.Ratio.square)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    if let output, let image = UIImage(data: output) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(L("SNS共有画像のプレビュー", "Social share image preview"))
                    } else if preparing {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(L("共有画像を準備しています…", "Preparing image…"))
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                            Text(L("画像を生成できませんでした", "Could not create image"))
                            Text(L("別の比率を選ぶか、もう一度お試しください", "Choose another ratio or try again"))
                            Button(L("再試行", "Try again")) {
                                renderedByKey.removeValue(forKey: CardKey(ratio: ratio, style: style))
                                retryCount += 1
                            }
                                .accessibilityIdentifier("signatureShare.retry")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
                .accessibilityIdentifier("signatureShare.preview")

                Button {
                    showShare = true
                    didShare = true
                } label: {
                    Text(posted == nil ? L("この画像を共有", "Share this image") : L("カードを共有", "Share card"))
                        .frame(maxWidth: .infinity)
                }
                .webPrimaryButton()
                .disabled(output == nil || preparing)
                .accessibilityIdentifier("signatureShare.share")
                .padding(.horizontal)
                .padding(.bottom, posted == nil ? 16 : 0)
                if let posted { postedActions(posted) }
            }
            .background(Color.black)
            .foregroundStyle(.white)
            .navigationTitle(posted == nil ? L("SNSに共有", "Share to social media") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 投稿の完了では「閉じる」は下に置く（資料の模型・頭は「投稿しました」の見出し）
                if posted == nil {
                    // 閉じるは左上（2026-11-13 owner 承認・#187・右上は決める操作だけ）
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                }
            }
            .toolbar(posted == nil ? .visible : .hidden, for: .navigationBar)
            .fullScreenCover(item: $storySeed) { seed in
                NavigationStack { StoryComposerView(sharing: seed) }
            }
            .onDisappear { posted?.onFinish?(didShare) }
            .onChange(of: styleRaw) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: Self.styleDefaultsKey)
            }
            .task(id: "\(ratio.rawValue)-\(styleRaw)-\(retryCount)") {
                let selectedRatio = ratio
                let selectedStyle = style
                let key = CardKey(ratio: selectedRatio, style: selectedStyle)
                if let cached = renderedByKey[key] {
                    output = cached
                    preparing = false
                    return
                }
                preparing = true
                output = nil
                if !avatarFetchAttempted, let avatarURL, !Task.isCancelled {
                    avatarFetchAttempted = true
                    var request = URLRequest(url: avatarURL)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    request.timeoutInterval = 4
                    if let (data, response) = try? await URLSession.shared.data(for: request),
                       let response = response as? HTTPURLResponse,
                       (200..<300).contains(response.statusCode),
                       data.count < 5_000_000, UIImage(data: data) != nil {
                        avatarData = data
                    }
                }
                let result = await SignatureShareCardRenderer.render(photoData, credit: credit,
                    ratio: selectedRatio, style: selectedStyle, avatarData: avatarData)
                guard !Task.isCancelled else { return }
                if let result { renderedByKey[key] = result }
                output = result
                preparing = false
            }
            .sheet(isPresented: $showShare) {
                if let output {
                    ShareSheet(images: [output], text: shareText)
                        .ignoresSafeArea()
                }
            }
        }
    }
}

// MARK: - 投稿の完了（1.1.83・資料「SNS をもっと SNS に」①・2026-11-12）

extension SignatureShareCardSheet {

    /// 頭: 真鍮の眉「投稿しました」（黒地の上の合図）と明朝の一行「カードにして、ほかの SNS にも」
    var postedHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PostedShareCardText.eyebrow)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(PostedShareCardText.title)
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("postedCard.header")
    }

    /// 下: 「ストーリーに載せる」「リンクをコピー」（線の副ボタン 44 を2つ並べる）と「閉じる」（文字のボタン）。
    /// 確かめは出さない（閉じれば何も起きない・CLAUDE.md「聞くのは最小に」）
    func postedActions(_ posted: Posted) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button { Task { await prepareStory(posted) } } label: {
                    Text(SendSheetLayout.storyLabel)
                        .jpOutlineButton(fullWidth: true)
                }
                .buttonStyle(.plain)
                .disabled(preparingStory)
                .accessibilityIdentifier("postedCard.story")
                if let link = posted.link {
                    Button {
                        UIPasteboard.general.string = link.absoluteString
                        didShare = true
                        toasts.show(L("リンクをコピーしました", "Link copied"))
                    } label: {
                        Text(L("リンクをコピー", "Copy link"))
                            .jpOutlineButton(fullWidth: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("postedCard.copyLink")
                }
            }
            Button(L("閉じる", "Close")) { dismiss() }
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.text2)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("postedCard.close")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// 写真を札にしたストーリーの絵を作り、作る画面を開く（写真の詳細の `prepareStory` と同じ絵・`SharedPhotoStoryCard`）。
    /// 写真は投稿に使った絵（手元にある）なので読み直さない。顔はカードのために読んだものを使う
    func prepareStory(_ posted: Posted) async {
        guard !preparingStory else { return }
        preparingStory = true
        defer { preparingStory = false }
        let raw = photoData
        let face = avatarData
        let handle = SharedPhotoStoryCard.handleLine(username: credit.username, displayName: credit.name)
        let title = posted.storyTitle
        let card = await Task.detached(priority: .userInitiated) {
            SharedPhotoStoryCard.render(photo: raw, avatar: face, handle: handle, title: title)
        }.value
        guard let card else {
            toasts.show(L("ストーリーの絵を作れませんでした", "Couldn't make the story image"), kind: .failure)
            return
        }
        didShare = true
        storySeed = StoryShareSeed(photoId: posted.photoId, cardData: card)
    }
}

/// 投稿の完了のカードの言葉（試験で見る）
enum PostedShareCardText {
    static var eyebrow: String { L("投稿しました", "Posted") }
    static var title: String { L("カードにして、ほかの SNS にも", "Turn it into a card for other social apps") }
}

/// 共有画像の型の並びと名前（2026-11-14・試験で見る）。名前は短く（チップに1語）
enum ShareCardStyleChoice {
    static let order: [SignatureShareCardRenderer.Style] = [.band, .fade, .cover, .label, .printed, .ticket, .cinema]

    static func title(_ style: SignatureShareCardRenderer.Style) -> String {
        switch style {
        case .band: return L("帯", "Band")
        case .fade: return L("フェード", "Fade")
        case .cover: return L("表紙", "Cover")
        case .label: return L("展示札", "Label")
        case .printed: return L("プリント", "Print")
        case .ticket: return L("切符", "Ticket")
        case .cinema: return L("シネマ", "Cinema")
        }
    }
}
