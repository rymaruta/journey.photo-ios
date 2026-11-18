import SwiftUI
import UIKit

/// UI テストで「写真の色」の書き出し画像を、写真の形（縦長 3:4・横長 3:2・正方形）× 置き場（ストーリー・投稿 4:5・1:1）で撮るための
/// 見本の画面（Debug のみ・`-JPPreviewPhotoColor YES`・2026-11-18）。
///
/// 写真はアプリに入っている見本の1枚（`PreviewUploadSample.assetName`・利用者の写真ではない）を、その形に真ん中で切って使う。
/// ほかに、白い写真・黒い写真（明暗の比の端）と、撮影地の長い見本。字は見本の中身（兼六園・2026-10-10）。
/// ログインも通信も要らない。Release では出ない
struct PhotoColorGalleryPreview: View {
    static let launchKey = "JPPreviewPhotoColor"

    static var isRequested: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: launchKey)
        #else
        return false
        #endif
    }

    enum Shape: String, CaseIterable {
        case portrait, landscape, square
        /// 幅 ÷ 高さ
        var aspect: CGFloat {
            switch self {
            case .portrait: return 3.0 / 4.0
            case .landscape: return 3.0 / 2.0
            case .square: return 1
            }
        }
    }

    enum Target: String, CaseIterable { case story, post4x5, post1x1 }

    /// 見本の写真（アプリの見本の1枚・白・黒）と中身（ふつう・撮影地の長い見本）
    enum Sample: String { case kenrokuen, white, black, long }

    struct Combo {
        let shape: Shape
        let target: Target
        let sample: Sample
        var name: String { "\(target.rawValue)-\(shape.rawValue)-\(sample.rawValue)" }
    }

    static let combos: [Combo] = Target.allCases.flatMap { target in
        Shape.allCases.map { Combo(shape: $0, target: target, sample: .kenrokuen) }
    } + [Combo(shape: .landscape, target: .story, sample: .white),
         Combo(shape: .portrait, target: .post4x5, sample: .black),
         Combo(shape: .portrait, target: .story, sample: .long),
         Combo(shape: .square, target: .post4x5, sample: .long)]

    static let takenDay = TripBook.utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10))

    static func location(_ sample: Sample) -> String {
        switch sample {
        case .kenrokuen, .white, .black: return "兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本"
        // 最小の字でも入らない地名（一つ上の単位を大きく出す形になる）
        case .long: return "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch, Isle of Anglesey County, United Kingdom"
        }
    }

    /// 見本の写真を、形の縦横比にした JPEG（白・黒は一色の写真）
    static func photo(_ shape: Shape, sample: Sample) -> Data? {
        #if os(Linux)
        return nil   // Linux の SDK 模型には画像の描画が無い（見本は Mac の UI テストだけで使う）
        #else
        if sample == .white || sample == .black {
            let size = CGSize(width: 1200, height: (1200 / shape.aspect).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.92) { context in
                (sample == .white ? UIColor.white : UIColor.black).setFill()
                context.cgContext.fill(CGRect(origin: .zero, size: size))
            }
        }
        guard let image = UIImage(named: PreviewUploadSample.assetName), let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let crop: CGRect
        if w / h > shape.aspect {
            let cw = h * shape.aspect
            crop = CGRect(x: (w - cw) / 2, y: 0, width: cw, height: h)
        } else {
            let ch = w / shape.aspect
            crop = CGRect(x: 0, y: (h - ch) / 2, width: w, height: ch)
        }
        guard let cut = cg.cropping(to: crop.integral) else { return nil }
        return UIImage(cgImage: cut).jpegData(compressionQuality: 0.92)
        #endif
    }

    static func render(_ combo: Combo) async -> Data? {
        guard let photo = photo(combo.shape, sample: combo.sample) else { return nil }
        let location = location(combo.sample)
        switch combo.target {
        case .story:
            let facts = TravelStory.Facts(location: location, takenDay: takenDay, name: "旅灯")
            var choice = TravelStory.Choice()
            choice.kind = .photoColor
            choice.placeLevel = .city
            choice.dateLevel = .date
            return TravelStoryRenderer.render([photo], facts: facts, choice: choice)?.data
        case .post4x5, .post1x1:
            let credit = SignatureShareCardRenderer.Credit(
                name: "旅灯", username: "tabi_akari", location: LocationMatch.shareCardDisplay(location), coords: nil,
                camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
                verified: false, proStyle: nil, early: false, badge: nil,
                place: LocationMatch.shareCardPlace(location), takenDay: takenDay)
            return await SignatureShareCardRenderer.render(photo, credit: credit,
                                                           ratio: combo.target == .post4x5 ? .portrait : .square,
                                                           style: .photoColor)
        }
    }

    @State private var index = 0
    @State private var image: UIImage?

    private var combo: Combo { Self.combos[min(index, Self.combos.count - 1)] }

    var body: some View {
        VStack(spacing: 12) {
            Text("\(index) \(combo.name) \(image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "-") \(image == nil ? "…" : "ready")")
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .accessibilityIdentifier("photoColorGallery.label")
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(combo.name)
                        .accessibilityIdentifier("photoColorGallery.card")
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
            .accessibilityIdentifier("photoColorGallery.next")
        }
        .padding(.vertical, 8)
        .background(Color.black)
        .task(id: index) {
            let combo = self.combo
            let data = await Self.render(combo)
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}
