// SceneKit の模型（2026-10-18・写真で作るキャンピングカー `CamperSceneView` を Linux で型検査するため）。
//
// **名前は SceneKitShim**（SceneKit ではない）。`canImport(SceneKit)` を真にすると、既存のメダルの画面
// （`MedalViewerView`）の SceneKit の枝まで Linux で組むことになるので、キャンピングカーだけが
// `#elseif canImport(SceneKitShim)` で読む。実機のビルドには入らない（Xcode は project.yml から作られ、Package を見ない）。
//
// 形（名前・引数ラベル・型）だけを本物に合わせる。**ここが本物と違うと、Linux で通っても Xcode で落ちる。**
// 足すときは Apple の SceneKit の宣言と同じ形にする。
import Foundation
import UIKit
import ImageIO

public struct SCNVector3: Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
    public init(x: Float, y: Float, z: Float) { self.init(x, y, z) }
}

public struct SCNVector4: Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

public typealias SCNQuaternion = SCNVector4

public struct SCNMatrix4 {
    public init() {}
}

public func SCNMatrix4MakeScale(_ sx: Float, _ sy: Float, _ sz: Float) -> SCNMatrix4 { SCNMatrix4() }
public func SCNMatrix4MakeTranslation(_ tx: Float, _ ty: Float, _ tz: Float) -> SCNMatrix4 { SCNMatrix4() }
public func SCNMatrix4Mult(_ a: SCNMatrix4, _ b: SCNMatrix4) -> SCNMatrix4 { SCNMatrix4() }

public enum SCNWrapMode: Int { case clamp = 1, `repeat` = 2, clampToBorder = 3, mirror = 4 }
public enum SCNFilterMode: Int { case none = 0, nearest = 1, linear = 2 }
public enum SCNTransparencyMode: Int { case aOne = 0, rgbZero = 1, singleLayer = 2, dualLayer = 3 }
public enum SCNBlendMode: Int { case alpha = 0, add = 1, subtract, multiply, screen, replace, max }
public enum SCNAntialiasingMode: UInt { case none = 0, multisampling2X, multisampling4X }
public enum SCNShadowMode: Int { case forward = 0, deferred = 1, modulated = 2 }
public enum SCNGeometryPrimitiveType: Int { case triangles = 0, triangleStrip, line, point, polygon }

open class SCNMaterialProperty {
    public init() {}
    open var contents: Any?
    open var intensity: CGFloat = 1
    open var contentsTransform = SCNMatrix4()
    open var wrapS: SCNWrapMode = .clamp
    open var wrapT: SCNWrapMode = .clamp
    open var mipFilter: SCNFilterMode = .none
}

open class SCNMaterial {
    public struct LightingModel: Equatable {
        let raw: String
        public static let phong = LightingModel(raw: "phong")
        public static let blinn = LightingModel(raw: "blinn")
        public static let lambert = LightingModel(raw: "lambert")
        public static let constant = LightingModel(raw: "constant")
        public static let physicallyBased = LightingModel(raw: "physicallyBased")
    }
    public init() {}
    open var lightingModel: LightingModel = .blinn
    public let diffuse = SCNMaterialProperty()
    public let metalness = SCNMaterialProperty()
    public let roughness = SCNMaterialProperty()
    public let clearCoat = SCNMaterialProperty()
    public let clearCoatRoughness = SCNMaterialProperty()
    public let emission = SCNMaterialProperty()
    public let normal = SCNMaterialProperty()
    public let specular = SCNMaterialProperty()
    public let multiply = SCNMaterialProperty()
    open var transparency: CGFloat = 1
    open var transparencyMode: SCNTransparencyMode = .aOne
    open var blendMode: SCNBlendMode = .alpha
    open var isDoubleSided = false
    open var writesToDepthBuffer = true
    open var readsFromDepthBuffer = true
    open var shaderModifiers: [SCNShaderModifierEntryPoint: String]?
}

public struct SCNShaderModifierEntryPoint: Hashable {
    let raw: String
    public static let geometry = SCNShaderModifierEntryPoint(raw: "geometry")
    public static let surface = SCNShaderModifierEntryPoint(raw: "surface")
    public static let lightingModel = SCNShaderModifierEntryPoint(raw: "lightingModel")
    public static let fragment = SCNShaderModifierEntryPoint(raw: "fragment")
}

open class SCNGeometrySource {
    public struct Semantic: Hashable {
        let raw: String
        public static let vertex = Semantic(raw: "vertex")
        public static let normal = Semantic(raw: "normal")
        public static let texcoord = Semantic(raw: "texcoord")
    }
    public init(data: Data, semantic: Semantic, vectorCount: Int, usesFloatComponents: Bool, componentsPerVector: Int,
                bytesPerComponent: Int, dataOffset: Int, dataStride: Int) {}
    public init(vertices: [SCNVector3]) {}
    public init(normals: [SCNVector3]) {}
    public init(textureCoordinates: [CGPoint]) {}
}

open class SCNGeometryElement {
    public init<IndexType: FixedWidthInteger>(indices: [IndexType], primitiveType: SCNGeometryPrimitiveType) {}
}

open class SCNGeometry {
    public init() {}
    public init(sources: [SCNGeometrySource], elements: [SCNGeometryElement]?) {}
    open var materials: [SCNMaterial] = []
    open var boundingBox: (min: SCNVector3, max: SCNVector3) { (SCNVector3(0, 0, 0), SCNVector3(0, 0, 0)) }
}

open class SCNBox: SCNGeometry {
    public init(width: CGFloat, height: CGFloat, length: CGFloat, chamferRadius: CGFloat) { super.init() }
    open var chamferSegmentCount = 5
}

open class SCNCylinder: SCNGeometry {
    public init(radius: CGFloat, height: CGFloat) { super.init() }
    open var radialSegmentCount = 48
}

open class SCNTorus: SCNGeometry {
    public init(ringRadius: CGFloat, pipeRadius: CGFloat) { super.init() }
    open var ringSegmentCount = 48
    open var pipeSegmentCount = 24
}

open class SCNSphere: SCNGeometry {
    public init(radius: CGFloat) { super.init() }
    open var segmentCount = 48
}

open class SCNPlane: SCNGeometry {
    public init(width: CGFloat, height: CGFloat) { super.init() }
}

open class SCNFloor: SCNGeometry {
    public override init() { super.init() }
    open var reflectivity: CGFloat = 0.25
    open var reflectionFalloffEnd: CGFloat = 0
    open var reflectionResolutionScaleFactor: CGFloat = 0.5
    open var width: CGFloat = 0
    open var length: CGFloat = 0
}

open class SCNText: SCNGeometry {
    public init(string: Any?, extrusionDepth: CGFloat) { super.init() }
    open var font: UIFont!
    open var flatness: CGFloat = 0.6
}

open class SCNLight {
    public struct LightType: Equatable {
        let raw: String
        public static let ambient = LightType(raw: "ambient")
        public static let omni = LightType(raw: "omni")
        public static let directional = LightType(raw: "directional")
        public static let spot = LightType(raw: "spot")
    }
    public init() {}
    open var type: LightType = .omni
    open var color: Any = UIColor.white
    open var intensity: CGFloat = 1000
    open var castsShadow = false
    open var shadowMode: SCNShadowMode = .forward
    open var shadowColor: Any = UIColor.black
    open var shadowRadius: CGFloat = 3
    open var shadowSampleCount = 0
    open var shadowMapSize = CGSize(width: 0, height: 0)
    open var automaticallyAdjustsShadowProjection = true
    open var attenuationStartDistance: CGFloat = 0
    open var attenuationEndDistance: CGFloat = 0
    open var attenuationFalloffExponent: CGFloat = 2
    open var categoryBitMask = -1
    open var spotInnerAngle: CGFloat = 0
    open var spotOuterAngle: CGFloat = 45
}

open class SCNCamera {
    public init() {}
    open var fieldOfView: CGFloat = 60
    open var zNear: Double = 1
    open var zFar: Double = 100
    open var wantsHDR = false
    open var wantsExposureAdaptation = true
    open var bloomIntensity: CGFloat = 0
    open var exposureOffset: CGFloat = 0
    open var bloomThreshold: CGFloat = 1
    open var bloomBlurRadius: CGFloat = 4
    open var screenSpaceAmbientOcclusionIntensity: CGFloat = 0
}

open class SCNNode {
    public init() {}
    public init(geometry: SCNGeometry?) { self.geometry = geometry }
    open var geometry: SCNGeometry?
    open var camera: SCNCamera?
    open var light: SCNLight?
    open var position = SCNVector3(0, 0, 0)
    open var orientation = SCNQuaternion(0, 0, 0, 1)
    open var eulerAngles = SCNVector3(0, 0, 0)
    open var scale = SCNVector3(1, 1, 1)
    open var pivot = SCNMatrix4()
    open var castsShadow = true
    open var opacity: CGFloat = 1
    open var renderingOrder = 0
    open var categoryBitMask = 1
    open var name: String?
    open var isHidden = false
    // 試験で組み上げた場面をたどれるよう、子と親は本当に覚える
    public private(set) var childNodes: [SCNNode] = []
    /// 試験で確かめられるよう、走らせている動きの鍵を覚える
    public private(set) var actionKeys: [String] = []
    open func runAction(_ action: SCNAction, forKey key: String?) { if let key, !actionKeys.contains(key) { actionKeys.append(key) } }
    open func removeAction(forKey key: String) { actionKeys.removeAll { $0 == key } }
    public private(set) weak var parent: SCNNode?
    open func addChildNode(_ child: SCNNode) {
        child.removeFromParentNode()
        child.parent = self
        childNodes.append(child)
    }
    open func removeFromParentNode() {
        parent?.childNodes.removeAll { $0 === self }
        parent = nil
    }
    open func flattenedClone() -> Self { self }
    /// 本物は親をたどって座標を写す。模型は位置を足すだけ（回り・大きさは見ない）
    open func convertPosition(_ position: SCNVector3, to node: SCNNode?) -> SCNVector3 {
        var p = position, n: SCNNode? = self
        while let c = n, c !== node {
            p = SCNVector3(p.x + c.position.x, p.y + c.position.y, p.z + c.position.z)
            n = c.parent
        }
        return p
    }
}

open class SCNScene {
    public init() {}
    public let rootNode = SCNNode()
    public let lightingEnvironment = SCNMaterialProperty()
    public let background = SCNMaterialProperty()
}

open class SCNView: UIView {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public init(frame: CGRect, options: [String: Any]?) { super.init(frame: frame) }
    open var scene: SCNScene?
    open var pointOfView: SCNNode?
    open var antialiasingMode: SCNAntialiasingMode = .multisampling4X
    open var preferredFramesPerSecond = 60
    open var rendersContinuously = false
    /// 模型は画面に写さない（z 0 を返す＝画面の外として扱われる）
    open func projectPoint(_ point: SCNVector3) -> SCNVector3 { SCNVector3(0, 0, 0) }
}

/// 画面の外で描いて絵にする（本物は `init(device: MTLDevice?, options:)`。家具の接写の一覧・2026-10-21）
open class SCNRenderer {
    public init(device: Any?, options: [AnyHashable: Any]?) {}
    open var scene: SCNScene?
    open var pointOfView: SCNNode?
    open func snapshot(atTime time: Double, with size: CGSize, antialiasingMode: SCNAntialiasingMode) -> UIImage { UIImage() }
}

open class SCNTransaction {
    public static func begin() {}
    public static func commit() {}
    nonisolated(unsafe) public static var animationDuration: Double = 0
    nonisolated(unsafe) public static var animationTimingFunction: CAMediaTimingFunction?
}

/// 本物は QuartzCore（UIKit が再輸出する）
open class CAMediaTimingFunction {
    public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {}
}

// MARK: - 画素から絵を作る（本物は CoreGraphics）

public final class CGDataProvider {
    public init?(data: CFData) {}
}

public enum CGColorRenderingIntent: Int32 { case defaultIntent = 0, absoluteColorimetric, relativeColorimetric, perceptual, saturation }

extension CGImage {
    public convenience init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
                             space: CGColorSpace, bitmapInfo: CGBitmapInfo, provider: CGDataProvider, decode: UnsafePointer<CGFloat>?,
                             shouldInterpolate: Bool, intent: CGColorRenderingIntent) {
        self.init()
    }
}

open class SCNAction {
    public init() {}
    open class func customAction(duration seconds: Double, action block: @escaping (SCNNode, CGFloat) -> Void) -> SCNAction { SCNAction() }
    open class func repeatForever(_ action: SCNAction) -> SCNAction { SCNAction() }
}
