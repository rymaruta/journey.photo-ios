import SwiftUI
import PhotosUI
import UIKit

/// 撮影画面と同じ37種類を、撮影前にも学べる読み物として見せる。
/// 図は実際の写真ではなく、カメラに出るガイド線の配置例。
///
/// **v2（2026-10-14・板 Compositions）**: バーの中央は「撮影ガイド」（設定の節の名前）、大見出しは明朝 30 の
/// 「構図一覧」。節の見出しは真鍮の眉ラベルと消えていく線（`JPEyebrowLine`）、行は札に入れず 64 の素の行に
/// 白 8% の区切り線。構図の名前 16 semibold・場面は 12 の text-3
struct CompositionCatalogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                Text(L("構図一覧", "Composition guide"))
                    .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(L("撮りたい場面から構図を選び、線の使い方を確認できます。図はガイド線の例で、実際の写真ではありません。",
                       "Explore ways to frame a scene. Illustrations show guide lines, not actual photographs."))
                    .font(JPFont.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(CompositionSection.allCases) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        JPEyebrowLine(section.title)
                            .padding(.top, JPSpace.xl)
                            .padding(.bottom, JPSpace.xxs)
                        ForEach(section.kinds) { kind in
                            NavigationLink { CompositionExplanationView(kind: kind) } label: {
                                HStack(spacing: 14) {
                                    CompositionThumbnail(kind: kind, cornerRadius: 8)
                                        .frame(width: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(kind.name).font(.callout.weight(.semibold))
                                            .foregroundStyle(WebTheme.text)
                                        Text(CompositionExample.scene(for: kind))
                                            .font(JPFont.caption).foregroundStyle(WebTheme.text3)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                        .foregroundStyle(WebTheme.text3)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 10)
                                .frame(minHeight: JPHeight.tallRow)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(JPRowButtonStyle())
                            .accessibilityIdentifier("composition.catalog.\(kind.rawValue)")
                        }
                    }
                }
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.section)
        }
        .webScreen()
        // 板 v2: バーの中央は設定の節の名前（大見出しの「構図一覧」と二重にしない）
        .navigationTitle(L("撮影ガイド", "Shooting guide"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CompositionExplanationView: View {
    let kind: CompositionKind
    @State private var variant = 0
    @State private var showGuideLines = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var exampleImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                // 板 v2: 明朝 30 の題の右に、難しさの札（12・text-2・白 14% の線）
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(kind.name)
                        .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                        .foregroundStyle(WebTheme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(kind.difficulty.label)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text2)
                        .padding(.horizontal, JPSpace.xs)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: JPRadius.s).strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                }

                // 作例写真は端末内だけで扱う。未選択時は従来の配置図を表示。
                // 板 v2: 線のボタン（44・白 14% の縁）
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(L("自分の写真で構図を確認", "Try with your photo"), systemImage: "photo.on.rectangle")
                        .jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composition.explanation.choosePhoto")

                // 作例の配置図。写真が選ばれた場合は写真の上に同じガイド線を重ねる。
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.20, green: 0.29, blue: 0.32),
                                                Color(red: 0.09, green: 0.12, blue: 0.14)],
                                       startPoint: .top, endPoint: .bottom)
                        if let exampleImage {
                            Image(uiImage: exampleImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else if UIImage(named: "composition-ai-\(kind.rawValue)") != nil {
                            Image("composition-ai-\(kind.rawValue)")
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            Image(systemName: CompositionExample.symbol(for: kind))
                                .font(.system(size: 86, weight: .ultraLight))
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                        if showGuideLines {
                            CompositionOverlay(kind: kind, variant: variant, lineOpacity: 0.7,
                                               levelDegrees: 0, shadowed: false)
                        }
                    }
                    .aspectRatio(0.75, contentMode: .fit)
                    .frame(maxWidth: 270)
                    // 板 v2: 写真の札の角 14
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                    .overlay(RoundedRectangle(cornerRadius: JPRadius.m)
                        .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                    .frame(maxWidth: .infinity)
                    Text(exampleImage != nil
                         ? L("端末内の写真（アップロードされません）", "Photo on your device (not uploaded)")
                         : (UIImage(named: "composition-ai-\(kind.rawValue)") != nil
                            ? CompositionExample.bundledCaption(for: kind)
                            : L("作例の配置図（写真ではありません）", "Example layout (illustration, not a photo)")))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                    Toggle(L("ガイド線を表示", "Show guide lines"), isOn: $showGuideLines)
                        .font(JPFont.body)
                        // 板 v2: 軌道は暗い真鍮（brass-deep）。白いつまみが乗って入切が見える（`JPToggleRow` と同じ）
                        .tint(WebTheme.accentDeep)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .accessibilityIdentifier("composition.explanation.showLines")
                    if kind.hasVariants {
                        Button {
                            variant = kind.nextVariant(after: variant)
                        } label: {
                            Label(L("向き：\(kind.variantName(variant))", "Orientation: \(kind.variantName(variant))"),
                                  systemImage: "rotate.right")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityIdentifier("composition.explanation.variant")
                    }
                }

                explanationSection(L("どんな構図？", "How it works"), text: CompositionExample.explanation(for: kind))
                explanationSection(L("こんな場面で", "Example scene"), text: CompositionExample.scene(for: kind))
                explanationSection(L("撮るときのコツ", "Shooting tip"), text: kind.tip)
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.section)
        }
        .webScreen()
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let image = await Task.detached(priority: .userInitiated) {
                    try? ReferencePhotoLoader.previewJPEG(from: data)
                }.value
                guard let image, let preview = UIImage(data: image) else { return }
                exampleImage = preview
            }
        }
    }

    /// 解説の節（板 v2: 真鍮の眉と消えていく線 → 本文 15・text-2。札に入れない）
    private func explanationSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPEyebrowLine(title)
            Text(text)
                .font(JPFont.body)
                .lineSpacing(5)
                .foregroundStyle(WebTheme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, JPSpace.xs)
    }
}

/// 一覧と詳細で同じ作例・解説を使い、撮影時の線と食い違わないようにする。
enum CompositionExample {
    /// 作例が**実際の写真**の構図（AI 生成ではない）。出典と許諾は
    /// `Tools/composition-examples/photo-sources.json`、確認の記録は `docs/composition-ai-review.json`（source: photo）。
    ///
    /// 2026-10-14 判断（owner）: 文字どおりの形を描いた AI の絵（Z の字の道・線だけの絵）は写真の作例に
    /// なっていなかったので、無料で商用に使え表記の要らない写真（CC0・パブリックドメイン）に替えた。
    /// 写真を「AI生成」と書かない（`CompositionAIExampleTests` が台帳と突き合わせる）
    static let photoKinds: Set<CompositionKind> = [
        .tunnel, .zShape, .rootRectangle, .armature, .diagonal45, .mizige, .tianzige, .obliqueThirds,
        .squareGrid, .ratio4x5, .ratio9x16, .ratio16x9,
    ]

    /// 作例の絵の下の札。写真なら「作例の写真」、AI の絵なら「AI生成」と書く
    static func bundledCaption(for kind: CompositionKind) -> String {
        photoKinds.contains(kind)
            ? L("構図の作例写真", "Composition example photo")
            : L("AI生成の構図作例", "AI-generated composition example")
    }

    static func scene(for kind: CompositionKind) -> String {
        switch kind {
        case .thirds, .iphone: return L("海辺の人物を交点に置く", "Place a person on an intersection by the sea")
        case .halves: return L("水面と空を半分ずつ写す", "Divide a lake and sky equally")
        case .symmetry: return L("建物の正面を中心軸で揃える", "Center a building's facade")
        case .hinomaru: return L("一輪の花を画面の中央に", "Center a single flower")
        case .horizon: return L("夕空を広く見せる海岸", "Show more of the sunset sky above the sea")
        case .grid4, .squareGrid, .grid6x4:
            return L("建物の窓や柱の並びを整える", "Align rows of windows or columns")
        case .tianzige: return L("水辺の建物と映り込みを十字で釣り合わせる", "Balance a waterside building and its reflection on the cross")
        case .mizige: return L("回廊の線が中心の奥へ集まる", "Corridor lines converging on the center")
        case .phiGrid: return L("街角の人物を内寄りの交点に", "Place a person at an inner intersection")
        case .goldenSpiral: return L("曲がる道の先に主役を置く", "Place the subject at the end of a winding path")
        case .fibonacciGrid: return L("階段をたどって奥の扉へ", "Follow stairs toward a distant door")
        case .goldenTriangle: return L("斜面と人物を対角に並べる", "Arrange a slope and person diagonally")
        case .diagonals, .diagonal45, .obliqueThirds: return L("斜めに延びる道や稜線", "A sloping road or mountain ridge")
        case .thirdsDiagonals: return L("道の斜線と奥の人物", "A diagonal road leading to a person")
        case .dynamicSymmetry: return L("交差する街路と建物の輪郭", "Crossing streets and building edges")
        case .armature: return L("橋のケーブルが斜めに集まる", "Bridge cables converging on the diagonals")
        case .rootRectangle: return L("√2に切り出す塔と山", "A pagoda and mountain framed for a √2 crop")
        case .triangle: return L("3人の位置で三角形を作る", "Arrange three people in a triangle")
        case .radial: return L("一点へ集まる線路や光", "Tracks or light converging at one point")
        case .tunnel: return L("鳥居や木のトンネルの奥へ", "Into a tunnel of torii gates or trees")
        case .frameWithin: return L("門の向こうに見える街並み", "A cityscape seen through a gate")
        case .negativeSpace: return L("広い空に小さな鳥を置く", "A small bird against a wide sky")
        case .lShape: return L("岸辺と桟橋でL字を作る", "A shoreline and pier forming an L")
        case .zShape: return L("折り返す道を手前から奥へたどる", "Follow a winding road from near to far")
        case .sCurve: return L("S字に曲がる川の流れ", "An S-shaped river")
        case .cCurve: return L("湾曲する海岸線", "A curved coastline")
        case .square: return L("中央の建物を正方形に収める", "A building composed inside a square")
        case .ratio4x5: return L("縦長に切り出す街並み", "A street scene framed for 4:5")
        case .ratio9x16: return L("縦いっぱいに伸びる塔", "A tall tower in a 9:16 frame")
        case .ratio16x9: return L("横に広がる山並み", "A mountain panorama in 16:9")
        case .otherRatios: return L("横長の街並みを比率で切り出す", "Frame a wide cityscape for the chosen ratio")
        case .level: return L("海や建物の水平を確認する", "Level the sea or building edges")
        }
    }

    static func explanation(for kind: CompositionKind) -> String {
        switch kind {
        case .thirds, .iphone: return L("画面を縦横それぞれ三等分します。主役を交点に置くと、周りの景色も伝えやすくなります。",
                                         "Divide the frame into thirds. An intersection leaves room for context.")
        case .halves: return L("中央の十字で画面を分けます。対になる形や明暗を比べたいときに使います。",
                                "Split the frame at the center to compare paired shapes or tones.")
        case .symmetry: return L("中央の縦線・横線を対称軸にします。両側の形や余白が釣り合う位置を探します。",
                                  "Use the center line as an axis and balance both sides.")
        case .hinomaru: return L("主役を中央に置きます。背景を整理すると、視線が迷わず主役に集まります。",
                                 "Center the subject and simplify the background to draw attention to it.")
        case .horizon: return L("水平線を上か下の三分割線へ。見せたい方に画面の三分の二を使います。",
                                "Place the horizon on an upper or lower third and give more room to the stronger half.")
        case .grid4, .squareGrid, .grid6x4: return L("細かい格子で傾きや間隔を確認します。線を全部使う必要はありません。",
                                                        "Use the grid to check alignment and spacing; you need not match every line.")
        case .tianzige: return L("外枠と中心の十字で、主役と四隅の重さを見比べます。",
                                 "Use the outer frame and cross to balance the center and corners.")
        case .mizige: return L("中心へ集まる十字と対角線を見て、形の流れを整えます。",
                                "Use the cross and diagonals to organize lines toward the center.")
        case .phiGrid: return L("黄金比で分けた線です。三分割より中心に近い交点を目安にします。",
                                "Golden-ratio divisions put the intersections nearer the center than thirds.")
        case .goldenSpiral: return L("曲線の終点に主役を置き、周囲の流れを渦に沿わせます。",
                                    "Place the subject at the spiral's eye and let surrounding lines lead toward it.")
        case .fibonacciGrid: return L("小さくなる区画へ視線を導きます。段階的に奥へ続く景色に向きます。",
                                     "Lead the eye through successively smaller areas toward the subject.")
        case .goldenTriangle: return L("対角線と両端から下ろした線で画面を分けます。交点を主役の目安にします。",
                                      "Use the diagonal and its crossing lines to locate the subject.")
        case .diagonals, .diagonal45: return L("画面を斜めに横切る線を使います。道や斜面の方向を強調できます。",
                                                  "A diagonal emphasizes the direction of a road or slope.")
        case .thirdsDiagonals: return L("三分割の交点に主役を置き、斜めの線でそこへ視線を導きます。",
                                       "Position the subject on thirds and use diagonals to lead toward it.")
        case .obliqueThirds: return L("斜めの帯で画面を分けるアプリ独自の補助線です。傾いた輪郭の整理に使います。",
                                      "An app-specific slanted-thirds guide to organize angled outlines.")
        case .dynamicSymmetry: return L("長方形の対角線と逆対角線が交わる点を使います。複数の方向を整理できます。",
                                        "Intersecting diagonals help organize several directions within a rectangle.")
        case .armature: return L("対角線・ひし形・角から中点への線を重ねます。形が多い場面では一部だけを目安に。",
                                 "A network of diagonals and midpoints; use only the lines that help a busy scene.")
        case .rootRectangle: return L("√2比率の切り出し枠とその中の対角線です。明るい範囲に主役を収めます。",
                                     "Compose within a √2 crop, using its diagonals as placement cues.")
        case .triangle: return L("三つの主役を結んで三角形を作ります。上向きは安定、逆向きは緊張感が出ます。",
                                 "Three subjects form a triangle: upright feels stable, inverted more tense.")
        case .radial: return L("線が一点へ集まる場所を探します。中心を変えると主役を端にも置けます。",
                               "Find lines converging at one point; move the center to position the subject.")
        case .tunnel: return L("アーチのような形で奥の主役を囲みます。手前と奥の距離も伝えられます。",
                               "Surround a distant subject with an arch to show depth.")
        case .frameWithin: return L("窓や門などを手前の枠にします。その中に奥の景色を収めます。",
                                    "Use a window or gate as a foreground frame around a distant scene.")
        case .negativeSpace: return L("主役を小さく置き、周囲の空間を広く残します。余白も写真の一部です。",
                                      "Keep the subject small and let the surrounding empty area contribute.")
        case .lShape: return L("二つの線が直角に曲がる形を探し、視線の行き止まりに主役を置きます。",
                               "Find two lines bending at a right angle and place the subject near their meeting point.")
        case .zShape: return L("視線が折り返しながら奥へ進む線を探します。",
                               "Look for a zigzag that carries the eye deeper into the scene.")
        case .sCurve: return L("ゆるやかな二つの曲がりで、手前から奥へ視線を導きます。",
                               "Two gentle bends guide the eye from foreground to distance.")
        case .cCurve: return L("大きな一つの曲線で主役の周りを包みます。",
                               "A single broad curve wraps around the subject.")
        case .square, .ratio4x5, .ratio9x16, .ratio16x9, .otherRatios:
            return L("明るい部分が切り出し後の目安です。暗い部分は構図に含めず、撮影画像自体は切り抜きません。",
                     "The bright area previews a crop. The camera still saves the full, uncropped photo.")
        case .level: return L("傾きに応じて線が動き、水平に近づくと太くなります。景色の水平を揃える補助です。",
                              "The line responds to tilt and thickens near level, helping keep horizons straight.")
        }
    }

    static func symbol(for kind: CompositionKind) -> String {
        switch kind.section {
        case .classic: return "mountain.2"
        case .golden: return "point.topleft.down.curvedto.point.bottomright.up"
        case .diagonal: return "road.lanes"
        case .shape: return "tree"
        case .ratio: return "building.2"
        case .device: return "camera"
        }
    }
}
