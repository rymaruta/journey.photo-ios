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
struct SupporterCardView: View {

    let profile: UserProfile

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
                VStack(alignment: .leading, spacing: 28) {
                    card(width: cardWidth)
                    yearsSection(width: cardWidth)
                    Text(L("番号は申し込んだ順で、同じ番号は二度と出ません。やめても番号とメダルは残り、再開すると続きから数えます。月 ¥500。",
                           "Numbers are given in the order people joined and are never reused. If you stop, your number and medals stay; when you come back, the count continues. ¥500 a month."))
                        .font(.caption)
                        .lineSpacing(12 * 0.7 - 4)
                        .foregroundStyle(WebTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background { SupporterCardStyle.background.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // 板: 戻るの右に明朝 18 の見出し（真ん中には置かない）
            ToolbarItem(placement: .topBarLeading) {
                Text(L("サポーター証", "Supporter card"))
                    .font(JPFont.display(18, relativeTo: .headline))
                    .foregroundStyle(Color.white)
                    .accessibilityAddTraits(.isHeader)
            }
        }
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(face.accessibilityLabel)
        .accessibilityHint(L("押すと手に取って回せます", "Opens the card so you can turn it over"))
        .accessibilityIdentifier("supporter.card")
    }

    // MARK: - 続けた年のメダル

    private func yearsSection(width: Double) -> some View {
        // 板は 96pt を3つ。狭い端末では間を 8pt 残して縮める
        let side = min(96, (width - 16) / 3)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("続けた年のメダル", "Years of support"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Spacer(minLength: 8)
                Text(L("\(SupporterText.monthOrdinal(supporter?.months ?? 0)) か月目",
                       "Month \(SupporterText.monthOrdinal(supporter?.months ?? 0))"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WebTheme.faint)
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
                Text(SupporterText.yearLabel(year))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .opacity(reached ? 1 : 0.42)
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
