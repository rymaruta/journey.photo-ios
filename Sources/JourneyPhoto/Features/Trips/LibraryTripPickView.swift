import SwiftUI

/// 旅の写真を日ごとに選ぶ。
///
/// 日ごとに真鍮の眉ラベル（「DAY 1 · 9.12 · 京都市」）と4列の格子。押すと選ぶ・外す。
/// **最初から日ごとにばらけるよう選んでおく**（`LibraryTrips.spreadPick`）——
/// 何百枚から10枚を自分で探すのがいちばん重い。
///
/// 下の主ボタンで選んだ写真の本体を読み、投稿画面へ（写真のある画面なので白）
struct LibraryTripPickView: View {

    let trip: LibraryTrip
    /// 画面の題（旅の地名、無ければ期間）
    let title: String
    @ObservedObject var model: LibraryTripModel
    let onDone: ([Data]) -> Void

    /// 選んだ写真の id（選んだ順）。投稿画面へは旅の並びに直して渡す
    @State private var selected: [String]
    /// 上限を超えて選ぼうとした（下に一言出す。次に押したら消す）
    @State private var overLimit = false
    /// 本体を読んでいる最中（輪を出し、二度押しを止める）
    @State private var isLoading = false
    /// 読めなかった枚数（知らせを出す）と、読めたぶん
    @State private var failedCount = 0
    @State private var showFailed = false
    @State private var loadedPhotos: [Data] = []

    private let limit = UploadViewModel.maxSelection

    init(trip: LibraryTrip, title: String, model: LibraryTripModel, onDone: @escaping ([Data]) -> Void) {
        self.trip = trip
        self.title = title
        self.model = model
        self.onDone = onDone
        _selected = State(initialValue: LibraryTrips.spreadPick(trip, limit: UploadViewModel.maxSelection))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                ForEach(trip.days) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LibraryTrips.dayLabel(day, place: model.name(for: day.center)))
                            .jpEyebrow()
                            .foregroundStyle(WebTheme.accent)
                            .padding(.horizontal, 16)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(day.shots, id: \.id) { shot in cell(shot) }
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .webScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        // 日ごとの地名（引けなければ日付だけ）
        .task { await model.resolveNames(trip.days.map(\.center)) }
        .alert(L("\(failedCount)枚は読み込めませんでした", "\(failedCount) photo(s) couldn't be loaded"),
               isPresented: $showFailed) {
            if !loadedPhotos.isEmpty {
                Button(L("残りの\(loadedPhotos.count)枚で続ける", "Continue with \(loadedPhotos.count)")) {
                    onDone(loadedPhotos)
                }
            }
            Button(L("選び直す", "Pick again"), role: .cancel) { }
        } message: {
            Text(L("iCloud から落とせなかった写真は外しました。通信できる場所でもう一度お試しください。",
                   "Photos that couldn't be downloaded from iCloud were removed. Try again with a connection."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Text("\(LibraryTrips.periodText(trip)) · \(L("\(trip.shots.count)枚", "\(trip.shots.count) photos"))")
                .font(JPFont.mono(12))
                .foregroundStyle(WebTheme.muted2)
            Text(L("日ごとにばらけるよう選んであります。押すと選ぶ・外すが切り替わります",
                   "We picked a few from each day. Tap to add or remove."))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    private func cell(_ shot: LibraryShot) -> some View {
        let isOn = selected.contains(shot.id)
        return Button {
            let result = LibraryTrips.toggle(shot.id, in: selected, limit: limit)
            selected = result.selected
            overLimit = result.overLimit
        } label: {
            // 4列の格子なので一辺は 80pt 以上（押せる範囲 44pt を満たす）
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { LibraryThumbView(id: shot.id, side: 100) }
                .clipped()
                .overlay(alignment: .topTrailing) { mark(isOn).padding(6) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(L("写真", "Photo"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// 選んだ印（白い丸にチェック）。選んでいない写真は細い白い輪だけ
    @ViewBuilder
    private func mark(_ isOn: Bool) -> some View {
        if isOn {
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WebTheme.accentText)
                }
                .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1)
        } else {
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                .background(Color.black.opacity(0.25), in: Circle())
                .frame(width: 24, height: 24)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if overLimit {
                Text(L("一度に入れられるのは\(limit)枚までです", "You can add up to \(limit) photos at a time"))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.text)
            }
            Button {
                Task { await load() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(WebTheme.accentText)
                    } else {
                        Text(L("\(selected.count)枚を下書きに入れる", "Add \(selected.count) to a draft"))
                    }
                }
                .jpPillButton(.primary)
                .opacity(selected.isEmpty ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty || isLoading)
            .accessibilityLabel(isLoading ? L("写真を読み込んでいます", "Loading photos")
                                          : L("\(selected.count)枚を下書きに入れる", "Add \(selected.count) to a draft"))
        }
        .jpBottomBar()
    }

    /// 選んだ写真の本体を旅の並びで読む。読めなかった写真は外して知らせる
    private func load() async {
        // ボタンの `.disabled` は次の描画まで効かない——二度押しをここでも止める
        guard !isLoading, !selected.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let order = trip.shots.map(\.id).filter { selected.contains($0) }
        var photos: [Data] = []
        var failed: [String] = []
        for id in order {
            if let data = await PhotoLibrary.imageData(for: id) {
                photos.append(data)
            } else {
                failed.append(id)
            }
        }
        if failed.isEmpty {
            onDone(photos)
            return
        }
        selected.removeAll { failed.contains($0) }
        failedCount = failed.count
        loadedPhotos = photos
        showFailed = true
    }
}
