import SwiftUI

/// 撮影地を候補から選ぶ。
///
/// **地名をタグに書かせない。** 実データではタグ4種が撮影地の語と同じで、
/// 撮影地欄へ移すと `/location/*` の集約ページが厚くなる（＝検索に出る面が
/// 増える）。打った文字から候補を出して、選ばせる方へ寄せる。
///
/// 候補には座標が付いてくる（サーバー側で約1kmに丸め済み）。地名を選ぶと
/// 座標も一緒に入るので、地図にも載る。
struct PlaceSearchField: View {

    @Binding var location: String
    @Binding var coords: Photo.Coords?

    @EnvironmentObject private var environment: AppEnvironment
    @State private var suggestions: [DiscoveryService.Place] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    /// **打っている人がいるときだけ候補を出す。**
    /// 撮影地は写真の座標から自動でも入る（`UploadViewModel.fillPlaceName`）。
    /// 入った瞬間に `.onChange` が走ると、頼んでいない検索が飛び、
    /// **勝手に候補が開く**（選んだ覚えのない地名が並ぶ）
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            TextField(L("撮影地（例: 高屋神社, 香川）", "Place (e.g. Takaya Shrine, Kagawa)"), text: $location)
                .focused($focused)
                .onChange(of: location) { _, value in schedule(value) }

            ForEach(suggestions) { place in
                Button {
                    location = place.label
                    coords = place.coords
                    suggestions = []
                } label: {
                    Label(place.label, systemImage: "mappin.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if isSearching {
                Text(L("探しています…", "Searching…")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// **打つたびに投げない。** 最後の打鍵から少し待つ（検索と同じ間合い）。
    private func schedule(_ value: String) {
        searchTask?.cancel()
        // 自分で入れた値（自動補完・候補の選択）では探しに行かない
        guard focused else {
            suggestions = []
            return
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            let found = (try? await environment.discovery.searchPlaces(trimmed)) ?? []
            guard !Task.isCancelled else { return }
            // 選んだ直後に自分の候補を出し直さない
            suggestions = found.filter { $0.label != location }
        }
    }
}
