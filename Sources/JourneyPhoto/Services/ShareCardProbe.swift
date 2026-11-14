#if !os(Linux)
import UIKit

/// 共有カードの点検の記録（テストだけが使う・2026-11-14）。
///
/// `ShareCardProbe.$current.withValue(probe) { await SignatureShareCardRenderer.render(…) }` の間だけ、
/// 描く部品（字・印・ロゴ・アバター・地図）の枠と、字の大きさ・切れたかを記録する。
/// `skipContent` なら部品を描かず、写真・影・黒い面・額縁だけの絵を作る。2枚の書き出し画像の画素の差が
/// 「部品が描かれた所」になり、端からの距離と、部品の下の背景の明るさ（明暗の比）を画素で測れる
/// （`ShareCardAuditTests`）。ふだんの書き出しでは `current` が nil なので、何も変わらない。
final class ShareCardProbe: @unchecked Sendable {
    struct Item {
        enum Kind: String { case text, symbol, logo, avatar, marks, map }
        let kind: Kind
        let text: String
        let rect: CGRect
        let color: UIColor
        let fontSize: CGFloat
        /// 幅に入らず末尾を「…」にした・行を詰めきれなかった
        let truncated: Bool
    }

    @TaskLocal static var current: ShareCardProbe?

    let skipContent: Bool
    private let lock = NSLock()
    private var stored: [Item] = []

    init(skipContent: Bool) {
        self.skipContent = skipContent
    }

    var items: [Item] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func record(_ kind: Item.Kind, _ text: String = "", rect: CGRect, color: UIColor = .white,
                fontSize: CGFloat = 0, truncated: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        stored.append(Item(kind: kind, text: text, rect: rect, color: color, fontSize: fontSize, truncated: truncated))
    }

    /// 部品を描くか（点検の「背景だけ」の絵では描かない）
    static var drawsContent: Bool { !(current?.skipContent ?? false) }

    /// 記録して、描くかを返す
    @discardableResult
    static func note(_ kind: Item.Kind, _ text: String = "", rect: CGRect, color: UIColor = .white,
                     fontSize: CGFloat = 0, truncated: Bool = false) -> Bool {
        current?.record(kind, text, rect: rect, color: color, fontSize: fontSize, truncated: truncated)
        return drawsContent
    }
}
#endif
