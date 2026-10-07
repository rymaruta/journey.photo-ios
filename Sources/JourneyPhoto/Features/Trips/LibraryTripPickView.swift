import SwiftUI

/// 旅の写真を日ごとに選ぶ。
///
/// 日ごとに真鍮の眉ラベル（「DAY 1 · 9.12 · 京都市」）と4列の格子。押すと選ぶ・外す。
/// **最初から日ごとにばらけるよう選んでおく**（`LibraryTrips.spreadPick`）——
/// 何百枚から10枚を自分で探すのがいちばん重い。
///
/// 下の主ボタンで選んだ写真の本体を読み、1枚ずつ整えて（`ImagePreparer`）投稿画面へ
/// （写真のある画面なので白）。**原本は持ち続けない**——読んだらすぐ縮めて、原本は捨てる
struct LibraryTripPickView: View {

    let trip: LibraryTrip
    /// 画面の題（旅の地名、無ければ期間）
    let title: String
    @ObservedObject var model: LibraryTripModel
    let onDone: ([ImagePreparer.Prepared]) -> Void

    /// 選んだ写真の id（選んだ順）。投稿画面へは旅の並びに直して渡す
    @State private var selected: [String]
    /// 上限を超えて選ぼうとした（下に一言出す。次に押したら消す）
    @State private var overLimit = false
    /// 本体を読んでいる最中（輪を出し、二度押しを止める）
    @State private var isLoading = false
    /// 読めなかった枚数（知らせを出す）と、読めたぶん
    @State private var failedCount = 0
    @State private var showFailed = false
    @State private var loadedPhotos: [ImagePreparer.Prepared] = []
    /// 読み込みの仕事。**画面を離れたら取り消す**——取り消さないと、閉じたあとに
    /// 読み終えた写真が呼び手へ届き、次の投稿に混ざっていた
    @State private var loadTask: Task<Void, Never>?

    private let limit = UploadViewModel.maxSelection

    init(trip: LibraryTrip, title: String, model: LibraryTripModel,
         onDone: @escaping ([ImagePreparer.Prepared]) -> Void) {
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
        // **戻る・閉じるは読み込み中も止めない**（iCloud からの読み込みには時間の上限が無い）。
        // 画面が消えたら読み込みを取り消す。閉じたあとに届いた写真は呼び手が捨てる
        // （`TripImportHandoff.received`）
        .onDisappear { stopLoading() }
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
            Text(L("読み込めなかった写真（iCloud から落とせなかったものなど）は外しました。通信できる場所でもう一度お試しください。",
                   "Photos that couldn't be loaded (such as ones that couldn't be downloaded from iCloud) were removed. Try again with a connection."))
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
            if isLoading {
                // 読み込み中は主ボタンの位置に「やめる」（輪と並べる）
                HStack(spacing: 12) {
                    ProgressView().tint(WebTheme.foreground)
                    Text(L("写真を読み込んでいます", "Loading photos"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { stopLoading() } label: {
                    Text(L("やめる", "Stop")).jpPillButton(.outline)
                }
                .buttonStyle(.plain)
            } else {
                // 旅の記録の一冊は2枚から（1枚では束にならず、非公開のままどこの棚にも出ない）
                let canAdd = LibraryTrips.canAddToTrips(count: selected.count)
                if !canAdd {
                    Text(L("2枚から旅の記録に入れられます", "Pick 2 or more photos to add to your trips"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                }
                Button { startLoading() } label: {
                    Text(L("\(selected.count)枚を旅の記録に入れる", "Add \(selected.count) to your trips"))
                        .jpPillButton(.primary)
                        .opacity(canAdd ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
        }
        .jpBottomBar()
    }

    /// 読み込みを始める。**印を立ててから仕事を作る**——ボタンの `.disabled` は次の描画まで
    /// 効かないので、素早い二度押しで仕事が2つできていた
    private func startLoading() {
        guard loadTask == nil, !isLoading, LibraryTrips.canAddToTrips(count: selected.count) else { return }
        isLoading = true
        loadTask = Task { await load() }
    }

    /// 読み込みをやめる（「やめる」・画面が消えた）。状態はここで戻す——取り消した仕事は
    /// 状態に触らない（次に始めた読み込みの「読み込み中」を消さない）
    private func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    /// 選んだ写真の本体を旅の並びで読み、**読んだそばから1枚ずつ整える**（縮小・EXIF と GPS を落とす・
    /// 撮影日と約1kmに丸めた座標は残す）。読めなかった・整えられなかった写真は外して知らせる。
    ///
    /// 🔴 **原本を溜めない。** 以前は原本（1枚 数MB〜数十MB の HEIC・JPEG）を10枚まとめて読み、
    /// 投稿画面へ渡して、画面を閉じるまで持ち続けていた。整えるのは画面の処理の外で
    private func load() async {
        let order = trip.shots.filter { selected.contains($0.id) }
        let zone = trip.timeZone
        var photos: [ImagePreparer.Prepared] = []
        var failed: [String] = []
        for shot in order {
            let id = shot.id
            if Task.isCancelled { return }
            guard let data = await PhotoLibrary.imageData(for: id) else {
                failed.append(id)
                continue
            }
            if Task.isCancelled { return }
            let prepared = try? await Task.detached(priority: .userInitiated) {
                // EXIF の撮影日時が無ければ写真ライブラリの撮った時刻で付ける（一冊から落ちない）
                ImagePreparer.fillingTakenDate(
                    try ImagePreparer.prepare(data: data, fileName: "photo", withThumbnail: true),
                    takenAt: shot.date, timeZone: zone)
            }.value
            if let prepared {
                photos.append(prepared)
            } else {
                failed.append(id)
            }
        }
        // 読んでいる間にやめた・画面を離れたなら、何も渡さない（状態は `stopLoading` が戻した）
        guard !Task.isCancelled else { return }
        loadTask = nil
        isLoading = false
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
