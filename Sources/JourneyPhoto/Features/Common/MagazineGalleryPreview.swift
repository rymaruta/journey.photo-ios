import SwiftUI
import UIKit
import CoreLocation

/// UI テストで「雑誌」の書き出し画像を、写真の形（縦長 3:4・横長 3:2・正方形）× 置き場（ストーリー・投稿 4:5・1:1）と、
/// 全面に敷く形（4:5 の写真を投稿 4:5 に・9:16 の写真をストーリーに）・長い題・日付と Vol. の無い見本で撮るための
/// 見本の画面（Debug のみ・`-JPPreviewMagazine YES`・2026-11-18）。
///
/// 写真はアプリに入っている見本の1枚（`PreviewUploadSample.assetName`・利用者の写真ではない）を、その形に真ん中で切って使う
/// （`KoyomiGalleryPreview.photo` と同じ切り方）。字は見本の中身（兼六園・題・撮影の値・Vol. 12）。ログインも通信も要らない。
/// Release では出ない
struct MagazineGalleryPreview: View {
    static let launchKey = "JPPreviewMagazine"

    static var isRequested: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: launchKey)
        #else
        return false
        #endif
    }

    enum Shape: String, CaseIterable {
        case portrait, landscape, square
        /// 全面に敷く見本（投稿 4:5 に 4:5、ストーリーに 9:16）
        case fourFive, nineSixteen
        var aspect: CGFloat {
            switch self {
            case .portrait: return 3.0 / 4.0
            case .landscape: return 3.0 / 2.0
            case .square: return 1
            case .fourFive: return 4.0 / 5.0
            case .nineSixteen: return 9.0 / 16.0
            }
        }
    }

    enum Target: String, CaseIterable { case story, post4x5, post1x1 }

    enum Sample: String {
        /// 題・撮影の値・Vol. のある見本
        case kenrokuen
        /// 長い題（2行）
        case longTitle
        /// 題も日付も Vol. も撮影の値も無い（撮影地だけ）
        case bare
    }

    struct Combo {
        let shape: Shape
        let target: Target
        let sample: Sample
        var name: String { "\(target.rawValue)-\(shape.rawValue)-\(sample.rawValue)" }
    }

    static let combos: [Combo] = Target.allCases.flatMap { target in
        [Shape.portrait, .landscape, .square].map { Combo(shape: $0, target: target, sample: .kenrokuen) }
    } + [Combo(shape: .fourFive, target: .post4x5, sample: .kenrokuen),
         Combo(shape: .nineSixteen, target: .story, sample: .kenrokuen),
         Combo(shape: .landscape, target: .post4x5, sample: .longTitle),
         Combo(shape: .portrait, target: .story, sample: .bare)]

    static let takenDay = TripBook.utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10))
    static let location = "兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本"

    static func title(_ sample: Sample) -> String? {
        switch sample {
        case .kenrokuen: return "緑に包まれた水面の静寂"
        case .longTitle: return "朝霧の向こうにゆっくりと浮かび上がる雪吊りの松と霞ヶ池の水面"
        case .bare: return nil
        }
    }

    static func render(_ combo: Combo) async -> Data? {
        guard let photo = KoyomiGalleryPreview.photo(aspect: combo.shape.aspect) else { return nil }
        let rich = combo.sample != .bare
        switch combo.target {
        case .story:
            var facts = TravelStory.Facts(location: location, takenDay: rich ? takenDay : nil, name: "旅灯",
                                          latitude: 36.56)
            facts.title = title(combo.sample)
            if rich {
                facts.camera = "Hasselblad X2D II 100C"
                facts.aperture = "f/4.5"
                facts.exposure = "1/90s"
                facts.iso = 50
                facts.volume = 12
            }
            var choice = TravelStory.Choice()
            choice.kind = .magazine
            choice.placeLevel = .city
            choice.dateLevel = .date
            return TravelStoryRenderer.render([photo], facts: facts, choice: choice)?.data
        case .post4x5, .post1x1:
            var credit = SignatureShareCardRenderer.Credit(
                name: "旅灯", username: "tabi_akari", location: LocationMatch.shareCardDisplay(location),
                coords: nil,
                camera: rich ? "Hasselblad X2D II 100C" : nil, lens: nil, exposure: rich ? "1/90s" : nil,
                aperture: rich ? "f/4.5" : nil, iso: rich ? 50 : nil,
                verified: false, proStyle: nil, early: false, badge: nil,
                place: LocationMatch.shareCardPlace(location))
            credit.takenDay = rich ? takenDay : nil
            credit.title = title(combo.sample)
            credit.volume = rich ? 12 : nil
            return await SignatureShareCardRenderer.render(photo, credit: credit,
                                                           ratio: combo.target == .post4x5 ? .portrait : .square,
                                                           style: .magazine)
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
                .accessibilityIdentifier("magazineGallery.label")
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(combo.name)
                        .accessibilityIdentifier("magazineGallery.card")
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
            .accessibilityIdentifier("magazineGallery.next")
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
