import SwiftUI
import UIKit
import CoreLocation

/// UI テストで共有カードの書き出し画像を全部の型 × 比で撮るための見本の画面（Debug のみ・`-JPPreviewShareCards YES`・2026-11-14）。
///
/// アプリに入っている見本の写真（`PreviewUploadSample.assetName`）を、ふつうの中身と長い中身（`Sample`）で書き出し、1枚ずつ出す。
/// 「次へ」で次の組み合わせ。ログインも通信も要らない（見本の利用者や見本の通信を使わない）。Release では出ない
struct ShareCardGalleryPreview: View {
    static let launchKey = "JPPreviewShareCards"

    /// 旅をストーリーにの「搭乗券（写真に重ねる）」だけを、写真の形ごとに出す（`-JPPreviewTravelPass YES`・2026-11-18）。
    /// 見本の写真を縦長・正方形・横長に切って書き出し、写真が切れずに収まるか・半券の置き場を絵で見る
    static let travelPassKey = "JPPreviewTravelPass"

    static var isRequested: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: launchKey) || isTravelPass
        #else
        return false
        #endif
    }

    static var isTravelPass: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: travelPassKey)
        #else
        return false
        #endif
    }

    /// 搭乗券の見本の写真の形（名前・幅 / 高さ）
    static let travelPassShapes: [(name: String, aspect: CGFloat)] = [
        ("縦長3x4", 3.0 / 4.0), ("縦長9x16", 9.0 / 16.0), ("正方形", 1), ("横長3x2", 3.0 / 2.0), ("横長16x9", 16.0 / 9.0),
    ]

    /// 見本の写真を、真ん中で `aspect` の形に切る
    nonisolated static func cropped(_ image: UIImage, aspect: CGFloat) -> Data? {
        #if os(Linux)
        return nil   // Linux の SDK 模型には CGImage の切り取りが無い（見本の画面は Mac の UI テストでだけ使う）
        #else
        guard let cg = image.cgImage else { return nil }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        var size = CGSize(width: width, height: width / aspect)
        if size.height > height { size = CGSize(width: height * aspect, height: height) }
        let rect = CGRect(x: ((width - size.width) / 2).rounded(), y: ((height - size.height) / 2).rounded(),
                          width: size.width.rounded(), height: size.height.rounded())
        return cg.cropping(to: rect).map { UIImage(cgImage: $0).jpegData(compressionQuality: 0.92) } ?? nil
        #endif
    }

    /// 搭乗券（写真に重ねる・今ここ）の見本の事実。撮った日は今日でない日（日付で出る）
    nonisolated static func travelPass(_ photo: Data) -> Data? {
        let facts = TravelStory.Facts(location: "輪島市, 石川県, 日本", takenDay: Date(timeIntervalSince1970: 1_793_664_000),
                                      name: "旅灯",
                                      trip: TravelStory.TripFacts(photoCount: 12, distanceKm: 84, days: 3, leadDay: 2))
        var choice = TravelStory.Choice()
        choice.kind = .pass
        choice.mode = .photo
        choice.phase = .now
        return TravelStoryRenderer.render([photo], facts: facts, choice: choice)?.data
    }

    private var count: Int { Self.isTravelPass ? Self.travelPassShapes.count : Self.combos.count }
    private var itemName: String {
        Self.isTravelPass ? "搭乗券-\(Self.travelPassShapes[min(index, count - 1)].name)" : combo.name
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
            Text("\(index) \(itemName) \(image == nil ? "…" : "ready")")
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .accessibilityIdentifier("shareCardGallery.label")
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(itemName)
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
            .disabled(index + 1 >= count)
            .accessibilityIdentifier("shareCardGallery.next")
        }
        .padding(.vertical, 8)
        .background(Color.black)
        .task(id: index) {
            if Self.isTravelPass {
                let aspect = Self.travelPassShapes[min(index, count - 1)].aspect
                guard let sample = UIImage(named: PreviewUploadSample.assetName) else { return }
                let data = await Task.detached(priority: .userInitiated) {
                    Self.cropped(sample, aspect: aspect).flatMap(Self.travelPass)
                }.value
                guard !Task.isCancelled else { return }
                image = data.flatMap(UIImage.init(data:))
                return
            }
            let combo = self.combo
            guard let photo = UIImage(named: PreviewUploadSample.assetName)?.jpegData(compressionQuality: 0.92) else { return }
            let data = await SignatureShareCardRenderer.render(photo, credit: Self.credit(combo.content),
                                                               ratio: combo.ratio, style: combo.style)
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}
