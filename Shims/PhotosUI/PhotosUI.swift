// PhotosUI の模型。
import Foundation
import SwiftUI

public struct PhotosPickerItem: Equatable, Hashable {
    public var itemIdentifier: String? { nil }
    public func loadTransferable<T>(type: T.Type) async throws -> T? { nil }
}

public struct PHPhotoLibraryShim {
    public static func shared() -> PHPhotoLibraryShim { PHPhotoLibraryShim() }
}

public struct PHPickerFilter {
    public static let images = PHPickerFilter()
    public static let videos = PHPickerFilter()
}

public struct PhotosPicker: View {
    public init<L: View>(selection: Binding<PhotosPickerItem?>,
                         matching filter: PHPickerFilter? = nil,
                         photoLibrary: PHPhotoLibraryShim? = nil,
                         @ViewBuilder label: () -> L) {}
    /// まとめて選ぶ側（本物にもある）。
    public init<L: View>(selection: Binding<[PhotosPickerItem]>,
                         maxSelectionCount: Int? = nil,
                         matching filter: PHPickerFilter? = nil,
                         photoLibrary: PHPhotoLibraryShim? = nil,
                         @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}

extension View {
    /// 選ぶ画面を旗で開く（本物にもある）。メニューの中に `PhotosPicker` を置くと
    /// 開かないことがあるので、こちらを使う
    public func photosPicker(isPresented: Binding<Bool>,
                             selection: Binding<[PhotosPickerItem]>,
                             maxSelectionCount: Int? = nil,
                             matching filter: PHPickerFilter? = nil) -> some View { self }
}
