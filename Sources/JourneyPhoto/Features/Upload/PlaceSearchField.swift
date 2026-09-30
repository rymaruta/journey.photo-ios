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
    /// 写真の位置（あれば）。**近くの撮影スポットを先に出すためだけ**に使い、送らない
    var near: Photo.Coords? = nil

    @EnvironmentObject private var environment: AppEnvironment
    @State private var suggestions: [DiscoveryService.Place] = []
    /// 撮影スポットの候補（`PlaceSpotSuggestions`）。**地名検索より先に**出す
    @State private var spotSuggestions: [OfficialSpot] = []
    /// 撮影スポットの索引。欄に入ったときに1回読む（控えがあれば通信しない）。取れなければ出さないだけ
    @State private var spotIndex: [OfficialSpot]?
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    /// **打っている人がいるときだけ候補を出す。**
    /// 撮影地は写真の座標から自動でも入る（`UploadViewModel.fillPlaceName`）。
    /// 入った瞬間に `.onChange` が走ると、頼んでいない検索が飛び、
    /// **勝手に候補が開く**（選んだ覚えのない地名が並ぶ）
    @FocusState private var focused: Bool
    /// 候補から選んだときの地名。**手で直されたら座標を捨てるため**に覚える。
    ///
    /// 覚えていないと、「パリ」を選んでから文字を「ロンドン」に直した回に
    /// **パリの座標がロンドンとして保存される**。しかもサーバーは
    /// 明示的な座標を「正確」と見て `geoApprox` を外すので
    /// （`photoUpdate.ts`）、間違った場所に確定で刺さる。
    @State private var pickedLabel: String?

    var body: some View {
        Group {
            TextField(L("撮影地（例: 高屋神社, 香川）", "Place (e.g. Takaya Shrine, Kagawa)"), text: $location)
                .focused($focused)
                .onChange(of: location) { _, value in schedule(value) }
                .onChange(of: focused) { _, isFocused in
                    guard isFocused else {
                        spotSuggestions = []
                        return
                    }
                    Task { await loadSpotsAndSuggest() }
                }

            // 撮影スポット（公開済み）の候補。**名前だけを入れる**（紐付けはしない）
            ForEach(spotSuggestions) { spot in
                Button {
                    pickedLabel = spot.name
                    // 🔴 **位置のある写真は、写真の座標のまま。** スポットの座標（約1kmに丸めた値・
                    // 3km 先のこともある）で撮った位置を置き換えて「正確」として送っていた。
                    // スポットの座標を使うのは位置の無い写真だけ（`UploadViewModel.append` と同じ決まり）
                    // 位置のある写真では**前に選んだ地名の座標も捨てる**（残すと名前はスポット、
                    // 座標は前の地名のまま「正確」として送られた）。nil＝写真の座標のまま
                    coords = PlaceSpotSuggestions.coordsAfterPicking(spot, photoHasPosition: near != nil)
                    location = spot.name
                    spotSuggestions = []
                    suggestions = []
                } label: {
                    Label(spot.regionLabel.map { "\(spot.name) · \($0)" } ?? spot.name,
                          systemImage: "mappin.and.ellipse")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("撮影スポット \(spot.name)\(spot.regionLabel.map { "、" + $0 } ?? "")",
                                      "Photo spot \(spot.name)\(spot.regionLabel.map { ", " + $0 } ?? "")"))
            }

            ForEach(suggestions) { place in
                Button {
                    // **`location` より先に覚える。** あとにすると
                    // `.onChange(of: location)` が「選んだ地名ではない」と
                    // 読んで、選んだそばから座標を捨てることがある
                    pickedLabel = place.label
                    coords = place.coords
                    location = place.label
                    suggestions = []
                    spotSuggestions = []
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
        // **選んだ地名から離れたら座標を捨てる。** 残すと、別の地名に
        // 前の座標が付いたまま保存される（しかも「正確」として扱われる）
        if !PlacePick.keepsCoords(typed: value, pickedLabel: pickedLabel) {
            pickedLabel = nil
            coords = nil
        }
        // 自分で入れた値（自動補完・候補の選択）では探しに行かない。
        // **選んだ直後も探さない**——選んだ名前で探し直して、候補がまた開いていた
        guard focused, value != pickedLabel else {
            suggestions = []
            spotSuggestions = []
            return
        }
        suggestSpots(for: value)
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

    /// 撮影スポットの候補を出し直す（索引が読めていれば。端末の中だけで引く）
    private func suggestSpots(for value: String) {
        guard let spotIndex else { return }
        spotSuggestions = PlaceSpotSuggestions.suggestions(query: value, near: near, index: spotIndex)
            .filter { $0.name != location }
    }

    private func loadSpotsAndSuggest() async {
        if spotIndex == nil {
            spotIndex = try? await environment.spots.fetchIndex()
        }
        guard focused else { return }
        suggestSpots(for: location)
    }
}
