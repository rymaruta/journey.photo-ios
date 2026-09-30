import SwiftUI
import UIKit

/// ストーリーの上に**データで**置いたもの（文字・スタンプ・投票）を描く閲覧画面の層。
///
/// 見た目は Web の `StoryTextOverlay` に合わせる（`StoryTextItem` の注釈）。
/// **投票のボタンだけが押せる**——ほかは指を素通りさせ、前後へ送る操作を邪魔しない。
struct StoryTextLayer: View {

    let texts: [StoryTextItem]
    /// 絵が画面に敷かれた大きさ（縦横比が分かればよい）。分からなければ画面いっぱいを絵とみなす
    /// （Web も測れないときは囲み全体に載せる）
    let imageSize: CGSize?
    let voteState: StoryVoteState?
    /// 票を入れられるか（ログインしていて・自分の投稿ではない）
    let canVote: Bool
    let voting: Bool
    var onVote: (String) -> Void = { _ in }
    /// 作る画面で選んでいる（投票の札を破線で囲む）
    var highlighted = false

    var body: some View {
        GeometryReader { geometry in
            let box = TextOverlay.filledRect(image: imageSize ?? geometry.size, in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                ForEach(Array(texts.enumerated()), id: \.offset) { _, item in
                    placed(item, box: box)
                }
            }
        }
    }

    /// 置き場所: `(x, y)` の割合の点を、要素の同じ割合の点に合わせる（Web の
    /// `left: x%` と `translate(-x%, -y%)`）。傾きは要素の中心の周り
    private func placed(_ item: StoryTextItem, box: CGRect) -> some View {
        let place = item.place
        return content(item, box: box)
            .rotationEffect(.degrees(place.rotate))
            .alignmentGuide(HorizontalAlignment.leading) { d in
                CGFloat(StoryTextItem.guide(fraction: place.x, element: Double(d.width),
                                            boxStart: Double(box.minX), boxLength: Double(box.width)))
            }
            .alignmentGuide(VerticalAlignment.top) { d in
                CGFloat(StoryTextItem.guide(fraction: place.y, element: Double(d.height),
                                            boxStart: Double(box.minY), boxLength: Double(box.height)))
            }
    }

    @ViewBuilder
    private func content(_ item: StoryTextItem, box: CGRect) -> some View {
        let fontSize = max(1, Double(box.width) * item.place.size)
        let maxWidth = Double(box.width) * 0.86
        switch item {
        case .text(let label):
            textLabel(label, fontSize: fontSize, maxWidth: maxWidth)
                .allowsHitTesting(false)
        case .stamp(let stamp):
            Text(stamp.glyph)
                .font(.system(size: fontSize))
                .fixedSize()
                .allowsHitTesting(false)
                .accessibilityLabel(L("スタンプ", "Sticker"))
        case .vote(let vote):
            voteCard(vote, fontSize: fontSize, maxWidth: maxWidth)
        }
    }

    // MARK: - 文字

    private func textLabel(_ label: StoryTextItem.Label, fontSize: Double, maxWidth: Double) -> some View {
        let color = StoryTextItem.colors[label.color] ?? (0xFFFFFF, 0x000000)
        let solid = label.bg == "solid"
        let padded = label.bg != "none"
        let width = Self.measuredWidth(label.text, font: Self.uiFont(label.font, size: fontSize), maxWidth: maxWidth)
        return Text(label.text)
            .font(Self.font(label.font, size: fontSize))
            .multilineTextAlignment(.center)
            .foregroundStyle(StoryCanvas.color(hex: solid ? color.on : color.hex))
            .frame(width: CGFloat(width))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, padded ? CGFloat(fontSize * 0.5) : 0)
            .padding(.vertical, padded ? CGFloat(fontSize * 0.18) : 0)
            .background(solid ? StoryCanvas.color(hex: color.hex)
                              : label.bg == "soft" ? Color.black.opacity(0.45) : Color.clear,
                        in: RoundedRectangle(cornerRadius: padded ? CGFloat(fontSize * 0.35) : 0))
            .shadow(color: .black.opacity(label.bg == "none" ? 0.65 : 0), radius: 8, y: 2)
    }

    // MARK: - 投票（Web の投票スタンプと同じ形: 白い札・問い・2つの丸いボタン）

    private func voteCard(_ vote: StoryTextItem.Vote, fontSize: Double, maxWidth: Double) -> some View {
        let questionFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let optionSize = fontSize * 0.9
        let optionFont = UIFont.systemFont(ofSize: optionSize, weight: .semibold)
        let percents = voteState?.percents
        let labels = vote.options.indices.map { optionLabel(vote, index: $0, percents: percents) }
        let optionsWidth = labels.map { Self.measuredWidth($0, font: optionFont, maxWidth: maxWidth) + optionSize * 1.2 }
            .reduce(0, +) + 8
        let width = min(maxWidth, max(Self.measuredWidth(vote.question, font: questionFont, maxWidth: maxWidth),
                                      optionsWidth))
        let open = canVote && voteState?.myVote == nil
        return VStack(spacing: CGFloat(fontSize * 0.4)) {
            Text(vote.question)
                .font(.system(size: fontSize, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(vote.options.indices, id: \.self) { index in
                    optionPill(vote, index: index, label: labels[index], size: optionSize,
                               percents: percents, open: open)
                }
            }
            if let counts = voteState?.counts, counts.a + counts.b == 0 {
                // 数が見えるのに 0 票——0%/0% は引き分けに読めるので言葉で（Web と同じ）
                Text(L("まだ票はありません", "No votes yet"))
                    .font(.system(size: fontSize * 0.8))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(Color.black)
        .frame(width: CGFloat(width))
        .padding(.horizontal, CGFloat(fontSize * 0.5))
        .padding(.vertical, CGFloat(fontSize * 0.18 + 6))
        .background(Color.white, in: RoundedRectangle(cornerRadius: CGFloat(fontSize * 0.35)))
        // 作る画面で選んでいる札は破線で囲む（文字の札と同じ・板 24b）
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(-8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("投票：\(vote.question)", "Poll: \(vote.question)"))
    }

    private func optionLabel(_ vote: StoryTextItem.Vote, index: Int, percents: (a: Int, b: Int)?) -> String {
        let option = vote.options[index]
        let mine = voteState?.myVote == (index == 0 ? "a" : "b")
        guard let percents else { return option }
        return "\(mine ? "✓ " : "")\(option) \(index == 0 ? percents.a : percents.b)%"
    }

    @ViewBuilder
    private func optionPill(_ vote: StoryTextItem.Vote, index: Int, label: String, size: Double,
                            percents: (a: Int, b: Int)?, open: Bool) -> some View {
        let choice = index == 0 ? "a" : "b"
        let mine = voteState?.myVote == choice
        let pct = percents.map { index == 0 ? $0.a : $0.b }
        let pill = Text(label)
            .font(.system(size: size, weight: mine ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.vertical, CGFloat(size * 0.35))
            .padding(.horizontal, CGFloat(size * 0.6))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                // 割合があれば、その分だけ濃く塗る（Web の `linear-gradient`）
                GeometryReader { g in
                    let base: Color = Color.black.opacity(pct == nil ? 0.08 : 0.06)
                    let strong: Color = Color.black.opacity(0.18)
                    let filled: CGFloat = g.size.width * CGFloat(pct ?? 0) / 100
                    ZStack(alignment: .leading) {
                        base
                        if pct != nil {
                            strong.frame(width: filled)
                        }
                    }
                }
                .clipShape(Capsule())
            }
        if open {
            Button { onVote(choice) } label: { pill }
                .buttonStyle(.plain)
                .disabled(voting)
                .opacity(voting ? 0.6 : 1)
                .accessibilityLabel(L("「\(vote.options[index])」に投票", "Vote \"\(vote.options[index])\""))
        } else {
            pill
                .accessibilityAddTraits(mine ? .isSelected : [])
                .accessibilityValue(voteState?.counts.map { L("\(index == 0 ? $0.a : $0.b)票", "\(index == 0 ? $0.a : $0.b) votes") } ?? "")
        }
    }

    // MARK: - 字体（Web の `STORY_FONTS` の鍵。端末に無い字は近い字に）

    /// 字体の鍵から、端末で描く書体。**走り書き（Yomogi）は同梱していない**ので手書き風
    /// （Klee One）で代える。明朝は Web と同じヒラギノ明朝
    static func fontName(_ key: String) -> String? {
        switch key {
        case "mincho": return "HiraMinProN-W6"
        case "maru": return "HiraMaruProN-W4"
        case "marker": return "YuseiMagic-Regular"
        case "scribble": return "KleeOne-SemiBold"
        default: return nil
        }
    }

    static func uiFont(_ key: String, size: Double) -> UIFont {
        if let name = fontName(key), let font = UIFont(name: name, size: size) { return font }
        switch key {
        case "mono": return UIFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        case "bold": return UIFont.systemFont(ofSize: size, weight: .heavy)
        case "gothic", "mincho", "maru", "marker", "scribble": return UIFont.systemFont(ofSize: size, weight: .semibold)
        default: return UIFont.systemFont(ofSize: size, weight: .heavy)
        }
    }

    /// 画面の字体。**測る字（`uiFont`）と同じ字を選ぶ**（違うと測った幅で折り返しがずれる）
    static func font(_ key: String, size: Double) -> Font {
        if let name = fontName(key), UIFont(name: name, size: size) != nil { return .custom(name, fixedSize: size) }
        switch key {
        case "mono": return .system(size: size, weight: .semibold, design: .monospaced)
        case "bold": return .system(size: size, weight: .heavy)
        case "gothic", "mincho", "maru", "marker", "scribble": return .system(size: size, weight: .semibold)
        default: return .system(size: size, weight: .heavy)
        }
    }

    /// 折り返したあとの幅（`maxWidth` まで）。**要素の幅を先に決める**——幅の上限だけ渡すと
    /// 枠が上限いっぱいに広がり、`(x, y)` の割合の点で合わせる置き方がずれる
    static func measuredWidth(_ text: String, font: UIFont, maxWidth: Double) -> Double {
        let rect = NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
            with: CGSize(width: maxWidth, height: 100_000), options: .usesLineFragmentOrigin, context: nil)
        return min(maxWidth, Double(rect.width).rounded(.up))
    }
}
