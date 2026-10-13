import SwiftUI
import PhotosUI
import UIKit

/// 撮影画面と同じ37種類を、撮影前にも学べる読み物として見せる。
/// 図は実際の写真ではなく、カメラに出るガイド線の配置例。
struct CompositionCatalogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("構図一覧", "Composition guide"))
                    .font(JPFont.display(30, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(L("撮りたい場面から構図を選び、線の使い方を確認できます。図はガイド線の例で、実際の写真ではありません。",
                       "Explore ways to frame a scene. Illustrations show guide lines, not actual photographs."))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                ForEach(CompositionSection.allCases) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        JPSectionTitle(section.title)
                        JPCard {
                            ForEach(section.kinds) { kind in
                                if kind != section.kinds.first { JPCardDivider() }
                                NavigationLink { CompositionExplanationView(kind: kind) } label: {
                                    HStack(spacing: 14) {
                                        CompositionThumbnail(kind: kind, cornerRadius: 5)
                                            .frame(width: 44)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(kind.name).font(.subheadline.weight(.semibold))
                                                .foregroundStyle(WebTheme.text)
                                            Text(CompositionExample.scene(for: kind))
                                                .font(.caption).foregroundStyle(WebTheme.muted2)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                            .foregroundStyle(WebTheme.faint)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 64)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(JPRowButtonStyle())
                                .accessibilityIdentifier("composition.catalog.\(kind.rawValue)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(L("構図一覧", "Composition guide"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CompositionExplanationView: View {
    let kind: CompositionKind
    @State private var variant = 0
    @State private var showGuideLines = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var exampleImage: UIImage?
    @State private var useCuratedExample = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(kind.name)
                    .font(JPFont.display(30, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(kind.difficulty.label)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)

                // 作例写真は端末内だけで扱う。未選択時は従来の配置図を表示。
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(L("自分の写真で構図を確認", "Try with your photo"), systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("composition.explanation.choosePhoto")

                if CompositionCuratedPhoto.forKind(kind) != nil {
                    Toggle(L("用意された作例を表示", "Show curated example"), isOn: $useCuratedExample)
                        .tint(WebTheme.accent)
                }
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
                        } else if useCuratedExample, let curated = CompositionCuratedPhoto.forKind(kind) {
                            AsyncImage(url: curated.imageURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WebTheme.border, lineWidth: 1))
                    .frame(maxWidth: .infinity)
                    Text(exampleImage != nil
                         ? L("端末内の写真（アップロードされません）", "Photo on your device (not uploaded)")
                         : (useCuratedExample && CompositionCuratedPhoto.forKind(kind) != nil
                            ? L("実写作例（ガイド線は構図の目安です）", "Real photo example (guide lines are illustrative)")
                            : L("作例の配置図（写真ではありません）", "Example layout (illustration, not a photo)")))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                    Toggle(L("ガイド線を表示", "Show guide lines"), isOn: $showGuideLines)
                        .tint(WebTheme.accent)
                        .accessibilityIdentifier("composition.explanation.showLines")
                    if exampleImage == nil, useCuratedExample, let curated = CompositionCuratedPhoto.forKind(kind) {
                        Link(destination: curated.sourceURL) {
                            Text(curated.credit)
                                .font(.caption)
                                .foregroundStyle(WebTheme.accent)
                        }
                    }
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
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                exampleImage = image
            }
        }
    }

    private func explanationSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            JPSectionTitle(title)
            JPCard {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }
}

/// 一覧と詳細で同じ作例・解説を使い、撮影時の線と食い違わないようにする。
enum CompositionExample {
    static func scene(for kind: CompositionKind) -> String {
        switch kind {
        case .thirds, .iphone: return L("海辺の人物を交点に置く", "Place a person on an intersection by the sea")
        case .halves: return L("水面と空を半分ずつ写す", "Divide a lake and sky equally")
        case .symmetry: return L("建物の正面を中心軸で揃える", "Center a building's facade")
        case .hinomaru: return L("一輪の花を画面の中央に", "Center a single flower")
        case .horizon: return L("夕空を広く見せる海岸", "Show more of the sunset sky above the sea")
        case .grid4, .squareGrid, .tianzige, .mizige, .grid6x4:
            return L("建物の窓や柱の並びを整える", "Align rows of windows or columns")
        case .phiGrid: return L("街角の人物を内寄りの交点に", "Place a person at an inner intersection")
        case .goldenSpiral: return L("曲がる道の先に主役を置く", "Place the subject at the end of a winding path")
        case .fibonacciGrid: return L("階段をたどって奥の扉へ", "Follow stairs toward a distant door")
        case .goldenTriangle: return L("斜面と人物を対角に並べる", "Arrange a slope and person diagonally")
        case .diagonals, .diagonal45, .obliqueThirds: return L("斜めに延びる道や稜線", "A sloping road or mountain ridge")
        case .thirdsDiagonals: return L("道の斜線と奥の人物", "A diagonal road leading to a person")
        case .dynamicSymmetry, .armature: return L("交差する街路と建物の輪郭", "Crossing streets and building edges")
        case .rootRectangle: return L("√2に切り出す街並み", "A cityscape framed for a √2 crop")
        case .triangle: return L("3人の位置で三角形を作る", "Arrange three people in a triangle")
        case .radial: return L("一点へ集まる線路や光", "Tracks or light converging at one point")
        case .tunnel: return L("木のトンネルの奥に人物", "A person beyond a tunnel of trees")
        case .frameWithin: return L("門の向こうに見える街並み", "A cityscape seen through a gate")
        case .negativeSpace: return L("広い空に小さな鳥を置く", "A small bird against a wide sky")
        case .lShape: return L("岸辺と桟橋でL字を作る", "A shoreline and pier forming an L")
        case .zShape: return L("折り返す山道をたどる", "A winding mountain path")
        case .sCurve: return L("S字に曲がる川の流れ", "An S-shaped river")
        case .cCurve: return L("湾曲する海岸線", "A curved coastline")
        case .square: return L("中央の建物を正方形に収める", "A building composed inside a square")
        case .ratio4x5: return L("縦長に切り出す人物写真", "A portrait framed for 4:5")
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


/// 出典と利用条件を確認した写真のみ登録。未登録の構図は従来の配置図に戻す。
private struct CompositionCuratedPhoto {
    let imageURL: URL
    let sourceURL: URL
    let credit: String

    static func forKind(_ kind: CompositionKind) -> Self? {
        let filename: String
        let credit: String
        switch kind {
        case .symmetry:
            filename = "A example of symmetry in a building.jpg"
            credit = "Photo: 235x / Wikimedia Commons / CC0 1.0"
        case .goldenSpiral:
            filename = "Golden spiral on a shell.jpg"
            credit = "Photo: Suyothami / Wikimedia Commons / CC BY-SA 4.0"
        case .sCurve, .cCurve:
            filename = "Winding Road (Unsplash).jpg"
            credit = "Photo: Adam Torres / Wikimedia Commons (see source for license)"
        default:
            return nil
        }
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        guard let source = URL(string: "https://commons.wikimedia.org/wiki/File:" + encoded),
              let image = URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/" + encoded + "?width=900") else { return nil }
        return Self(imageURL: image, sourceURL: source, credit: credit)
    }
}
