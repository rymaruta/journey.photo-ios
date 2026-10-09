// Photos の「写真を足す」口の模型（2026-10-09・「作例を重ねて撮る」で撮った1枚を保存する）。
// 本物と同じ名前・形。模型は何もしない（写真は増えない）
import Foundation

extension PHPhotoLibrary {
    /// 変更をまとめて行う。本物は完了の受け手つきの口が async に橋渡しされたもの（失敗は投げる）
    public func performChanges(_ changeBlock: @escaping () -> Void) async throws {}
}

open class PHAssetChangeRequest: NSObject {}

/// 写真を1枚つくる要求。中身（ファイルの中身）を足して作る
open class PHAssetCreationRequest: PHAssetChangeRequest {
    open class func forAsset() -> PHAssetCreationRequest { PHAssetCreationRequest() }
    open func addResource(with type: PHAssetResourceType, data: Data, options: PHAssetResourceCreationOptions?) {}
}

/// 中身の種類（本物と同じ値）
public enum PHAssetResourceType: Int {
    case photo = 1, video, audio, alternatePhoto
}

open class PHAssetResourceCreationOptions: NSObject {
    public override init() {}
}
