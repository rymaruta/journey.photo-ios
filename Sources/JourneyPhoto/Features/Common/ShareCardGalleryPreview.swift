import SwiftUI
import UIKit
import CoreLocation

/// UI テストで共有カードの書き出し画像を全部の型 × 比で撮るための見本の画面（Debug のみ・`-JPPreviewShareCards YES`・2026-11-14）。
///
/// アプリに入っている見本の写真（`PreviewUploadSample.assetName`）を、ふつうの中身と長い中身（`Sample`）で書き出し、1枚ずつ出す。
/// 「次へ」で次の組み合わせ。ログインも通信も要らない（見本の利用者や見本の通信を使わない）。Release では出ない
struct ShareCardGalleryPreview: View {
    static let launchKey = "JPPreviewShareCards"

    static var isRequested: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: launchKey)
        #else
        return false
        #endif
    }

    struct Combo {
        let style: SignatureShareCardRenderer.Style
        let ratio: SignatureShareCardRenderer.Ratio
        let content: Sample
        var name: String { "\(style.rawValue)-\(ratioName)-\(content.rawValue)" }
        var ratioName: String {
            switch ratio {
            case .portrait: return "4x5"
            case .story: return "9x16"
            case .square: return "1x1"
            }
        }
    }

    /// 中身の見本（ふつう・長い名前と撮影地と機材）
    enum Sample: String, CaseIterable { case normal, long }

    static let combos: [Combo] = Sample.allCases.flatMap { content in
        ShareCardStyleChoice.order.flatMap { style in
            [SignatureShareCardRenderer.Ratio.portrait, .story, .square].map { Combo(style: style, ratio: $0, content: content) }
        }
    }

    static func credit(_ content: Sample) -> SignatureShareCardRenderer.Credit {
        let kyoto = CLLocationCoordinate2D(latitude: 35.0, longitude: 135.5)
        if content == .long {
            return SignatureShareCardRenderer.Credit(
                name: "写真と旅とコーヒーを愛する週末フォトグラファー山田太郎", username: "weekend_photographer_yamada_taro",
                location: "和歌山県（東牟婁郡那智勝浦町）", coords: kyoto,
                camera: "Hasselblad X2D II 100C Earth Explorer", lens: "XCD 2,8-4/35-100E Zoom Lens Ultra Wide",
                exposure: "1/4000s", aperture: "f/2.8", iso: 12800,
                verified: true, proStyle: .plate, early: true, badge: nil)
        }
        return SignatureShareCardRenderer.Credit(
            name: "旅灯", username: "tabi_akari", location: "京都府（京都市東山区）", coords: kyoto,
            camera: "Sony α7 IV", lens: "FE 24-70mm F2.8 GM II", exposure: "1/250s", aperture: "f/8", iso: 100,
            verified: true, proStyle: nil, early: false, badge: nil)
    }

    @State private var index = 0
    @State private var image: UIImage?

    private var combo: Combo { Self.combos[min(index, Self.combos.count - 1)] }

    var body: some View {
        VStack(spacing: 12) {
            Text("\(index) \(combo.name) \(image == nil ? "…" : "ready")")
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .accessibilityIdentifier("shareCardGallery.label")
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(combo.name)
                        .accessibilityIdentifier("shareCardGallery.card")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(L("次へ", "Next")) {
                image = nil
                index += 1
            }
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            .disabled(index + 1 >= Self.combos.count)
            .accessibilityIdentifier("shareCardGallery.next")
        }
        .padding(.vertical, 8)
        .background(Color.black)
        .task(id: index) {
            let combo = self.combo
            guard let photo = UIImage(named: PreviewUploadSample.assetName)?.jpegData(compressionQuality: 0.92) else { return }
            let data = await SignatureShareCardRenderer.render(photo, credit: Self.credit(combo.content),
                                                               ratio: combo.ratio, style: combo.style)
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}
