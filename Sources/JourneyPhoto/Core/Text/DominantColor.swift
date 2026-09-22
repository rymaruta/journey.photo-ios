import Foundation

/// 写真の代表色（`dominantColor`）。
///
/// **Web の `averagePixelsToHex` と同じ計算。** 16×16 に縮めた絵の
/// 平均を `#rrggbb` にする。使い道は「読み込み中の地の色」で、
/// 一覧が真っ黒から写真にぱっと変わるのを和らげる。
///
/// **アプリは今まで送っていなかった。** Web から上げた写真は持っていて、
/// アプリから上げた写真だけ持っていない——同じ一覧に混ざると、
/// アプリの写真の枠だけ黒いまま残る。
enum DominantColor {

    /// ほぼ透明の画素は数えない（Web と同じ線）
    static let alphaFloor: UInt8 = 32

    /// RGBA の並びから平均色。**数えられる画素が1つも無ければ nil**
    /// （真っ白を返すより、属性ごと持たない方が正しい）。
    static func hex(fromRGBA bytes: [UInt8]) -> String? {
        var r = 0, g = 0, b = 0, n = 0
        var i = 0
        while i + 3 < bytes.count {
            if bytes[i + 3] >= alphaFloor {
                r += Int(bytes[i])
                g += Int(bytes[i + 1])
                b += Int(bytes[i + 2])
                n += 1
            }
            i += 4
        }
        guard n > 0 else { return nil }
        return "#" + [r, g, b].map { component -> String in
            let value = Int((Double(component) / Double(n)).rounded())
            return String(format: "%02x", min(255, max(0, value)))
        }.joined()
    }

    /// 縮める先の一辺。Web と同じ16（平均を取るだけなのでこれで足りる）
    static let sampleSize = 16
}
