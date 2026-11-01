import SwiftUI
import UIKit

/// SNSに出す前に比率と焼き込まれる情報を確認する画面。
struct SignatureShareCardSheet: View {
    let photoData: Data
    let credit: SignatureShareCardRenderer.Credit
    let shareText: String

    @Environment(\.dismiss) private var dismiss
    @State private var ratio: SignatureShareCardRenderer.Ratio = .portrait
    @State private var output: Data?
    @State private var preparing = true
    @State private var showShare = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("共有画像の比率", selection: $ratio) {
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
                            .accessibilityLabel("SNS共有画像のプレビュー")
                    } else if preparing {
                        ProgressView("共有画像を準備しています…")
                    } else {
                        ContentUnavailableView("画像を生成できませんでした",
                                               systemImage: "photo.badge.exclamationmark",
                                               description: Text("別の比率を選ぶか、もう一度お試しください"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)

                Button {
                    showShare = true
                } label: {
                    Text("この画像を共有")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(output == nil || preparing)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(Color.black)
            .foregroundStyle(.white)
            .navigationTitle("SNSに共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task(id: ratio) {
                preparing = true
                failed = false
                output = nil
                let result = await SignatureShareCardRenderer.render(photoData, credit: credit, ratio: ratio)
                guard !Task.isCancelled else { return }
                output = result
                failed = result == nil
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
