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

    @Environment(\.dismiss) private var dismiss
    @State private var ratio: SignatureShareCardRenderer.Ratio = .portrait
    @State private var output: Data?
    @State private var preparing = true
    @State private var showShare = false
    @State private var retryCount = 0
    @State private var avatarData: Data?
    @State private var avatarFetchAttempted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
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
                            Button(L("再試行", "Try again")) { retryCount += 1 }
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
            .task(id: "\(ratio.rawValue)-\(retryCount)") {
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
                    ratio: ratio, avatarData: avatarData)
                guard !Task.isCancelled else { return }
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
