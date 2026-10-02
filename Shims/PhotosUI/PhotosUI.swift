// PhotosUI の模型。
import Foundation
import SwiftUI
import UIKit
import Photos

/// 一部だけ許可した人が「写真を追加で選ぶ」画面（本物は PhotosUI が PHPhotoLibrary に足す口・iOS 15〜）。
/// 返すのは選び終えたあとに許可されている写真の id
extension PHPhotoLibrary {
    public func presentLimitedLibraryPicker(from controller: UIViewController) async -> [String] { [] }
}

public struct PhotosPickerItem: Equatable, Hashable {
    public let itemIdentifier: String?
    /// 本物にもある（iOS 16〜）。試験で別々の写真を作るのに使う
    public init(itemIdentifier: String) { self.itemIdentifier = itemIdentifier }
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
    /// 選んだ順を覚える版（本物にもある・iOS 16〜）。ストーリーの「写真を選ぶ」画面に埋め込む
    public init<L: View>(selection: Binding<[PhotosPickerItem]>,
                         maxSelectionCount: Int? = nil,
                         selectionBehavior: PhotosPickerSelectionBehavior,
                         matching filter: PHPickerFilter? = nil,
                         @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}

/// 選んだ順の扱い（本物にもある・iOS 16〜）
public struct PhotosPickerSelectionBehavior {
    public static let `default` = PhotosPickerSelectionBehavior()
    public static let ordered = PhotosPickerSelectionBehavior()
    public static let continuous = PhotosPickerSelectionBehavior()
    public static let continuousAndOrdered = PhotosPickerSelectionBehavior()
}

/// 写真選びの見せ方（本物は `PhotosPickerStyle` の型・iOS 17〜）
public struct PhotosPickerStyleShim {
    public static let presentation = PhotosPickerStyleShim()
    public static let inline = PhotosPickerStyleShim()
    public static let compact = PhotosPickerStyleShim()
}

/// 写真選びの設定（本物は PhotosUI の `PHPickerConfiguration`）。使うのは止める機能の組だけ
public struct PHPickerConfiguration {
    public struct Capabilities: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let search = Capabilities(rawValue: 1)
        public static let stagingArea = Capabilities(rawValue: 2)
        public static let collectionNavigation = Capabilities(rawValue: 4)
        public static let selectionActions = Capabilities(rawValue: 8)
        public static let sensitivityAnalysisIntervention = Capabilities(rawValue: 16)
    }
}

extension View {
    /// 埋め込みで出す（本物にもある・iOS 17〜）
    public func photosPickerStyle(_ style: PhotosPickerStyleShim) -> some View { self }
    /// 上下の飾り（ナビゲーションの帯・下の帯）を隠す（本物にもある・iOS 17〜）
    public func photosPickerAccessoryVisibility(_ visibility: VisibilityShim, edges: Edge.Set = .all) -> some View { self }
    /// 機能を止める（本物にもある・iOS 17〜）。「キャンセル」「追加」を止めると、選ぶたびに `selection` が変わる
    public func photosPickerDisabledCapabilities(_ capabilities: PHPickerConfiguration.Capabilities) -> some View { self }
}

extension View {
    /// 選ぶ画面を旗で開く（本物にもある）。メニューの中に `PhotosPicker` を置くと
    /// 開かないことがあるので、こちらを使う
    public func photosPicker(isPresented: Binding<Bool>,
                             selection: Binding<[PhotosPickerItem]>,
                             maxSelectionCount: Int? = nil,
                             matching filter: PHPickerFilter? = nil,
                             photoLibrary: PHPhotoLibraryShim) -> some View { self }
    /// 写真の場所（撮影地）を読まない版（本物にもある）
    public func photosPicker(isPresented: Binding<Bool>,
                             selection: Binding<[PhotosPickerItem]>,
                             maxSelectionCount: Int? = nil,
                             matching filter: PHPickerFilter? = nil) -> some View { self }
}
