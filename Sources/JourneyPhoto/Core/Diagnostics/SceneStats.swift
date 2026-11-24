import Foundation
#if canImport(SceneKit)
import SceneKit
import UIKit

/// SceneKit の場面の中身の数（測るだけ・見た目は変えない）。
///
/// 2026-11-23 判断（札 #709）: とおまわり号を消すときに、`CamperSceneStats` から引っ越した（数え方は前と同じ）。
/// いまは旅のトランクの回す箱（`MedalViewerView` の `SpinScene`）が、測る起動のときだけ使う。
///
///  - nodes: 木の節の数  geoms: 図形の数（同じ図形を使い回しているものは 1）  inst: 図形を持つ節の数（描く回数の目安）
///  - verts・tris: 図形の頂点・三角の数（重複を除く）  geo_kb: 図形が持つ値の大きさ（頂点・法線・UV・添字の実際のバイト数）
///  - mats: 材質の数  texs: 貼り絵（UIImage・CGImage）の数  tex_mb: 貼り絵を 4 バイト/画素と見たときの合計（ミップ込みは約 1.33 倍）
///  - lights: 光の数
struct SceneStats: Equatable {
    var nodes = 0
    var geometries = 0
    var instances = 0
    var vertices = 0
    var triangles = 0
    var geometryKB = 0.0
    var materials = 0
    var textures = 0
    var textureMB = 0.0
    var lights = 0

    /// 「nodes=… geoms=… …」（UI テストがそのまま 1 行にして残す。値に空白は入れない）
    var fields: String {
        String(format: "nodes=%d geoms=%d inst=%d verts=%d tris=%d geo_kb=%.0f mats=%d texs=%d tex_mb=%.1f lights=%d",
               nodes, geometries, instances, vertices, triangles, geometryKB, materials, textures, textureMB, lights)
    }

    static func measure(_ root: SCNNode) -> SceneStats {
        var s = SceneStats()
        var seenGeometry = Set<ObjectIdentifier>()
        var seenMaterial = Set<ObjectIdentifier>()
        var seenImage = Set<ObjectIdentifier>()
        var geometryBytes = 0
        var textureBytes = 0.0

        func addImage(_ contents: Any?) {
            guard let contents else { return }
            if let image = contents as? UIImage {
                guard seenImage.insert(ObjectIdentifier(image)).inserted else { return }
                s.textures += 1
                textureBytes += Double(image.size.width * image.scale) * Double(image.size.height * image.scale) * 4
            } else if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                let cg = contents as! CGImage
                guard seenImage.insert(ObjectIdentifier(cg as AnyObject)).inserted else { return }
                s.textures += 1
                textureBytes += Double(cg.width) * Double(cg.height) * 4
            }
        }

        func visit(_ node: SCNNode) {
            s.nodes += 1
            if node.light != nil { s.lights += 1 }
            if let geometry = node.geometry {
                s.instances += 1
                if seenGeometry.insert(ObjectIdentifier(geometry)).inserted {
                    s.geometries += 1
                    for source in geometry.sources { geometryBytes += source.data.count }
                    if let position = geometry.sources(for: .vertex).first { s.vertices += position.vectorCount }
                    for element in geometry.elements {
                        geometryBytes += element.data.count
                        if element.primitiveType == .triangles { s.triangles += element.primitiveCount }
                    }
                    for material in geometry.materials where seenMaterial.insert(ObjectIdentifier(material)).inserted {
                        s.materials += 1
                        for property in [material.diffuse, material.normal, material.roughness,
                                         material.metalness, material.emission, material.ambientOcclusion] {
                            addImage(property.contents)
                        }
                    }
                }
            }
            for child in node.childNodes { visit(child) }
        }
        visit(root)
        s.geometryKB = Double(geometryBytes) / 1024
        s.textureMB = textureBytes / 1_048_576
        return s
    }
}
#endif
