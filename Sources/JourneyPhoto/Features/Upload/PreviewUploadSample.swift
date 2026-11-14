import UIKit
#if os(iOS)
import ImageIO
import UniformTypeIdentifiers
#endif

/// 画面写真の試験で投稿画面に入れる見本の1枚（`PreviewSession.opensUploadSample`・Debug のみ）。
///
/// **アプリに入っている画像を使う**（構図の見本の1枚・`Assets.xcassets`）。写真のライブラリにも
/// 通信にも頼らない。鍵の無いときは nil（ふだんの投稿画面は何も変わらない）
enum PreviewUploadSample {

    /// 見本に使う画像の名前（`Assets.xcassets` の構図の見本）
    static let assetName = "composition-ai-radial"

    /// 見本の形を替える鍵（`-JPPreviewUploadSampleKind <kind>`・Debug のみ・2026-11-14 札 #596）。
    /// owner の「iPhone のカメラで撮ったそのままの写真（HEIC）」を UI テストで通すため、**実寸の画像をその場で作る**
    /// （リポジトリに大きい画像を置かない）。中身は模様だが、寸法・形式・向きの情報は本物と同じで、
    /// 読み込み（`ImagePreparer.prepare`）が展開する画素の数は同じになる
    static let kindKey = "JPPreviewUploadSampleKind"

    /// 作る形。寸法は横×縦（向きの情報で回す前の、ファイルの中の画素）
    enum Kind: String, CaseIterable {
        /// 48MP の HEIC（iPhone 14 Pro 以降のメイン 48MP）。向き 6（縦に持って撮った＝右へ 90° 回して見る）
        case heic48
        /// 12MP の HEIC（4032×3024）。向き 6
        case heic12
        /// 縦長の HEIC（3024×4032）。向き 1
        case portrait
        /// パノラマの HEIC（16000×3000）。向き 1
        case pano
        /// 大きい PNG（6000×4000・向きの情報なし）
        case png

        var pixels: (width: Int, height: Int) {
            switch self {
            case .heic48: return (8064, 6048)
            case .heic12: return (4032, 3024)
            case .portrait: return (3024, 4032)
            case .pano: return (16000, 3000)
            case .png: return (6000, 4000)
            }
        }

        /// EXIF / TIFF の向き（`kCGImagePropertyOrientation`）。PNG は付けない
        var orientation: Int? {
            switch self {
            case .heic48, .heic12: return 6
            case .portrait, .pano: return 1
            case .png: return nil
            }
        }
    }

    static var kind: Kind? {
        #if DEBUG
        UserDefaults.standard.string(forKey: kindKey).flatMap(Kind.init(rawValue:))
        #else
        nil
        #endif
    }

    static func capture() -> CameraCapture? {
        guard PreviewSession.opensUploadSample else { return nil }
        if let kind {
            return CameraCapture(metadata: [:], capturedAt: Date(), encode: { make(kind) })
        }
        return CameraCapture(metadata: [:], capturedAt: Date(), encode: {
            UIImage(named: assetName)?.jpegData(compressionQuality: 0.9)
        })
    }

    /// 実寸の画像を作って、その形式で書き出す（HEIC は向きの情報つき）。iOS 以外は nil
    static func make(_ kind: Kind) -> Data? {
        #if os(iOS)
        let (width, height) = kind.pixels
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // 斜めの縞と格子（一色だと圧縮で極端に小さくなり、本物の写真の重さから離れる）
        let colors = [CGColor(srgbRed: 0.2, green: 0.45, blue: 0.7, alpha: 1),
                      CGColor(srgbRed: 0.85, green: 0.6, blue: 0.3, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
        context.setLineWidth(6)
        let step = 97
        for x in stride(from: 0, to: width + height, by: step) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x - height, y: height))
        }
        context.strokePath()
        // 上の端に印（向きを回したときにどちらが上か分かるように）
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: height - height / 10, width: width / 3, height: height / 10))
        guard let image = context.makeImage() else { return nil }
        let type: UTType = kind == .png ? .png : .heic
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        var properties: [CFString: Any] = [:]
        if type == .heic { properties[kCGImageDestinationLossyCompressionQuality] = 0.8 }
        if let orientation = kind.orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let data = output as Data
        print("[storyCrash] sample kind=\(kind.rawValue) \(width)x\(height) bytes=\(data.count)"
              + " mem=\((PerfTimeline.physFootprint() ?? 0) / 1_048_576)MB")
        return data
        #else
        return nil
        #endif
    }
}
