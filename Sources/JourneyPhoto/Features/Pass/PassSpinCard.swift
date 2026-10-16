import SwiftUI

/// 回るきっぷ（表・裏）。**角度を補間して描く**（`Animatable`）——裏返す途中の 90° で表と裏が替わる。
/// 縁と破線の光は角度から（`SpinMotion.shine`・真鍮の線の上だけ）。「視差効果を減らす」では回さず、光も流さない。
///
/// 2026-10-16 判断（owner「自分のカードも指で回したい」）: 届いたカード（`PassViewerView`）と自分のカードの見本
/// （`PassSpinCard`・`PassCardPickView`）が**同じこの部品**を使う。描くものは表・裏とも「描くもの」
/// （`PassTicketFace`・`PassTicketBackFace`）で渡す
struct PassSpinTicket: View, Animatable {
    var yaw: Double
    let front: PassTicketFace
    let back: PassTicketBackFace
    let reduceMotion: Bool
    /// 写真を押した（束の画面: 全面で見る）。nil なら写真も裏返しの一部
    var onPhotoTap: (() -> Void)? = nil

    var animatableData: Double {
        get { yaw }
        set { yaw = newValue }
    }

    var body: some View {
        let back = SpinMotion.showsBack(yaw)
        let shine: Double? = reduceMotion ? nil : SpinMotion.shine(yaw)
        ZStack {
            // 写真を押すと全面で見る（写真の上は白だけ）。裏を見ている間は表を押させない・読ませない
            PassCardFront(face: front, onPhotoTap: onPhotoTap, shine: shine)
                .opacity(back ? 0 : 1)
                .allowsHitTesting(!back)
                .accessibilityHidden(back)
            PassCardBack(face: self.back, shine: shine)
                // 回すときは、裏が鏡に映らないように先に半回転しておく（回さないときはそのまま）
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(back ? 1 : 0)
                .allowsHitTesting(back)
                .accessibilityHidden(!back)
        }
        .rotation3DEffect(.radians(reduceMotion ? 0 : yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotationEffect(.degrees(back ? 1 : -1.5))
    }

    /// 読み上げで、いま見えている面（「表」「裏」）
    nonisolated static func spokenSide(_ yaw: Double) -> String {
        SpinMotion.showsBack(yaw) ? L("裏", "Back") : L("表", "Front")
    }
}

/// 指を置いて回す手つきの覚え（**束の画面と自分のカードの見本が同じものを使う**・写しを作らない）。
/// 指を置いた時の回りと時刻を覚え、動かしている間の回りは `PassSpinGesture.liveYaw` で決める。
/// 離したら `end` で消す（吸い付く先は `SpinMotion.snapTarget`）
struct PassSpinDrag {
    private(set) var baseYaw: Double?
    private(set) var startAt: Date?
    /// ScrollView の中で、この指が横（回す）かたて（送る）か。最初に動いた向きで決め、離すまで変えない
    private(set) var axis: PassSpinGesture.Axis?

    /// 指を置いた（2回目からは何もしない）
    mutating func begin(yaw: Double, now: Date = Date()) {
        guard startAt == nil else { return }
        startAt = now
        baseYaw = yaw
    }

    /// 向きを決める（最初の1回だけ）
    mutating func lockAxis(dx: Double, dy: Double) -> PassSpinGesture.Axis {
        if let axis { return axis }
        let decided = PassSpinGesture.axis(dx: dx, dy: dy)
        axis = decided
        return decided
    }

    /// 指を動かしている間の回り
    func liveYaw(current: Double, dx: Double, width: Double, now: Date = Date()) -> Double {
        PassSpinGesture.liveYaw(base: baseYaw ?? current, dx: dx, width: width,
                                elapsed: now.timeIntervalSince(startAt ?? now))
    }

    /// 指を離した: 置いていた長さと、置いた時の回りを返して忘れる
    mutating func end(now: Date = Date()) -> (duration: Double, base: Double?) {
        let duration = startAt.map { now.timeIntervalSince($0) } ?? 1
        let base = baseYaw
        self = PassSpinDrag()
        return (duration, base)
    }
}

/// 自分のカードの見本（名刺の一枚を選ぶ画面）。届いたカードと同じ `PassSpinTicket` を、同じ手つき
/// （`PassSpinDrag`・指を置いて回す・離すと近い面に吸い付く）で回す。
///
/// - **たての送りとぶつけない**: ScrollView の中なので `simultaneousGesture` で受け、最初に動いた向きが横の
///   ときだけ回す（`PassSpinGesture.axis`）。たてなら何もしない（送りはそのまま）
/// - 束の画面と違い「次のカード」は無いので、払いと回すの切り分け（`classify`）は使わない
/// - 押すと裏返る。下の「裏を見る」でも裏返せる（回せない人・「視差効果を減らす」でも裏を読める）
/// - 読み上げ: 表・裏のどちらかを値で言い、既定の操作で裏返す
struct PassSpinCard: View {
    let front: PassTicketFace
    let back: PassTicketBackFace
    /// 読み上げで面と一緒に言う名前（例「相手に届くカード」→「相手に届くカードの裏」）
    let spokenName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var yaw: Double = 0
    @State private var spin = PassSpinDrag()

    private var showsBack: Bool { SpinMotion.showsBack(yaw) }

    var body: some View {
        VStack(spacing: JPSpace.xs) {
            PassSpinTicket(yaw: yaw, front: front, back: back, reduceMotion: reduceMotion)
                .contentShape(Rectangle())
                .onTapGesture { flip() }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            spin.begin(yaw: yaw)
                            let dx = Double(value.translation.width)
                            guard spin.lockAxis(dx: dx, dy: Double(value.translation.height)) == .horizontal,
                                  !reduceMotion else { return }
                            yaw = spin.liveYaw(current: yaw, dx: dx, width: Double(PassCardStyle.deckSize.width))
                        }
                        .onEnded { value in
                            let turning = spin.axis == .horizontal && !reduceMotion
                            _ = spin.end()
                            guard turning else { return }
                            let dx = Double(value.translation.width)
                            let velocity = SpinMotion.releaseVelocity(
                                vx: (Double(value.predictedEndTranslation.width) - dx) / 0.25,
                                width: Double(PassCardStyle.deckSize.width), reduceMotion: reduceMotion)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                yaw = SpinMotion.snapTarget(yaw: yaw, velocity: velocity)
                            }
                        }
                )
                // 名前で上書きしない（上書きすると中身＝裏のひとこと等が読まれない）。名前と面は値で言う
                .accessibilityElement(children: .combine)
                .accessibilityValue(L("\(spokenName)の\(PassSpinTicket.spokenSide(yaw))",
                                      "\(PassSpinTicket.spokenSide(yaw)) of \(spokenName)"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(showsBack ? L("押すと表に戻ります", "Tap to see the front")
                                             : L("押すと裏返します", "Tap to flip the card"))
                .accessibilityAction { flip() }
                .accessibilityIdentifier("pass.pick.card")
            HStack(spacing: JPSpace.xs) {
                Text(reduceMotion ? L("押すと裏返る", "Tap to flip") : L("指を置いて回す · 押すと裏返る", "Hold and turn · Tap to flip"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                // 回さずに裏を読む口（黒地の上の手がかり＝真鍮・CLAUDE.md の owner の好み）
                Button(action: flip) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .accessibilityHidden(true)
                        Text(showsBack ? L("表を見る", "See the front") : L("裏を見る", "See the back"))
                    }
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pass.pick.flip")
            }
            .frame(width: PassCardStyle.deckSize.width)
        }
    }

    /// 押して裏返す（「裏を見る」・読み上げも）。「視差効果を減らす」では動かさずに替える
    private func flip() {
        let target = SpinMotion.flipTarget(from: yaw)
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82)) { yaw = target }
    }
}
