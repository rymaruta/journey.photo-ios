import SwiftUI
import UIKit

/// サポーター証（板 64・2026-10-09）。設定の「サポーター証」から積む。
///
/// 板のとおり:
/// - 地は上寄りに少し明るい丸いグラデーション（#17181B → #050505 48% → 黒 70%）
/// - 見出し「サポーター証」（明朝 18・戻るの右）
/// - 342×216・角 16 の札（素材の表に名前・@ユーザー名・MEMBER SINCE・番号を重ねた1枚）と深い影。
///   押すと全画面で手に取って回せる（板 Badge3D: 表と裏・縁は角の丸みまで金の小口）
/// - 「続けた年のメダル」（真鍮の眉ラベル）と右に「12 か月目」、1年目・2年目・3年目のメダル 96pt
///   （届いていないものは色を抜いて 42%）。届いたメダルは押すと手に取って回せる
/// - 注記（板の文言そのまま）
///
/// **v2（2026-10-14・板 SupporterCard）**: 地は黒（v1 の丸いグラデーションは手に取って回す全画面だけに残す）。
/// 題はナビの中央の 17（積む画面の題）。札は少し傾けて置き（`SupporterCardScreen.tilt`）、手に取れることを見せ、
/// 下に「押すと手に取って回せます」の注記。続けた年のメダルは 92 の3列、受け取った年だけ色、まだの年は灰色 40%。
/// 「12 か月目」は数だけ白の等幅（数は合図ではないので真鍮にしない）
struct SupporterCardView: View {

    let profile: UserProfile

    @EnvironmentObject private var store: StoreService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var front: UIImage?
    @State private var viewingCard = false
    @State private var viewingYear: EarnedBadge?

    private var supporter: SupporterInfo? { profile.supporterInfo }

    private var face: SupporterCardFace {
        SupporterCardFace(name: profile.name, handle: profile.username,
                          number: supporter?.number ?? 0, since: SupporterText.since(supporter?.since))
    }

    /// 届いている年のメダルの数。サーバーの `supporterYear` の段と、月の数から数えた段の大きい方
    private var yearsReached: Int {
        SupporterText.yearsReached(months: supporter?.months ?? 0,
                                   badgeTier: profile.earnedBadges["supporterYear"]?.tier)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = SupporterCardLayout.cardWidth(screenWidth: Double(geo.size.width))
            ScrollView {
                VStack(alignment: .leading, spacing: JPSpace.section) {
                    VStack(spacing: JPSpace.l) {
                        card(width: cardWidth)
                        Text(L("押すと手に取って回せます", "Tap to hold it and turn it over"))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .multilineTextAlignment(.center)
                            .accessibilityHidden(true)  // 札の読み上げのヒントと同じ文
                    }
                    .frame(maxWidth: .infinity)
                    yearsSection(width: cardWidth)
                    Text(SupporterText.note(monthlyPrice: store.product(.monthly)?.displayPrice))
                        .font(JPFont.footnote)
                        .lineSpacing(13 * 0.8 - 4)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, JPSpace.xl)
                .padding(.bottom, JPSpace.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // 板 v2: 地は黒（丸いグラデーションは手に取って回す全画面 `SupporterCardViewer` だけ）
        .background { WebTheme.background.ignoresSafeArea() }
        // 板 v2: 題は積む画面の中央の 17（Headline）。v1 は戻るの右の明朝 18
        .navigationTitle(L("サポーター証", "Supporter card"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            guard front == nil else { return }
            front = SupporterCardTextures.front(face)
        }
        .fullScreenCover(isPresented: $viewingCard) {
            SupporterCardViewer(face: face)
        }
        .fullScreenCover(item: $viewingYear) { badge in
            MedalViewerView(badge: badge, ownerName: profile.name)
        }
    }

    // MARK: - 札

    private func card(width: Double) -> some View {
        let height = width / SupporterCardLayout.aspect
        let corner = SupporterCardLayout.cornerRadius * width / SupporterCardLayout.width
        return Button { viewingCard = true } label: {
            Group {
                if let front {
                    Image(uiImage: front).resizable().interpolation(.high)
                } else {
                    // 重ね終える前の一瞬（素材の絵だけ）
                    Image("supporter-card-front").resizable().interpolation(.high)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            // 板: 0 24 48 黒 75%
            .shadow(color: Color.black.opacity(0.75), radius: 24, x: 0, y: 24)
            .contentShape(RoundedRectangle(cornerRadius: corner))
            // 板 v2: 少し傾けて置く（perspective 900・X 6°・Y -8°）。視差効果を減らす人には傾けない
            .rotation3DEffect(.degrees(reduceMotion ? 0 : SupporterCardScreen.tilt.x),
                              axis: (x: 1, y: 0, z: 0), perspective: SupporterCardScreen.tiltPerspective)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : SupporterCardScreen.tilt.y),
                              axis: (x: 0, y: 1, z: 0), perspective: SupporterCardScreen.tiltPerspective)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(face.accessibilityLabel)
        .accessibilityHint(L("押すと手に取って回せます", "Opens the card so you can turn it over"))
        .accessibilityIdentifier("supporter.card")
    }

    // MARK: - 続けた年のメダル

    private func yearsSection(width: Double) -> some View {
        // 板 v2 は 92pt を3つ。狭い端末では間を 8pt 残して縮める
        let side = min(SupporterCardScreen.yearMedalSide, (width - 16) / 3)
        let month = String(SupporterText.monthOrdinal(supporter?.months ?? 0))
        return VStack(alignment: .leading, spacing: JPSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("続けた年のメダル", "Years of support"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: JPSpace.xs)
                // 板 v2: 数だけ白の等幅 semibold、単位は text-2（13）
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(L("", "Month ")).font(JPFont.footnote).foregroundStyle(WebTheme.text2)
                    Text(month)
                        .font(JPFont.number(JPTypeScale.footnote, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.text)
                    Text(L(" か月目", "")).font(JPFont.footnote).foregroundStyle(WebTheme.text2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(month) か月目", "Month \(month)"))
            }
            HStack(alignment: .top) {
                ForEach(1...SupporterText.yearThresholds.count, id: \.self) { year in
                    if year > 1 { Spacer(minLength: 0) }
                    yearMedal(year, side: side)
                }
            }
        }
    }

    private func yearMedal(_ year: Int, side: Double) -> some View {
        let reached = year <= yearsReached
        return Button {
            guard reached else { return }
            // 裏に刻む日付は、いまの段を受け取った日（前の段の日付はサーバーが持っていない）
            let earned = profile.earnedBadges["supporterYear"]
            viewingYear = EarnedBadge(key: "supporterYear", tier: year,
                                      at: earned?.tier == year ? earned?.at : nil)
        } label: {
            VStack(spacing: 8) {
                Image(SupporterText.yearImage(year))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .grayscale(reached ? 0 : 1)
                    // 板 v2: 受け取った年には落ち影
                    .shadow(color: Color.black.opacity(reached ? 0.6 : 0), radius: 6, x: 0, y: 6)
                    .opacity(reached ? 1 : SupporterCardScreen.notReachedOpacity)
                // 板 v2: 字は 13。まだの年は text-3（字は薄めない——4.5:1 を保つ）
                Text(SupporterText.yearLabel(year))
                    .font(JPFont.footnote)
                    .foregroundStyle(reached ? WebTheme.text : WebTheme.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!reached)
        .accessibilityLabel(SupporterText.yearLabel(year) + (reached ? "" : L("（まだ）", " (not yet)")))
        .accessibilityHint(reached ? L("押すと手に取って回せます", "Opens the medal so you can turn it over") : "")
    }
}

/// サポーター証を手に取って回す（板 Badge3D の右の札）。全画面
struct SupporterCardViewer: View {

    let face: SupporterCardFace

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textures: MedalTextures.Faces?
    @State private var flips = 0

    var body: some View {
        GeometryReader { geo in
            // 舞台は硬貨と同じ正方形（カードは舞台の横幅の 9 割ほど・`MedalCoinCoordinator.buildCard`）
            let stage = MedalTextureLayout.coinSide(screenWidth: Double(geo.size.width))
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 20) {
                    Spacer(minLength: 0)
                    MedalCoinView(textures: textures, fallbackImage: "supporter-card-front",
                                  reduceMotion: reduceMotion, flips: flips,
                                  shape: .card(aspect: SupporterCardLayout.aspect))
                        .frame(width: stage, height: stage)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(face.accessibilityLabel)
                        .accessibilityAddTraits(.isImage)
                        .accessibilityAction(named: L("裏返す", "Turn over")) { flips += 1 }
                    VStack(spacing: 8) {
                        Text(L("手に取って回す", "Turn it over"))
                            .jpEyebrow()
                            .foregroundStyle(WebTheme.accent)
                        Text(L("サポーター証", "Supporter card"))
                            .font(JPFont.cardTitle)
                            .foregroundStyle(WebTheme.foreground)
                        Text(SupporterText.numberLabel(face.number))
                            .font(JPFont.mono(12))
                            .foregroundStyle(WebTheme.muted2)
                        Text(L("指で横に払うと裏返ります。", "Swipe sideways to turn it over."))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .jpGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.top, 8)
                .accessibilityLabel(Labels.Common.close)
            }
        }
        .background { SupporterCardStyle.background.ignoresSafeArea() }
        .statusBarHidden(true)
        .task {
            guard textures == nil else { return }
            textures = SupporterCardTextures.make(face)
        }
    }
}

/// サポーター証の画面の見た目（板 64 の値）
@MainActor
enum SupporterCardStyle {
    /// 板: radial-gradient(circle at 50% 22%, #17181B 0%, #050505 48%, #000 70%)。
    /// CSS の円は最も遠い角まで（390×844 の画面で約 690pt）なので、48% ≈ 330・70% ≈ 480
    static var background: some View {
        RadialGradient(stops: [
            Gradient.Stop(color: ProMarkColors.color(0x17181B), location: 0),
            Gradient.Stop(color: ProMarkColors.color(0x050505), location: 0.48),
            Gradient.Stop(color: Color.black, location: 0.70),
            Gradient.Stop(color: Color.black, location: 1),
        ], center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: 690)
    }
}

/// サポーター証の画面の寸法（v2 の板 SupporterCard・2026-10-14）。3D の絵（`SupporterCardTextures`）には触らない
enum SupporterCardScreen {
    /// 画面に置く札の傾き（板: rotateX 6°・rotateY -8°・perspective 900）。手に取れることを見せる。
    /// 視差効果を減らす人には傾けない
    static let tilt: (x: Double, y: Double) = (6, -8)
    /// 傾きの遠近（SwiftUI の perspective は 0〜1。板の 900px を 390pt の画面に当てた弱め）
    static let tiltPerspective: Double = 0.4
    /// 続けた年のメダルの大きさ（v2: 92・v1 は 96）
    static let yearMedalSide: Double = 92
    /// まだの年のメダルの濃さ（v2: 40%・灰色）。字は薄めない
    static let notReachedOpacity: Double = 0.4
}
