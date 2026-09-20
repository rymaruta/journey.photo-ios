import SwiftUI

/// タグ・撮影地・カテゴリで絞った一覧。
///
/// Web 側の `/tag/*`・`/location/*`・`/category/*` にあたる。あちらは
/// 検索に載せるための静的ページだが、アプリでは絞り込みの結果として出す。
struct TagPhotosView: View {

    enum Kind {
        case tag(String)
        case location(String)
        case category(String)

        var title: String {
            switch self {
            case .tag(let value): return "#\(value)"
            case .location(let value): return value
            case .category(let value): return value
            }
        }
    }

    let kind: Kind

    @EnvironmentObject private var environment: AppEnvironment
    @State private var photos: [Photo] = []
    @State private var isLoading = true

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            if photos.isEmpty && !isLoading {
                ErrorBanner(message: "この条件の写真はまだありません")
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink { PhotoDetailView(photo: photo) } label: {
                            RemoteImage(url: photo.gridImageURL)
                                .aspectRatio(1, contentMode: .fill)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await environment.gallery.fetchPhotos()) ?? []
        photos = Self.filter(all, by: kind)
    }

    /// **撮影地はゆるく一致させる。** Web 側の `photosInCollection` が
    /// 「パリ」「パリ, フランス」「オペラ・ガルニエ（パリ）」を寄せているので、
    /// 完全一致で絞ると結果が食い違う。
    static func filter(_ photos: [Photo], by kind: Kind) -> [Photo] {
        switch kind {
        case .tag(let value):
            let needle = value.lowercased()
            return photos.filter { ($0.tags ?? []).contains { $0.lowercased() == needle } }
        case .category(let value):
            return photos.filter { $0.category == value }
        case .location(let value):
            let needle = value.lowercased()
            return photos.filter {
                guard let location = $0.location?.lowercased() else { return false }
                return location == needle || location.contains(needle) || needle.contains(location)
            }
        }
    }
}
