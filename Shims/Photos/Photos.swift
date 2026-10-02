// Photos（PhotoKit）の模型。
//
// **足してあるのは、アプリが使う口だけ**（`Services/PhotoLibrary.swift`）。どれも
// 本物の Photos に実在する名前・形で、模型は素通し（許可は決まらず、写真は1枚も無い）。
// 実在しない口をここに置くと、手元では通って実機で落ちる。
import Foundation
import CoreLocation
import ImageIO
import UIKit

/// 写真ライブラリへの許可の段（本物と同じ並び）
public enum PHAuthorizationStatus: Int {
    case notDetermined = 0, restricted, denied, authorized
    /// 一部の写真だけを許可した（iOS 14〜）
    case limited
}

/// 求める許可の範囲（本物と同じ値）。アプリは読むので `.readWrite` だけを使う
public enum PHAccessLevel: Int {
    case addOnly = 1, readWrite = 2
}

public enum PHAssetMediaType: Int {
    case unknown = 0, image, video, audio
}

open class PHPhotoLibrary: NSObject {
    open class func shared() -> PHPhotoLibrary { PHPhotoLibrary() }
    open class func authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus { .notDetermined }
    open class func requestAuthorization(for accessLevel: PHAccessLevel,
                                         handler: @escaping (PHAuthorizationStatus) -> Void) {
        handler(.notDetermined)
    }
    /// 本物では上の口が async に橋渡しされたもの
    open class func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        .notDetermined
    }
}

open class PHObject: NSObject {
    open var localIdentifier: String { "" }
}

open class PHAsset: PHObject {
    open var mediaType: PHAssetMediaType { .unknown }
    open var creationDate: Date? { nil }
    open var location: CLLocation? { nil }
    open var pixelWidth: Int { 0 }
    open var pixelHeight: Int { 0 }

    open class func fetchAssets(with mediaType: PHAssetMediaType, options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        PHFetchResult()
    }
    open class func fetchAssets(withLocalIdentifiers identifiers: [String],
                                options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        PHFetchResult()
    }
}

/// 取り出した結果（本物は遅延で読む配列のようなもの）
open class PHFetchResult<ObjectType: AnyObject>: NSObject {
    open var count: Int { 0 }
    open var firstObject: ObjectType? { nil }
    open func object(at index: Int) -> ObjectType { fatalError("模型") }
}

/// 取り出し方。**`predicate` と `sortDescriptors` は Linux の Foundation で作れない**
/// （キー文字列の `NSSortDescriptor(key:)` が無い）ので、アプリ側は Darwin だけで組む
open class PHFetchOptions: NSObject {
    open var predicate: NSPredicate?
    open var sortDescriptors: [NSSortDescriptor]?
    open var fetchLimit: Int = 0
    public override init() {}
}

public typealias PHImageRequestID = Int32
public let PHInvalidImageRequestID: PHImageRequestID = 0
/// 結果の info の鍵（本物と同じ文字列）
public let PHImageResultIsDegradedKey = "PHImageResultIsDegradedKey"
public let PHImageCancelledKey = "PHImageCancelledKey"
public let PHImageErrorKey = "PHImageErrorKey"
public let PHImageResultIsInCloudKey = "PHImageResultIsInCloudKey"

public enum PHImageContentMode: Int {
    case aspectFit = 0, aspectFill = 1
}

public enum PHImageRequestOptionsDeliveryMode: Int {
    case opportunistic = 0, highQualityFormat = 1, fastFormat = 2
}

public enum PHImageRequestOptionsResizeMode: Int {
    case none = 0, fast, exact
}

public enum PHImageRequestOptionsVersion: Int {
    case current = 0, unadjusted, original
}

open class PHImageRequestOptions: NSObject {
    open var deliveryMode: PHImageRequestOptionsDeliveryMode = .opportunistic
    open var resizeMode: PHImageRequestOptionsResizeMode = .fast
    open var version: PHImageRequestOptionsVersion = .current
    /// iCloud にしか無い写真を落としてよいか
    open var isNetworkAccessAllowed = false
    open var isSynchronous = false
    public override init() {}
}

open class PHImageManager: NSObject {
    open class func `default`() -> PHImageManager { PHImageManager() }
    public override init() {}

    @discardableResult
    open func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
                           options: PHImageRequestOptions?,
                           resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        PHInvalidImageRequestID
    }

    /// 本体（元のファイルの中身）を取る（iOS 13〜）
    @discardableResult
    open func requestImageDataAndOrientation(
        for asset: PHAsset, options: PHImageRequestOptions?,
        resultHandler: @escaping (Data?, String?, CGImagePropertyOrientation, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID {
        PHInvalidImageRequestID
    }

    open func cancelImageRequest(_ requestID: PHImageRequestID) {}
}

/// 先に縮小を作っておける管理役（格子のサムネイル）
open class PHCachingImageManager: PHImageManager {
    open var allowsCachingHighQualityImages = true
    open func startCachingImages(for assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode,
                                 options: PHImageRequestOptions?) {}
    open func stopCachingImages(for assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode,
                                options: PHImageRequestOptions?) {}
    open func stopCachingImagesForAllAssets() {}
}
