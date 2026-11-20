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
        /// 保存できた写真（雑誌の Vol. の番号を数えるとき、まだ自分の一覧に無ければ足す・`MagazineCard.volume`）
        var photo: Photo? = nil
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter
    /// 自分の写真の一覧（雑誌の Vol. の番号を数える・`MagazineVolume`）
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
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
        ShareCardStyleChoice.style(rawValue: styleRaw, for: credit)
    }

    /// 撮った日を絵に出すか（「日付」の入切・`ShareCardDateChoice`）。型をまたいで覚える
    @State private var showsDate = ShareCardDateChoice.load()
    /// 雑誌の Vol. の番号（自分の何番目の投稿か）。読み終えるまで雑誌は描かない（番号が後から足されて絵が変わらないように）。
    /// 分からなければ nil のまま（「Vol.」を出さない）
    @State private var volume: Int?
    @State private var volumeLoaded = false
    /// 見本の中身（入切だけを写す。Vol. の番号は付けない）
    private var thumbnailCredit: SignatureShareCardRenderer.Credit {
        ShareCardDateChoice.credit(credit, showsDate: showsDate)
    }
    /// 描くときの中身（入切と Vol. を写したもの）
    private var drawnCredit: SignatureShareCardRenderer.Credit {
        var drawn = ShareCardDateChoice.credit(credit, showsDate: showsDate)
        drawn.volume = volume
        return drawn
    }

    /// 作った画像の置き場所の鍵（比率と型と日付の入切の組）
    private struct CardKey: Hashable {
        let ratio: SignatureShareCardRenderer.Ratio
        let style: SignatureShareCardRenderer.Style
        var showsDate = true
        /// 雑誌の Vol. の番号（雑誌のときだけ・ほかの型は nil にそろえる）
        var volume: Int? = nil
    }
    @State private var output: Data?
    // 同じ共有画面内で比率を戻したときはJPEGの再生成を避ける。
    // 最大 3 比率 × 7 型のみ保持し、画面を閉じると破棄する。
    @State private var renderedByKey: [CardKey: Data] = [:]
    @State private var preparing = true
    @State private var showShare = false
    @State private var copiedImage = false
    @State private var retryCount = 0
    @State private var avatarData: Data?
    @State private var avatarFetchAttempted = false
    /// 型の小さな見本（自分の写真で作った 4:5・型の名前ごと）。開いたプレビューができてから、後ろで順に作る
    @State private var thumbnails: [String: UIImage] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let header { header }
                if posted != nil { postedHeader }
                // 型は横に流れる小さな見本の並び（2026-11-14 判断・owner「更にブラッシュアップさせたいな」）。
                // 前は名前だけのチップで、押すまで形が分からなかった（10 の型）。いまは自分の写真で作った各型の 4:5 の見本に名前を添える
                // （インスタのフィルターの並びと同じ形）。押す回数は前と同じ1回。既定は帯のまま
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: JPSpace.xs) {
                            ForEach(ShareCardStyleChoice.order(for: credit), id: \.rawValue) { option in
                                ShareCardStyleTile(title: ShareCardStyleChoice.title(option),
                                                   image: thumbnails[option.rawValue],
                                                   selected: style == option) {
                                    styleRaw = option.rawValue
                                }
                                .id(option.rawValue)
                                .accessibilityIdentifier("signatureShare.style.\(option.rawValue)")
                            }
                        }
                        .padding(.horizontal)
                    }
                    // 前に選んだ型が並びの外（後ろの方）にあっても、開いたときに見えるようにする
                    .onAppear { reader.scrollTo(style.rawValue, anchor: .center) }
                }
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

                // 日付を描く型（暦・雑誌）を選んでいるときだけ、日付の入切を1つ（2026-11-18 判断・`ShareCardDateChoice`）
                if ShareCardDateChoice.showsToggle(style: style, credit: credit) {
                    JPToggleRow(title: ShareCardDateChoice.label, isOn: $showsDate)
                        .padding(.horizontal)
                        .accessibilityIdentifier("signatureShare.date")
                }

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
                                renderedByKey.removeValue(forKey: CardKey(ratio: ratio, style: style,
                                    showsDate: ShareCardDateChoice.drawsDate(style) ? showsDate : true,
                                    volume: style == .magazine ? volume : nil))
                                retryCount += 1
                            }
                                .accessibilityIdentifier("signatureShare.retry")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
                .accessibilityIdentifier("signatureShare.preview")

                // Copy the exact JPEG bytes, not a UIImage re-encoded by the share sheet.
                // This avoids mixing the caption and image in a single paste operation.
                Button {
                    guard let output else { return }
                    UIPasteboard.general.setItems(
                        [["public.jpeg": output]],
                        options: [.localOnly: true,
                                  .expirationDate: Date().addingTimeInterval(600)])
                    copiedImage = true
                } label: {
                    Text(copiedImage ? L("画像をコピーしました", "Image copied") :
                         L("画像をコピー（SNSに貼り付け）", "Copy image for social apps"))
                        .frame(maxWidth: .infinity)
                }
                .disabled(output == nil || preparing)
                .accessibilityIdentifier("signatureShare.copyImage")
                .padding(.horizontal)

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
            .onChange(of: showsDate) { _, newValue in
                ShareCardDateChoice.save(newValue)
                // 日付を描く型の見本は作り直す（2026-11-18 確かめ役: 入切を替えても見本が古いままだった）
                for option in ShareCardStyleChoice.order where ShareCardDateChoice.drawsDate(option) {
                    thumbnails.removeValue(forKey: option.rawValue)
                }
            }
            .task(id: style == .magazine) {
                // 雑誌の Vol. の番号。**雑誌を選んだときだけ**自分の写真の一覧を読む（2026-11-19 まとめ役の判断・
                // 読んだ一覧はアプリを使っている間だけ覚える `MagazineVolume.Memo`）。上限の時間を過ぎたら出さない
                guard style == .magazine, !volumeLoaded else { return }
                volume = await MagazineVolume.load(photoId: credit.photoId, justPosted: posted?.photo,
                                                   owner: auth.userId, photos: environment.photos)
                volumeLoaded = true
            }
            // 番号を読み終えたことで描き直すのは雑誌のときだけ（ほかの型は描き直さない）
            .task(id: "\(ratio.rawValue)-\(styleRaw)-\(showsDate)-\(retryCount)" + (style == .magazine ? "-\(volumeLoaded)" : "")) {
                let selectedRatio = ratio
                let selectedStyle = style
                // 雑誌は Vol. の番号を読み終えてから描く（読み終えたら task がもう一度来る）
                if selectedStyle == .magazine, !volumeLoaded {
                    preparing = true
                    output = nil
                    return
                }
                // 日付を描かない型では入切で描き直さない（鍵をそろえる）
                let dated = ShareCardDateChoice.drawsDate(selectedStyle) ? showsDate : true
                let key = CardKey(ratio: selectedRatio, style: selectedStyle, showsDate: dated,
                                  volume: selectedStyle == .magazine ? volume : nil)
                if let cached = renderedByKey[key] {
                    output = cached
                    preparing = false
                    return
                }
                preparing = true
                output = nil
                copiedImage = false
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
                let result = await SignatureShareCardRenderer.render(photoData, credit: drawnCredit,
                    ratio: selectedRatio, style: selectedStyle, avatarData: avatarData)
                guard !Task.isCancelled else { return }
                if let result { renderedByKey[key] = result }
                output = result
                preparing = false
            }
            .task(id: showsDate) {
                // 見本は 4:5・顔なしで。先に今のプレビューを作らせ（最大 3 秒待つ）、見本は後ろで1つずつ（144×180 に縮めて持つ）
                for _ in 0..<30 where preparing {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                for option in ShareCardStyleChoice.order(for: credit) where thumbnails[option.rawValue] == nil {
                    if Task.isCancelled { return }
                    // 見本は Vol. の番号なしで描く（番号のために一覧を読まない・2026-11-19 まとめ役の判断）
                    guard let data = await SignatureShareCardRenderer.render(photoData, credit: thumbnailCredit,
                                                                             ratio: .portrait, style: option),
                          let image = UIImage(data: data)?.preparingThumbnail(of: ShareCardStyleTile.pixelSize)
                    else { continue }
                    thumbnails[option.rawValue] = image
                }
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
    /// 確かめは出さない（閉じれば何も起きない・CLAUDE.md「聞くのは最小に」）。
    /// 2026-11-14: 大きい文字で2つが横に収まらなければ縦に積む（板 06「大きい文字」・字を「…」で切らない）。
    /// 縦に積んでも1行に収まらない大きさ（AX5 の「ストーリーに載せる」・Mac run 1273 の 120e2）は字を少し縮める
    func postedActions(_ posted: Posted) -> some View {
        VStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { postedShareButtons(posted) }
                VStack(spacing: 8) { postedShareButtons(posted) }
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

    /// 「ストーリーに載せる」と「リンクをコピー」。ストーリーの絵を作っている間は、字の代わりに回る印を出す
    /// （押した手ごたえ・二度押しを受けない・板 06「送っている間は印を出す」）
    @ViewBuilder
    func postedShareButtons(_ posted: Posted) -> some View {
        Button { Task { await prepareStory(posted) } } label: {
            ZStack {
                Text(SendSheetLayout.storyLabel)
                    .opacity(preparingStory ? 0 : 1)
                if preparingStory {
                    ProgressView()
                        .tint(WebTheme.text)
                        .accessibilityHidden(true)
                }
            }
            .minimumScaleFactor(0.7)
            .jpOutlineButton(fullWidth: true)
        }
        .buttonStyle(.plain)
        .disabled(preparingStory)
        .accessibilityLabel(SendSheetLayout.storyLabel)
        .accessibilityValue(preparingStory ? L("準備しています", "Preparing") : "")
        .accessibilityIdentifier("postedCard.story")
        if let link = posted.link {
            Button {
                UIPasteboard.general.string = link.absoluteString
                didShare = true
                toasts.show(L("リンクをコピーしました", "Link copied"))
            } label: {
                Text(L("リンクをコピー", "Copy link"))
                    .minimumScaleFactor(0.7)
                    .jpOutlineButton(fullWidth: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("postedCard.copyLink")
        }
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

/// 共有画像の型の並びと名前（2026-11-14・試験で見る）。名前は短く（チップに1語）。
/// 2026-11-18: 暦（`KoyomiCard`）を後ろに足した（前からの並びは変えない）。続けて雑誌（`MagazineCard`）を後ろに足した
enum ShareCardStyleChoice {
    static let order: [SignatureShareCardRenderer.Style] = [.band, .fade, .cover, .label, .printed, .ticket, .cinema,
                                                            .mat, .film, .tanzaku, .koyomi, .photoColor, .magazine]

    /// その写真で選べる型。**撮った日の分からない写真では暦を外す**（日付も節気も出せない・2026-11-18 判断）
    static func order(for credit: SignatureShareCardRenderer.Credit) -> [SignatureShareCardRenderer.Style] {
        order.filter { $0 != .koyomi || credit.takenDay != nil }
    }

    /// 前に選んだ型が、この写真で選べなければ既定の帯
    static func style(rawValue: String, for credit: SignatureShareCardRenderer.Credit) -> SignatureShareCardRenderer.Style {
        guard let style = SignatureShareCardRenderer.Style(rawValue: rawValue), order(for: credit).contains(style) else {
            return .band
        }
        return style
    }

    static func title(_ style: SignatureShareCardRenderer.Style) -> String {
        switch style {
        case .band: return L("帯", "Band")
        case .fade: return L("フェード", "Fade")
        case .cover: return L("表紙", "Cover")
        case .label: return L("展示札", "Label")
        case .printed: return L("プリント", "Print")
        case .ticket: return L("切符", "Ticket")
        case .cinema: return L("シネマ", "Cinema")
        case .mat: return L("額装", "Mat")
        case .film: return L("フィルム", "Film")
        case .tanzaku: return L("縦書き", "Vertical")
        case .koyomi: return L("暦", "Almanac")
        case .photoColor: return L("写真の色", "Photo color")
        case .magazine: return L("雑誌", "Magazine")
        }
    }
}

/// 共有画像の「日付」の入切（2026-11-18 判断・まとめ役）。
///
/// 写真の詳細はわざと撮影日を出していない（`PhotoDetailView` の撮影情報）。暦の型は撮った日（と、日付の手がかりになる
/// 二十四節気）を描くので、撮った日が外に出る道がここで初めてできる。そこで:
/// - **既定は出す**（暦の型の主役なので。設定を入口にしない）
/// - **日付を描く型を選んでいて、撮った日のある写真のときだけ**、プレビューの近くに入切を1つ出す（押す回数1・
///   ストーリーの `TravelStory.DateLevel` と同じ考え方）
/// - 切ったら暦は日付も節気も出さない（`KoyomiCard.texts` の「日付を出さない」の決まり）
/// - 入切は型をまたいで端末に覚える（後から足す日付を描く型も `drawsDate` に足せば同じ入切を使う）
enum ShareCardDateChoice {
    static let defaultsKey = "signatureShare.showsDate"

    /// 日付を描く型（暦・写真の色・雑誌。2026-11-18: 写真の色と雑誌も同じ入切を使う）
    static func drawsDate(_ style: SignatureShareCardRenderer.Style) -> Bool {
        style == .koyomi || style == .photoColor || style == .magazine
    }

    /// 入切を出すか（日付を描く型で、撮った日のある写真）
    static func showsToggle(style: SignatureShareCardRenderer.Style, credit: SignatureShareCardRenderer.Credit) -> Bool {
        drawsDate(style) && credit.takenDay != nil
    }

    /// 覚えた入切（初めては出す）
    static func load(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) == nil ? true : defaults.bool(forKey: defaultsKey)
    }

    static func save(_ showsDate: Bool, defaults: UserDefaults = .standard) {
        defaults.set(showsDate, forKey: defaultsKey)
    }

    /// 描くときに渡す中身（入切を写す）
    static func credit(_ credit: SignatureShareCardRenderer.Credit, showsDate: Bool) -> SignatureShareCardRenderer.Credit {
        var copy = credit
        copy.showsDate = showsDate
        return copy
    }

    static var label: String { L("日付", "Date") }
}

/// 共有画像の型の小さな見本（2026-11-14 判断）。自分の写真で作った 4:5 の見本と名前。
/// 選んだものは真鍮の輪とチェックと太字（色だけに頼らない・owner の好み「選んでいるものは真鍮」）。押せる所は 44 以上
struct ShareCardStyleTile: View {
    let title: String
    let image: UIImage?
    let selected: Bool
    let action: () -> Void

    /// 見本の大きさ（4:5）
    static let size = CGSize(width: 48, height: 60)
    /// 見本の画像を縮めて持つ画素の大きさ（3 倍の画面でも粗くならない）
    static let pixelSize = CGSize(width: 144, height: 180)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(WebTheme.card)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? WebTheme.accent : WebTheme.hairline, lineWidth: selected ? 2 : 1)
                )
                .padding(3)
                HStack(spacing: 2) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(JPFont.caption.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(selected ? WebTheme.accent : WebTheme.text2)
            }
            .frame(minWidth: 60, minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
