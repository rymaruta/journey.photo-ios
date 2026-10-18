import CoreLocation
import PhotosUI
import SwiftUI
import UIKit

/// 撮って加える（板 CampCapture・CampFlow: 撮る → 切り出す → 置く の 3 手順）。
///
/// - 1 撮る: 写真は画面いっぱい。三分割の細い線と、切り出せる物を囲む四隅の枠。下の黒い帯に「写真／切り絵」と白いシャッター、
///   左に写真から選ぶ・右にカメラの前後。写真の上なので白だけ（真鍮は使わない）
/// - 2 切り出す: 後ろの写真を 62% 暗くし、切った 3 枚を少しずつ持ち上げて重なりを見せる（0.6 秒・紙の白いフチと影）。
///   「島に立てる」（白）と「切り抜きを直す」
/// - 3 置く: 島の上に箱庭を仮に立て（点線の輪と影）、置く場所を 3 つから選ぶ。島は指で回せる。主ボタンは真鍮に墨
/// - **人が写った写真は切り絵にしない**（数えない）。「写真」で撮った 1 枚は空の色にだけ使う
struct CampCaptureView: View {
    var ownerName: String?
    /// 閉じた（立てた切り絵の id。立てずに閉じたら nil）
    let onFinish: (String?) -> Void

    enum Mode { case photo, cutout }

    @StateObject private var camera = CampCamera()
    @StateObject private var locator = CurrentLocation()
    @ObservedObject private var store = CampStore.shared
    @EnvironmentObject private var toasts: ToastCenter
    @State private var step = 1
    @State private var mode: Mode = .cutout
    @State private var result: CampCutResult?
    @State private var meta = CampShotMeta()
    @State private var working = false
    @State private var lifted = false
    @State private var spot = 0
    @State private var savedId: String?
    @State private var angle = CampAngle.resting
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmClose = false
    /// 画面の大きさ（撮る枠の写真の範囲を決める）
    @State private var screen = CGSize(width: 390, height: 844)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .top) {
                Color.black
                if step == 1 {
                    shootLayer(size)
                } else if step == 2, let result {
                    CampCutStage(result: result, size: size, lifted: lifted)
                } else if step == 3 {
                    placeIsland(size)
                }
                header
                if step == 1 { shootControls(size) }
                if step == 2 { cutSheet }
                if step == 3 { placeSheet(size) }
                if working { workingVeil }
            }
            .frame(width: size.width, height: size.height)
            .onAppear { screen = size }
            .onChange(of: size) { _, newSize in screen = newSize }
        }
        .ignoresSafeArea()
        .statusBarHidden(step != 3)
        .task {
            await camera.start()
            if CLLocationManager().authorizationStatus == .authorizedWhenInUse
                || CLLocationManager().authorizationStatus == .authorizedAlways {
                locator.locate(requestedByUser: false)
            }
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await pick(item) }
        }
        .confirmationDialog(L("切り抜いた 3 枚を保存していません", "The three cut layers aren\u{2019}t saved"),
                            isPresented: $confirmClose, titleVisibility: .visible) {
            Button(L("保存せずに閉じる", "Close without saving"), role: .destructive) { onFinish(nil) }
            Button(Labels.Common.cancel, role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camp.capture")
    }

    // MARK: - 見出し（閉じる・手順）

    private var onPhoto: Bool { step != 3 }

    private var header: some View {
        HStack(spacing: 4) {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            }
            .accessibilityLabel(Labels.Common.close)
            .accessibilityIdentifier("camp.capture.close")
            HStack(spacing: 2) {
                ForEach(Array(CampCaptureText.steps.enumerated()), id: \.offset) { i, label in
                    stepButton(i + 1, label)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 48)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("手順", "Steps"))
        }
        .padding(.top, 50)
        .padding(.horizontal, 8)
        .background {
            if step == 3 {
                LinearGradient(colors: [Color.black.opacity(0.67), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
    }

    private func stepButton(_ n: Int, _ label: String) -> some View {
        let current = n == step, done = n < step
        let accent = onPhoto ? Color.white : WebTheme.accent
        let reachable = n < step || (n == 2 && result != nil) || (n == 3 && savedId != nil)
        return Button {
            guard reachable, n != step else { return }
            go(to: n)
        } label: {
            HStack(spacing: 6) {
                Text("\(n)")
                    .font(JPFont.number(11, weight: .semibold))
                    .foregroundStyle(current || done ? Color.black : Color.white.opacity(0.62))
                    .frame(width: 20, height: 20)
                    .background { Circle().fill(current ? accent : (done ? Color.white.opacity(0.62) : Color.clear)) }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(current ? Color.white : Color.white.opacity(0.62))
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("camp.capture.step\(n)")
    }

    // MARK: - 1 撮る

    private func shootLayer(_ size: CGSize) -> some View {
        let viewH = size.height - 120
        let frame = CampCrop.frame(width: Double(size.width), height: Double(size.height))
        return ZStack(alignment: .topLeading) {
            Group {
                if camera.state == .ready {
                    CampCameraPreview(session: camera.session)
                } else if let sample = CampSample.photo {
                    Image(uiImage: sample).resizable().scaledToFill()
                } else {
                    VStack(spacing: 12) {
                        Text(CampCaptureText.noCamera)
                            .font(JPFont.body)
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: size.width, height: viewH)
            .clipped()
            .accessibilityLabel(L("カメラ: 切り出せる物を四隅の枠で囲む", "Camera: frame what you want to cut out"))
            // 三分割の細い線（白 18%）
            Path { p in
                for k in [1.0, 2.0] {
                    p.move(to: CGPoint(x: size.width * k / 3, y: 0))
                    p.addLine(to: CGPoint(x: size.width * k / 3, y: viewH))
                    p.move(to: CGPoint(x: 0, y: viewH * k / 3))
                    p.addLine(to: CGPoint(x: size.width, y: viewH * k / 3))
                }
            }
            .stroke(Color.white.opacity(0.18), lineWidth: 1)
            .allowsHitTesting(false)
            // 四隅の枠（白 2・長さ 18）
            CampCornerFrame(x: frame.x, y: frame.y, w: frame.w, h: frame.h)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .allowsHitTesting(false)
            LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func shootControls(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text(mode == .cutout ? CampCaptureText.hint : CampCaptureText.skyHint)
                .font(.system(size: 13))
                .foregroundStyle(Color.white)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background { Capsule().fill(Color.black.opacity(0.55)) }
                .padding(.bottom, 44 - 18)
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    modeButton(.photo, L("写真", "Photo"))
                    modeButton(.cutout, L("切り絵", "Cutout"))
                }
                .frame(height: 30)
                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        libraryThumb
                    }
                    .accessibilityLabel(L("写真から選ぶ", "Choose from photos"))
                    .accessibilityIdentifier("camp.capture.library")
                    Spacer()
                    Button { Task { await shoot() } } label: {
                        Circle()
                            .fill(Color.white)
                            .padding(8)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(working || camera.isCapturing)
                    .accessibilityLabel(L("撮る", "Shoot"))
                    .accessibilityIdentifier("camp.capture.shutter")
                    Spacer()
                    Button { Task { await camera.toggle() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 19))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .background { Circle().fill(Color.white.opacity(0.14)) }
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.state != .ready)
                    .accessibilityLabel(L("カメラを切り替える", "Switch camera"))
                    .accessibilityIdentifier("camp.capture.flip")
                }
                .padding(.horizontal, 28)
                Spacer(minLength: 0)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(Color.black)
        }
    }

    private func modeButton(_ m: Mode, _ label: String) -> some View {
        Button { mode = m } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.96)
                .foregroundStyle(mode == m ? Color.white : CampPalette.color(0x8A8A8A))
                .frame(minWidth: 44, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
        .accessibilityIdentifier(m == .cutout ? "camp.capture.mode.cutout" : "camp.capture.mode.photo")
    }

    /// 写真から選ぶ（いちばん新しい切り絵の写真の切り抜き。無ければ印）
    private var libraryThumb: some View {
        Group {
            if let id = store.cutouts.last?.id, let data = try? Data(contentsOf: store.photoURL(cutout: id)),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
    }

    // MARK: - 2 切り出す

    private var cutSheet: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let result, result.hasPeople {
                Text(L("人が写っています", "There are people in this photo"))
                    .font(JPFont.display(24, relativeTo: .title2))
                    .foregroundStyle(Color.white)
                Text(L("人の写った写真は、切り絵にしません。木の並び・岩・道具を撮ってください。",
                       "We don\u{2019}t make cutouts from photos of people. Try a row of trees, rocks or gear."))
                    .font(.system(size: 14))
                    .foregroundStyle(CampPalette.color(0xDCDCDC))
                    .lineSpacing(5)
                Button { go(to: 1) } label: { primaryWhite(L("撮り直す", "Shoot again")) }
                    .padding(.top, 12)
                    .accessibilityIdentifier("camp.capture.retake")
            } else if let result {
                Text(L("切り抜けました・3 枚", "Cut into 3 layers"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Text(result.title)
                    .font(JPFont.display(24, relativeTo: .title2))
                    .foregroundStyle(Color.white)
                    .lineSpacing(4)
                Text(CampCaptureText.meta(place: meta.locality, date: meta.date))
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(CampPalette.color(0xA3A3A3))
                Text(L("木の並びに沿って奥・中・手前の 3 枚に切り分けました。島に立てると、重ねた紙の箱庭になります。",
                       "Cut along the tree lines into back, middle and front layers. On the island they stand as a paper diorama."))
                    .font(.system(size: 14))
                    .foregroundStyle(CampPalette.color(0xDCDCDC))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Button { Task { await saveAndPlace() } } label: { primaryWhite(L("島に立てる", "Stand it on the island")) }
                    .padding(.top, 12)
                    .accessibilityIdentifier("camp.capture.toPlace")
                Button { go(to: 1) } label: {
                    Text(L("切り抜きを直す", "Redo the cut"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camp.capture.retake")
            }
        }
        .padding(.top, 20).padding(.leading, 20).padding(.bottom, 34).padding(.trailing, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).fill(Color.black) }
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 24) }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func primaryWhite(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background { RoundedRectangle(cornerRadius: 14).fill(Color.white) }
            .contentShape(Rectangle())
    }

    // MARK: - 3 置く

    private func placeIsland(_ size: CGSize) -> some View {
        let islandH = min(500, size.height - 344)
        return CampIslandView(options: placeOptions, angle: angle, cornerRadius: 0,
                              images: CampStoreImages.loader(store), onAngle: { angle = $0 })
            .frame(width: size.width, height: islandH)
            .accessibilityIdentifier("camp.capture.island")
    }

    private var placeOptions: CampSceneOptions {
        let placed = store.placed.compactMap { c in c.spot.map { CampPlacedCutout(id: c.id, layers: c.layers, spot: $0) } }
        let stage = CampStage.stage(cutouts: max(1, store.placedCount + 1))
        let placing = savedId.flatMap { id in result.map { CampPlacedCutout(id: id, layers: $0.layers, spot: spot) } }
        return CampSceneOptions(stage: stage, season: CampClock.season(of: Date()), time: CampTime(slot: CampClock.slot(of: Date())),
                                cutouts: placed, placing: placing)
    }

    private func placeSheet(_ size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("置く場所", "Where to stand it"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(L("\(result?.title ?? "")を、どこに立てますか", "Where should \(result?.title ?? "it") stand?"))
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(Color.white)
                .lineLimit(2)
            CampSpotPicker(spot: $spot)
                .padding(.top, 8)
            Text(L("指で島を回すと、裏から見た紙の白も確かめられます", "Turn the island to see the white paper from behind"))
                .font(.system(size: 13))
                .foregroundStyle(CampPalette.color(0xA3A3A3))
            Spacer(minLength: 8)
            Button { place() } label: {
                Text(L("ここに立てる", "Stand it here"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background { RoundedRectangle(cornerRadius: 14).fill(WebTheme.accent) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camp.capture.place")
            Button { go(to: 2) } label: {
                Text(L("切り抜きに戻る", "Back to the cut"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CampPalette.color(0xE5E5E5))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camp.capture.back")
        }
        .padding(.top, 20).padding(.leading, 20).padding(.bottom, 34).padding(.trailing, 20)
        .frame(width: size.width, height: max(320, size.height - min(500, size.height - 344)), alignment: .topLeading)
        .background(Color.black)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var workingVeil: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                ProgressView().tint(Color.white)
                Text(L("切り出しています", "Cutting out"))
                    .font(JPFont.footnote)
                    .foregroundStyle(Color.white)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 動き

    private func go(to n: Int) {
        if n == 1 {
            if let id = savedId { store.remove(cutout: id) }
            savedId = nil
            result = nil
            lifted = false
        }
        withAnimation(.easeInOut(duration: 0.25)) { step = n }
        if n == 2 {
            lifted = false
            withAnimation(.easeOut(duration: 0.6)) { lifted = true }
        }
    }

    private func close() {
        if step == 2, savedId == nil, let result, !result.hasPeople {
            confirmClose = true
            return
        }
        if step == 3, savedId != nil {
            toasts.show(L("切り絵は、あとで島に立てられます", "You can stand the cutout on the island later"), kind: .info)
        }
        onFinish(nil)
    }

    /// シャッター（カメラが無ければ見本の写真）
    private func shoot() async {
        var image: UIImage?
        if camera.state == .ready, let shot = await camera.capture() {
            image = UIImage(data: shot.data)
        } else {
            image = CampSample.photo
        }
        guard let image else { return }
        var m = CampShotMeta()
        m.date = Date()
        if case let .located(lat, lon) = locator.state {
            m.latitude = lat
            m.longitude = lon
        }
        await process(image, meta: m)
    }

    private func pick(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let exif = CampCutter.metadata(data)
        var m = CampShotMeta()
        m.date = exif.date ?? Date()
        m.latitude = exif.latitude
        m.longitude = exif.longitude
        m.altitude = exif.altitude
        await process(image, meta: m)
    }

    private func process(_ image: UIImage, meta base: CampShotMeta) async {
        working = true
        defer { working = false }
        let size = screen
        let frame = CampCrop.frame(width: Double(size.width), height: Double(size.height))
        let cut = await CampCutter.cut(image, frame: CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h),
                                       viewSize: CGSize(width: size.width, height: size.height - 120))
        var m = base
        await m.geocode()
        meta = m
        if mode == .photo {
            // 空の色だけに使う（切り絵にしない・集める数には入れる）
            store.add(shot: m.shot(subjects: cut.subjects, people: cut.hasPeople, cutout: false), cutout: nil, layerImages: [],
                      photo: nil, sky: cut.hasPeople ? nil : cut.sky.map { CampSkySample(colors: $0, takenAt: m.date ?? Date()) })
            toasts.show(cut.hasPeople ? L("人の写った写真は使いません", "Photos of people aren\u{2019}t used")
                                      : L("この時刻の空の色にしました", "The sky now takes this photo\u{2019}s color"))
            onFinish(nil)
            return
        }
        result = cut
        go(to: 2)
    }

    /// 2 → 3（切り絵を入れ物に置く。まだ立てない）
    private func saveAndPlace() async {
        guard let result else { return }
        if savedId == nil {
            let id = UUID().uuidString
            let shot = meta.shot(subjects: result.subjects, people: false, cutout: true)
            let record = CampCutoutRecord(id: id, shotId: shot.id, layers: result.layers, spot: nil, title: result.title,
                                          place: meta.locality, takenAt: meta.date ?? Date(), createdAt: Date())
            store.add(shot: shot, cutout: record, layerImages: result.cards.compactMap(CampCutter.png),
                      photo: CampCutter.cropJPEG(result),
                      sky: result.sky.map { CampSkySample(colors: $0, takenAt: meta.date ?? Date()) })
            savedId = id
        }
        go(to: 3)
    }

    private func place() {
        guard let id = savedId else { return }
        store.place(id, spot: spot)
        onFinish(id)
    }
}

/// 置く場所の 3 つ（板 CampCapture の 3 置く: 手前の芝・小道のそば・テントの横）
struct CampSpotPicker: View {
    @Binding var spot: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                let on = i == spot
                Button { spot = i } label: {
                    Text(CampCaptureText.spots[i])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? WebTheme.accent : CampPalette.color(0xE5E5E5))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? WebTheme.accent : Color.white.opacity(0.22),
                                                                                 lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("camp.capture.spot\(i)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("置く場所", "Where to stand it"))
    }
}

/// 撮った 1 枚の撮影情報（撮った日時・位置・地名）
struct CampShotMeta {
    var date: Date?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var prefecture: String?
    var locality: String?

    /// 地名を引く（iOS の地名変換・3 秒まで）
    mutating func geocode() async {
        guard let lat = latitude, let lon = longitude else { return }
        let names: (String?, String?)? = await AsyncTimeout.firstWithin(seconds: 3) {
            guard let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first
            else { return nil }
            return (mark.administrativeArea, mark.locality)
        }
        prefecture = names?.0
        locality = names?.1
    }

    /// 記録（位置は 0.01° に丸めて端末の中だけに置く）
    func shot(subjects: [CampSubject], people: Bool, cutout: Bool) -> CampShot {
        func round(_ v: Double?) -> Double? { v.map { ($0 * 100).rounded() / 100 } }
        return CampShot(id: UUID().uuidString, takenAt: date ?? Date(), latitude: round(latitude), longitude: round(longitude),
                        altitude: altitude, prefecture: prefecture, locality: locality, subjects: subjects, hasPeople: people,
                        cutout: cutout)
    }
}

/// 見本の写真（シミュレータ・画面写真の試験。実機でカメラがあるときは使わない）
enum CampSample {
    @MainActor static var photo: UIImage? = {
        #if targetEnvironment(simulator)
        return CampCutter.samplePhoto()
        #else
        return CampPreview.usesSample ? CampCutter.samplePhoto() : nil
        #endif
    }()
}

enum CampCaptureText {
    static var steps: [String] { [L("撮る", "Shoot"), L("切り出す", "Cut out"), L("置く", "Place")] }
    static var spots: [String] { [L("手前の芝", "Front lawn"), L("小道のそば", "By the path"), L("テントの横", "Beside the tent")] }
    static var hint: String { L("木の並び・岩・道具を撮ると、切り絵になります", "Shoot a row of trees, rocks or gear to make a cutout") }
    static var skyHint: String { L("空を撮ると、その時刻の島の空になります", "Shoot the sky to color the island\u{2019}s sky at this hour") }
    static var noCamera: String {
        L("カメラを使えません。左下から写真を選べます", "The camera isn\u{2019}t available. Choose a photo at the bottom left")
    }

    /// 「[撮った場所] · [撮った日] · 朝」
    static func meta(place: String?, date: Date?) -> String {
        let d = date ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: L("ja_JP", "en_US"))
        f.dateFormat = L("yyyy.M.d", "MMM d, yyyy")
        let time = CampTime(slot: CampClock.slot(of: d)).name
        return [place, f.string(from: d), time].compactMap { $0 }.joined(separator: " · ")
    }
}

/// 撮る画面の四隅の枠（長さ 18）
struct CampCornerFrame: Shape {
    let x: Double, y: Double, w: Double, h: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = 18.0
        let corners: [(Double, Double, Double, Double)] = [(x, y, 1, 1), (x + w, y, -1, 1), (x, y + h, 1, -1), (x + w, y + h, -1, -1)]
        for (cx, cy, sx, sy) in corners {
            p.move(to: CGPoint(x: cx, y: cy + sy * l))
            p.addLine(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx + sx * l, y: cy))
        }
        return p
    }
}
