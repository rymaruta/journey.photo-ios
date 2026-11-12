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
    /// 上に置く部品（「投稿 4:5 | ストーリー 9:16」の切り替え・`SocialShareSheet`・2026-11-12）
    var header: AnyView? = nil

    @Environment(\.dismiss) private var dismiss
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
    // 最大 3 比率 × 2 型のみ保持し、画面を閉じると破棄する。
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
                Picker(L("共有画像の型", "Share image style"), selection: $styleRaw) {
                    // 型の名前は短く（4つを1行の切り替えに並べる）。順は「いつもの帯」→ 写真を活かす順
                    Text(L("帯", "Band")).tag(SignatureShareCardRenderer.Style.band.rawValue)
                    Text(L("フェード", "Fade")).tag(SignatureShareCardRenderer.Style.fade.rawValue)
                    Text(L("表紙", "Cover")).tag(SignatureShareCardRenderer.Style.cover.rawValue)
                    Text(L("展示札", "Label")).tag(SignatureShareCardRenderer.Style.label.rawValue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
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
                } label: {
                    Text(L("この画像を共有", "Share this image"))
                        .frame(maxWidth: .infinity)
                }
                .webPrimaryButton()
                .disabled(output == nil || preparing)
                .accessibilityIdentifier("signatureShare.share")
                .padding(.horizontal)
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
