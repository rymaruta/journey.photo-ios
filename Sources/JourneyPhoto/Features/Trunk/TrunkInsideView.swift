import SwiftUI
import UIKit

/// トランクの中（板「旅のトランク」の部品 Inside・2026-10-18 owner 承認）。360×268 の胴と、同じ大きさのふた。
///
/// 前開き: 開けた姿は**胴が上**（内張り・内ポケットに会員証・仕切りの帯に乗車券の束）、**倒れたふたが下**
/// （内張り・メダルの台に 8 枠・「ほか N」）。台と仕切りは型のまま、内張りは付けた内張りの部品か型の既定
/// （`TrunkInsideLooks`）。縫い付けの札（「会員証」「乗車券 12」「メダル 10」）は板どおり 11pt の刷りの字。
///
/// 押せるのは `interactive` のときだけ（開き切ったとき）。押すと `onPick`。持ち上げているものは少し浮かせる
struct TrunkInsideView: View {

    enum Part { case lid, base, all }

    let model: TrunkModel
    let part: Part
    let lining: TrunkLining
    let contents: TrunkInsideContents
    /// 会員証の絵（サポーター証の表・`SupporterCardTextures.front`）。無ければ素材の絵
    var cardImage: UIImage?
    /// 会員証の読み上げ（`SupporterCardFace.accessibilityLabel`）
    var cardLabel: String = L("サポーター証", "Supporter card")
    /// 乗車券の束に見せる写真（すれちがい帳の新しい方から3枚）
    var ticketPhotos: [Photo] = []
    /// 縫い付けの札を出すか
    var tabs = true
    /// 押せるか（開き切ったとき）。押せないときは1枚の絵として読み上げる
    var interactive = false
    /// 持ち上げているもの（少し浮かせる）
    var lifted: TrunkHeld?
    var onPick: (TrunkHeld) -> Void = { _ in }
    /// 胴（`.base`）のどの層を描くか。ふたを動かしている間は、乗車券の下と上を1度だけ絵にして使い回し、
    /// 写真の載った乗車券だけを生きたまま挟む（`TrunkOpenView` の `TrunkLidImages`）
    var layer: BaseLayer = .all

    /// 胴の層（乗車券の束をはさんで下・乗車券・上）
    enum BaseLayer { case all, belowTickets, ticketsOnly, aboveTickets }

    static let width: Double = TrunkLooks.bodyWidth
    static let height: Double = TrunkLooks.bodyHeight
    /// 開けた姿（胴＋蝶番の帯＋ふた）の高さ（板の 548）
    static let openHeight: Double = 548
    /// 縁の幅（板の R）
    private static let rim: Double = 10
    /// 仕切りの左（板の dividerX）
    private static let dividerX: Double = 206

    private var look: TrunkInsideLook { TrunkInsideLooks.look(model) }

    var body: some View {
        let look = look
        Group {
            switch part {
            case .lid: lid(look)
            case .base: base(look)
            case .all:
                ZStack(alignment: .topLeading) {
                    base(look)
                    hingeBand(look).offset(y: Self.height)
                    lid(look).offset(y: 280)
                }
                .frame(width: Self.width, height: Self.openHeight, alignment: .topLeading)
            }
        }
        .modifier(InsideAccessibility(interactive: interactive,
                                      label: contents.accessibilityLabel(model: model, lining: lining)))
    }

    // MARK: 胴（上）

    private func base(_ look: TrunkInsideLook) -> some View {
        let below = layer == .all || layer == .belowTickets
        let above = layer == .all || layer == .aboveTickets
        let shadowed = layer == .all || layer == .belowTickets
        return ZStack(alignment: .topLeading) {
            if below {
                TrunkPartPaintView(paint: look.rim)
                liningLayer(look, deep: true)
                divider(look)
                if contents.showsCard { card }
                pocket(look)
            }
            if layer == .all || layer == .ticketsOnly { tickets }
            if above {
                strap(look)
                if tabs {
                    tab(L("会員証", "Card"), x: 62, y: 150, w: 90)
                    let tw = contents.ticketTabWidth
                    let left = Self.dividerX + 10
                    tab(contents.ticketTab, x: left + (Self.width - Self.rim - left - tw) / 2, y: 176, w: tw)
                }
                edgeShade
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(shadowed ? 0.6 : 0), radius: 0, x: 0, y: 3)
        .shadow(color: Color.black.opacity(shadowed ? 0.75 : 0), radius: 25, x: 0, y: 30)
    }

    /// 内張り（縁の内側 10・角 8）。胴の中は奥へ深い陰（板の `inset 0 16px 26px`）
    private func liningLayer(_ look: TrunkInsideLook, deep: Bool) -> some View {
        let w = Self.width - Self.rim * 2, h = Self.height - Self.rim * 2
        return ZStack(alignment: .topLeading) {
            TrunkPartPaintView(paint: lining.paint)
            if deep {
                LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0.55), location: 0),
                                       Gradient.Stop(color: Color.clear, location: 34 / h),
                                       Gradient.Stop(color: Color.clear, location: 1 - 12 / h),
                                       Gradient.Stop(color: Color.black.opacity(0.3), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                // ふたの裏の陰（`inset 0 -10px 18px`・`inset 0 6px 12px`）
                LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0.25), location: 0),
                                       Gradient.Stop(color: Color.clear, location: 14 / h),
                                       Gradient.Stop(color: Color.clear, location: 1 - 22 / h),
                                       Gradient.Stop(color: Color.black.opacity(0.35), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if look.gildEdge {
                RoundedRectangle(cornerRadius: 8).strokeBorder(WebTheme.accent, lineWidth: 1.5)
            }
        }
        .offset(x: Self.rim, y: Self.rim)
    }

    private func divider(_ look: TrunkInsideLook) -> some View {
        let h = Self.height - Self.rim * 2
        return ZStack(alignment: .topLeading) {
            TrunkPartPaintView(paint: look.divider)
            if look.brassBand {
                // 真鍮の帯（仕切りの真ん中 46〜54%）
                TrunkPartPaintView(paint: TrunkInsideLooks.brass)
                    .frame(width: 10, height: h * 0.08)
                    .offset(y: h * 0.46)
            }
            if look.gildEdge {
                HStack(spacing: 0) {
                    WebTheme.accent.frame(width: 1.5)
                    Spacer(minLength: 0)
                    WebTheme.accent.frame(width: 1.5)
                }
            }
        }
        .frame(width: 10, height: h, alignment: .topLeading)
        .shadow(color: Color.black.opacity(0.5), radius: 3, x: 3, y: 0)
        .offset(x: Self.dividerX, y: Self.rim)
    }

    /// 会員証（サポーター証 342×216 を半分で・少し傾けて内ポケットから出ている）
    private var card: some View {
        let up = lifted == .card
        return Button { onPick(.card) } label: {
            Group {
                if let cardImage {
                    Image(uiImage: cardImage).resizable().interpolation(.high)
                } else {
                    Image("supporter-card-front").resizable().interpolation(.high)
                }
            }
            .frame(width: 171, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(up ? 0.7 : 0.55), radius: up ? 9 : 4, x: 0, y: up ? 16 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
        .rotationEffect(.degrees(-2))
        .scaleEffect(up ? 1.06 : 1)
        .offset(x: 22, y: up ? 8 : 30)
        .accessibilityLabel(cardLabel)
        .accessibilityHint(L("押すと手に取れます", "Tap to pick it up"))
        .accessibilityIdentifier("trunk.inside.card")
    }

    private func pocket(_ look: TrunkInsideLook) -> some View {
        ZStack(alignment: .topLeading) {
            TrunkPartPaintView(paint: look.panel)
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 2)
            if let stitch = look.stitch {
                Path { p in
                    p.move(to: CGPoint(x: 6, y: 6))
                    p.addLine(to: CGPoint(x: 176, y: 6))
                }
                .stroke(Color(trunk: stitch), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            } else {
                Color.black.opacity(0.3).frame(height: 3)
            }
        }
        .frame(width: 182, height: 160, alignment: .topLeading)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 4))
        .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: -3)
        .offset(x: 16, y: 92)
        .allowsHitTesting(false)
    }

    /// 乗車券の束（すれちがい帳の 92×128 を縮めた 75×105・写真 62）
    @ViewBuilder
    private var tickets: some View {
        let count = min(TrunkInsideContents.ticketStack, contents.ticketCount)
        if count > 0 {
            let up = lifted == .tickets
            let poses = contents.ticketPoses
            ZStack(alignment: .topLeading) {
                ForEach(0..<min(count, poses.count), id: \.self) { i in
                    ticket(ticketPhotos.indices.contains(i) ? ticketPhotos[i] : nil)
                        .rotationEffect(.degrees(poses[i].rot))
                        .shadow(color: Color.black.opacity(0.6), radius: up ? 7 : 4, x: 0, y: up ? 14 : 8)
                        .offset(x: 226 + poses[i].x * 0.82, y: 27 - (up ? 14 : 0))
                }
                Button { onPick(.tickets) } label: {
                    Color.clear.frame(width: 128, height: 132).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
                .offset(x: 220, y: 18)
                .accessibilityLabel(contents.ticketLabel)
                .accessibilityHint(L("押すと手に取れます", "Tap to pick them up"))
                .accessibilityIdentifier("trunk.inside.tickets")
            }
        }
    }

    private func ticket(_ photo: Photo?) -> some View {
        let brass = WebTheme.accent
        return VStack(spacing: 0) {
            Group {
                if let photo {
                    RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                } else {
                    Color(trunk: TrunkRGBA(0x1A1A1A))
                }
            }
            .frame(width: 75, height: 62)
            .clipped()
            brass.opacity(0.55).frame(height: 1)
            Spacer(minLength: 0)
        }
        .frame(width: 75, height: 105)
        .background(Color(trunk: TrunkRGBA(0x0E0D0B)))
        .overlay(alignment: .bottomLeading) {
            // 切り取り線と、改札の穴
            HStack(spacing: 4) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0.5))
                    p.addLine(to: CGPoint(x: 51, y: 0.5))
                }
                .stroke(brass.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 51, height: 1)
                Circle().strokeBorder(brass.opacity(0.5), lineWidth: 1).frame(width: 7, height: 7)
            }
            .padding(.leading, 6)
            .padding(.bottom, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(brass.opacity(0.5), lineWidth: 1))
        .allowsHitTesting(false)
    }

    /// 乗車券を押さえる帯（仕切りの右・上から 112）
    private func strap(_ look: TrunkInsideLook) -> some View {
        let left = Self.dividerX + 10
        let w = Self.width - Self.rim - left
        return ZStack(alignment: .topLeading) {
            TrunkPartPaintView(paint: look.panel)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            if let stitch = look.stitch {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 3.5)); p.addLine(to: CGPoint(x: w, y: 3.5))
                    p.move(to: CGPoint(x: 0, y: 14.5)); p.addLine(to: CGPoint(x: w, y: 14.5))
                }
                .stroke(Color(trunk: stitch), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .frame(width: w, height: 18, alignment: .topLeading)
        .shadow(color: Color.black.opacity(0.5), radius: 2.5, x: 0, y: 3)
        .offset(x: left, y: 112)
        .allowsHitTesting(false)
    }

    // MARK: ふた（下・ふたの裏）

    private func lid(_ look: TrunkInsideLook) -> some View {
        ZStack(alignment: .topLeading) {
            TrunkPartPaintView(paint: look.rim)
            liningLayer(look, deep: false)
            medalPanel(look)
            if tabs {
                tab(contents.medalTab, x: 126, y: 16, w: 108)
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.6), radius: 0, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.7), radius: 20, x: 0, y: 24)
    }

    /// メダルの台（316×200・4 列 2 段の凹みと留め輪）
    private func medalPanel(_ look: TrunkInsideLook) -> some View {
        let slots = contents.slots
        let cellW = 316.0 / 4
        return ZStack(alignment: .topLeading) {
            TrunkPartPaintView(paint: look.panel)
            if let stitch = look.stitch {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color(trunk: stitch), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .padding(5)
            }
            ForEach(Array(slots.indices), id: \.self) { i in
                let cx = cellW * Double(i % 4) + cellW / 2
                let cy = 50 + Double(i / 4) * 100
                slot(slots[i], cx: cx, cy: cy)
            }
        }
        .frame(width: 316, height: 200, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(look.gildEdge ? WebTheme.accent.opacity(0.8) : Color.white.opacity(0.06), lineWidth: look.gildEdge ? 1.5 : 1)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 4, x: 0, y: 4)
        .offset(x: 22, y: 46)
    }

    @ViewBuilder
    private func slot(_ slot: TrunkMedalSlot, cx: Double, cy: Double) -> some View {
        let filled: Bool = {
            if case .empty = slot { return false }
            return true
        }()
        // 凹み（70・内へ落ちる陰）と、下の留め輪
        ZStack {
            Circle().fill(Color.black.opacity(0.28))
            Circle().stroke(Color.black.opacity(0.55), lineWidth: 5).blur(radius: 3).offset(y: 2).clipShape(Circle())
            if !filled {
                Circle().strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
        }
        .frame(width: 70, height: 70)
        .offset(x: cx - 35, y: cy - 35)
        .accessibilityHidden(true)
        UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
            .fill(Color.black.opacity(0.35))
            .frame(width: 18, height: 9)
            .opacity(filled ? 1 : 0.5)
            .offset(x: cx - 9, y: cy + 30)
            .accessibilityHidden(true)
        switch slot {
        case .medal(let badge):
            let up = lifted == .medal(badge)
            Button { onPick(.medal(badge)) } label: {
                Image(BadgeCatalog.largeImage(badge.key, tier: badge.tier))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(up ? 0.7 : 0.55), radius: up ? 6 : 1.5, x: 0, y: up ? 14 : 3)
                    .scaleEffect(up ? 1.12 : 1)
                    .offset(y: up ? -10 : 0)
                    // 押す所は凹みの升いっぱい（76×88）。舞台を縮めても 44pt を割らない（`TrunkLid.medalHit`）
                    .frame(width: TrunkLid.medalHit.w, height: TrunkLid.medalHit.h)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!interactive)
            .offset(x: cx - TrunkLid.medalHit.w / 2, y: cy - TrunkLid.medalHit.h / 2)
            .accessibilityLabel(TrunkInsideContents.slotLabel(slot))
            .accessibilityHint(L("押すと手に取れます", "Tap to pick it up"))
            .accessibilityIdentifier("trunk.inside.medal")
        case .more:
            Button { onPick(.more) } label: {
                Text(L("ほか \(contents.overflow)", "+\(contents.overflow)"))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WebTheme.accent)
                    .frame(width: 64, height: 64)
                    .background(Color(trunk: TrunkRGBA(0x0E0D0B)), in: Circle())
                    .overlay(Circle().strokeBorder(WebTheme.accent.opacity(0.5), lineWidth: 1))
                    .frame(width: TrunkLid.medalHit.w, height: TrunkLid.medalHit.h)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!interactive)
            .offset(x: cx - TrunkLid.medalHit.w / 2, y: cy - TrunkLid.medalHit.h / 2)
            .accessibilityLabel(TrunkInsideContents.slotLabel(slot))
            .accessibilityHint(L("押すと手に取れます", "Tap to pick them up"))
            .accessibilityIdentifier("trunk.inside.more")
        case .empty:
            EmptyView()
        }
    }

    // MARK: 蝶番の帯（開けた姿）

    private func hingeBand(_ look: TrunkInsideLook) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color.black.opacity(0.85), Color.black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                .frame(width: Self.width - 16, height: 12)
                .offset(x: 8)
            ForEach([64.0, 268], id: \.self) { x in
                TrunkPartPaintView(paint: look.metal)
                    .frame(width: 28, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1) }
                    .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                    .offset(x: x, y: -3)
            }
        }
        .frame(width: Self.width, height: 12, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // MARK: 縫い付けの札・縁の陰

    /// 縫い付けの札（22pt・革の粒の黒・真鍮の 11pt の字。黒い地の上の真鍮）
    private func tab(_ text: String, x: Double, y: Double, w: Double) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .tracking(11 * 0.12)
            .foregroundStyle(WebTheme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: w, height: 22)
            .background {
                ZStack {
                    Color(trunk: TrunkRGBA(0x141210))
                    TrunkGrain.leather
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WebTheme.accent.opacity(0.25), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
            .offset(x: x, y: y)
            .accessibilityHidden(true)
    }

    private var edgeShade: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: Self.width, height: 2)
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 0),
                                   Gradient.Stop(color: Color.clear, location: 1 - 30 / Self.height),
                                   Gradient.Stop(color: Color.black.opacity(0.4), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 押せないとき（絵として置く）は1枚の絵として読み上げ、押せるときは中のボタンを1つずつ読ませる
private struct InsideAccessibility: ViewModifier {
    let interactive: Bool
    let label: String

    func body(content: Content) -> some View {
        if interactive {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
        }
    }
}
