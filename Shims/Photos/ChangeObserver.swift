// Photos の「ライブラリが変わった」の知らせの口の模型（2026-10-16・端末の写真の一冊）。
// 本物と同じ名前・形。模型は何もしない（知らせは来ない）
import Foundation

/// ライブラリの変化（本物は何が変わったかを `changeDetails(for:)` で引ける。アプリは使わない）
open class PHChange: NSObject {}

/// 変化を受け取る役。本物の受け口は主の糸ではない糸で呼ばれる
public protocol PHPhotoLibraryChangeObserver: NSObjectProtocol {
    func photoLibraryDidChange(_ changeInstance: PHChange)
}

extension PHPhotoLibrary {
    public func register(_ observer: PHPhotoLibraryChangeObserver) {}
    public func unregisterChangeObserver(_ observer: PHPhotoLibraryChangeObserver) {}
}
