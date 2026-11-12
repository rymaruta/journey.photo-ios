import SwiftUI
import UIKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// SNSに出す前に比率と焼き込まれる情報を確認する画面。
///
/// 2026-11-12 第8章（型を横に払って選ぶ）: 型が 6 つ（表紙・縦書き・インスタント・フェード・帯・展示札）になり、
/// 1行の分割の切り替えでは字が窮屈になるので、**見本を横に払うか、下の見本の列（絵と名前）を押して選ぶ**。
/// 押す回数は今と同じ（写真の「…」→「SNS に載せる」→「この画像を共有」＝3、型を変えて 4）。
/// 比率は「投稿 4:5・ストーリー 9:16・正方形 1:1」と、どこに貼るかの言葉を足す（押す前に分かる）。
struct SignatureShareCardSheet: View {
    let photoData: Data
    let credit: SignatureShareCardRenderer.Credit
    let shareText: String
    let avatarURL: URL?

    typealias Style = SignatureShareCardRenderer.Style
    typealias Ratio = SignatureShareCardRenderer.Ratio

    @Environment(\.dismiss) private var dismiss
    @State private var ratio: Ratio = .portrait
    /// カードの型。前に選んだものを次も使う（2026-11-05 owner「ユーザが選べるように」）。初めての人は「縦書き」（`Style.firstChoice`）
    /// 2026-11-05: `@AppStorage` は使わない（Linux の SwiftUI 模型に無く、他の画面も UserDefaults を直に読む）
    static let styleDefaultsKey = "signatureShare.style"
    @State private var styleRaw = SignatureShareCardSheet.initialStyle(
        stored: UserDefaults.standard.string(forKey: SignatureShareCardSheet.styleDefaultsKey)).rawValue
    private var style: Style { Style(rawValue: styleRaw) ?? Style.firstChoice }

    /// 開いたときの型。前に使った型（読めない値なら初めての人と同じ）
    nonisolated static func initialStyle(stored: String?) -> Style {
        stored.flatMap(Style.init(rawValue:)) ?? Style.firstChoice
    }

    /// 見本を払ったとき・読み上げで「次へ」としたときの型（端で反対の端へ回る）
    nonisolated static func neighbor(of style: Style, step: Int) -> Style {
        let order = Style.pickerOrder
        let index = order.firstIndex(of: style) ?? 0
        return order[((index + step) % order.count + order.count) % order.count]
    }

    /// 型の名前（見本の列の下の1行）
    nonisolated static func name(_ style: Style) -> String {
        switch style {
        case .band: return L("帯", "Band")
        case .fade: return L("フェード", "Fade")
        case .cover: return L("表紙", "Cover")
        case .label: return L("展示札", "Label")
        case .tate: return L("縦書き", "Vertical")
        case .instant: return L("インスタント", "Instant")
        }
    }

    /// 比率の言葉（どこに貼るか）と数
    nonisolated static func ratioLabel(_ ratio: Ratio) -> (place: String, value: String) {
        switch ratio {
        case .portrait: return (L("投稿", "Post"), "4:5")
        case .story: return (L("ストーリー", "Story"), "9:16")
        case .square: return (L("正方形", "Square"), "1:1")
        }
    }

    /// 払って型を替える距離（これより短い払いは替えない）
    nonisolated static let swipeThreshold: CGFloat = 40
    /// 見本の列の絵の幅（4:5 で 52×65）。書き出す画素は 3 倍
    nonisolated static let thumbnailWidth: CGFloat = 52

    /// 作った画像の置き場所の鍵（比率と型の組）
    private struct CardKey: Hashable {
        let ratio: Ratio
        let style: Style
    }
    @State private var output: Data?
    // 同じ共有画面内で比率・型を戻したときはJPEGの再生成を避ける。画面を閉じると破棄する。
    @State private var renderedByKey: [CardKey: Data] = [:]
    @State private var thumbnails: [Style: UIImage] = [:]
    @State private var preparing = true
    @State private var showShare = false
    @State private var retryCount = 0
    @State private var avatarData: Data?
    @State private var avatarFetchAttempted = false
    @State private var dragOffset: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                    .padding(.top, 10)
                styleStrip
                ratioRow
                Button {
                    showShare = true
                } label: {
                    Text(L("この画像を共有", "Share this image"))
                        .frame(maxWidth: .infinity)
                }
                .webPrimaryButton()
                .disabled(output == nil || preparing)
                .accessibilityIdentifier("signatureShare.share")
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .background(Color.black)
            .foregroundStyle(.white)
            .navigationTitle(L("SNSに共有", "Share to social media"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("閉じる", "Close")) { dismiss() }
                }
            }
            .onChange(of: styleRaw) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: Self.styleDefaultsKey)
            }
            .task(id: "\(ratio.rawValue)-\(styleRaw)-\(retryCount)") {
                await renderSelected()
            }
            // 見本の列の小さな絵（1080 で 6 枚作ると重いので、幅 156 の画素で描く）
            .task { await renderThumbnails() }
            .sheet(isPresented: $showShare) {
                if let output {
                    ShareSheet(images: [output], text: shareText)
                        .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - 見本（横に払うと型が変わる）

    private var preview: some View {
        Group {
            if let output, let image = UIImage(data: output) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .offset(x: dragOffset)
                    .opacity(1 - min(0.5, abs(dragOffset) / 400))
                    .accessibilityLabel(L("SNS共有画像のプレビュー", "Social share image preview"))
                    .accessibilityValue(Self.name(style))
                    .accessibilityHint(L("左右に払うと型が変わります", "Swipe left or right to change the style"))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: select(Self.neighbor(of: style, step: 1))
                        case .decrement: select(Self.neighbor(of: style, step: -1))
                        @unknown default: break
                        }
                    }
            } else if preparing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L("共有画像を準備しています…", "Preparing image…"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text(L("画像を生成できませんでした", "Could not create image"))
                    Text(L("別の型か比率を選ぶか、もう一度お試しください", "Choose another style or ratio, or try again"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                    Button(L("再試行", "Try again")) {
                        renderedByKey.removeValue(forKey: CardKey(ratio: ratio, style: style))
                        retryCount += 1
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("signatureShare.retry")
                }
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in dragOffset = Double(value.translation.width) }
                .onEnded { value in
                    if abs(value.translation.width) > Self.swipeThreshold {
                        select(Self.neighbor(of: style, step: value.translation.width < 0 ? 1 : -1))
                    }
                    withAnimation(.easeOut(duration: 0.22)) { dragOffset = 0 }
                }
        )
        .accessibilityIdentifier("signatureShare.preview")
    }

    // MARK: - 見本の列（絵で選ぶ・名前は下に1行）

    private var styleStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Style.pickerOrder, id: \.self) { item in
                        styleButton(item)
                            .id(item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
            .onAppear { proxy.scrollTo(style, anchor: .center) }
            .onChange(of: styleRaw) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(style, anchor: .center) }
            }
        }
        .accessibilityIdentifier("signatureShare.style")
    }

    private func styleButton(_ item: Style) -> some View {
        let selected = item == style
        let width = Self.thumbnailWidth
        let height = width / CGFloat(Ratio.portrait.rawValue)
        return Button { select(item) } label: {
            VStack(spacing: 5) {
                Group {
                    if let image = thumbnails[item] {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        WebTheme.surface
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(WebTheme.border, lineWidth: 1))
                // 今いる型は真鍮の輪（黒の 2 を空けて 2 の輪・owner の好み「選んでいる所は真鍮」）
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(WebTheme.accent, lineWidth: 2)
                        .padding(-3)
                        .opacity(selected ? 1 : 0)
                )
                Text(Self.name(item))
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? WebTheme.accent : WebTheme.text2)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 60, minHeight: 44)
            .padding(.top, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("signatureShare.style.\(item.rawValue)")
    }

    // MARK: - 比率（どこに貼るか）

    private var ratioRow: some View {
        HStack(spacing: 6) {
            ForEach([Ratio.portrait, .story, .square], id: \.self) { item in
                let selected = item == ratio
                let label = Self.ratioLabel(item)
                Button { ratio = item } label: {
                    VStack(spacing: 1) {
                        Text(label.place)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.text)
                        Text(label.value)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.text3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(selected ? WebTheme.accentBackground : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? Color.clear : WebTheme.line, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label.place) \(label.value)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("signatureShare.ratio.\(label.value)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    // MARK: - 描く

    private func select(_ item: Style) {
        guard item != style else { return }
        styleRaw = item.rawValue
    }

    private func renderSelected() async {
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

    private func renderThumbnails() async {
        for item in Style.pickerOrder where thumbnails[item] == nil {
            guard !Task.isCancelled else { return }
            if let data = await SignatureShareCardRenderer.render(photoData, credit: credit, ratio: .portrait,
                                                                 style: item, outputWidth: Self.thumbnailWidth * 3),
               let image = UIImage(data: data) {
                thumbnails[item] = image
            }
        }
    }
}
