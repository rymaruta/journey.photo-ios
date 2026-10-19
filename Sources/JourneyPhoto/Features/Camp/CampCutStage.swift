import SwiftUI
import UIKit

/// 「2 切り出す」の写真（板 CampCapture の s2）。
///
/// - 撮った写真をそのまま後ろに置き、62% 暗くする
/// - 切った 3 枚（奥・中・手前）を、紙の白いフチ（#d9d2c2 の 17 と #f7f4ec の 14）と落ち影（ぼかし 9・(4, 16)・黒 85%）
///   を付けて、少しずつ持ち上げる（板: 奥 (−8, −30)・中 (0, −10)・手前 (8, 14)。写真の画素で、板の倍率 0.74）
/// - 持ち上がる動き: 0.6 秒の ease-out（板の `ccLift`: 6 下から）
/// - 3 枚の右に「奥・中・手前」の札（細い線と点・黒 62% の丸い札）
///
/// 板の寸法（390 × 844）で、切り抜いた範囲の幅 360 を 266.4pt（0.74 倍）に、左を 42.8pt・奥の 1 枚の上を 132pt に置く
struct CampCutStage: View {
    let result: CampCutResult
    let size: CGSize
    let lifted: Bool

    /// 板の寸法での置き場所（幅 390 に対して）
    static let boardScale = 0.74
    static let left = 42.8
    static let farTop = 132.0
    /// 3 枚の持ち上げ（写真の画素 × 0.74 = 板の pt）
    static let lifts: [(Double, Double)] = [(-8, -30), (0, -10), (8, 14)]

    private var k: Double { Double(size.width) / 390 }
    /// 切り抜いた範囲の 1 単位（幅 360）あたりの pt
    private var unit: Double { Self.boardScale * k }
    private var cropOrigin: CGPoint {
        CGPoint(x: Self.left * k, y: Self.farTop * Double(size.height) / 844 - (result.layers.layers.first?.top ?? 0) * unit)
    }
    /// 写真の 1 画素あたりの pt
    private var photoScale: Double {
        let cropWidth = Double(result.cropRect.width)
        return cropWidth > 0 ? unit * result.layers.width / cropWidth : 1
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            photo
            Color.black.opacity(0.62)
            ForEach(Array(result.layers.layers.enumerated()), id: \.offset) { i, layer in
                card(i, layer)
                    .offset(y: lifted ? 0 : 6 * k)
            }
            ForEach(Array(result.layers.layers.enumerated()), id: \.offset) { i, layer in
                tag(i, layer)
            }
            LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
            LinearGradient(colors: [Color.black.opacity(0), Color.black], startPoint: .top, endPoint: .bottom)
                .frame(height: 120 * k)
                .offset(y: 470 * Double(size.height) / 844)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("撮った写真が、木の並びに沿って奥・中・手前の 3 枚の切り絵に分かれ、白い紙のフチをつけて浮き上がっている。後ろの写真は暗く沈んでいる",
                              "Your photo split along the tree lines into back, middle and front paper cutouts with white rims, lifted above the darkened photo"))
        .accessibilityIdentifier("camp.capture.cut")
    }

    private var photoFrame: CGRect {
        let s = photoScale
        return CGRect(x: Double(cropOrigin.x) - Double(result.cropRect.minX) * s,
                      y: Double(cropOrigin.y) - Double(result.cropRect.minY) * s,
                      width: Double(result.photo.size.width) * s, height: Double(result.photo.size.height) * s)
    }

    private var photo: some View {
        let f = photoFrame
        return Image(uiImage: result.photo)
            .resizable()
            .frame(width: f.width, height: f.height)
            .offset(x: f.minX, y: f.minY)
    }

    /// 札の座標（u, v）を画面の点へ（持ち上げつき）
    private func point(_ c: CampVec2, layer: CampCutLayer, index: Int) -> CGPoint {
        let lift = Self.lifts[min(index, 2)]
        let x = Double(cropOrigin.x) + (c.x - CampCutLayers.margin) * unit + lift.0 * Self.boardScale * k
        let y = Double(cropOrigin.y) + (layer.top + c.y - CampCutLayers.margin) * unit + lift.1 * Self.boardScale * k
        return CGPoint(x: x, y: y)
    }

    private func card(_ i: Int, _ layer: CampCutLayer) -> some View {
        let pts = CampCutLayers.photoOutline(layer).map { point($0, layer: layer, index: i) }
        let shape = CampPolygon(points: pts)
        let lift = Self.lifts[min(i, 2)]
        let f = photoFrame
        let scale = Self.boardScale * k
        return ZStack(alignment: .topLeading) {
            // 落ち影（板: 黒 85%・縁 16・ぼかし 9・(4, 16)）
            ZStack {
                shape.fill(Color.black.opacity(0.85))
                shape.stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 16 * scale, lineJoin: .round))
            }
            .blur(radius: 9 * scale)
            .offset(x: 4 * scale, y: 16 * scale)
            // 紙のフチ（縁の影の色 → 紙）
            shape.fill(CampPalette.color(0xD9D2C2))
            shape.stroke(CampPalette.color(0xD9D2C2), style: StrokeStyle(lineWidth: 17 * scale, lineJoin: .round))
            shape.fill(CampPalette.color(0xF7F4EC))
            shape.stroke(CampPalette.color(0xF7F4EC), style: StrokeStyle(lineWidth: 14 * scale, lineJoin: .round))
            // 写真を稜線で切ったもの
            Image(uiImage: result.photo)
                .resizable()
                .frame(width: f.width, height: f.height)
                .offset(x: f.minX + lift.0 * scale, y: f.minY + lift.1 * scale)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 「奥・中・手前」の札（稜線の右寄り u = 0.68 の点から右へ 24 の線、黒 62% の丸い札）
    private func tag(_ i: Int, _ layer: CampCutLayer) -> some View {
        let index = min(layer.points.count - 1, Int(Double(layer.points.count - 1) * 0.68))
        let p = point(CampVec2(layer.points[index].x + CampCutLayers.margin, layer.points[index].y + CampCutLayers.margin),
                      layer: layer, index: i)
        let label = [L("奥", "Back"), L("中", "Middle"), L("手前", "Front")][min(i, 2)]
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: p)
                path.addLine(to: CGPoint(x: p.x + 24, y: p.y))
            }
            .stroke(Color.white.opacity(0.7), lineWidth: 1)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .offset(x: p.x - 2.5, y: p.y - 2.5)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .frame(minWidth: 30, minHeight: 22)
                .background { Capsule().fill(Color.black.opacity(0.62)) }
                .offset(x: p.x + 26, y: p.y - 11)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 点を結んだ多角形（画面の座標のまま）
struct CampPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for q in points.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }
}
