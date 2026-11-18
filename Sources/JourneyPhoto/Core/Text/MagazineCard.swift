import Foundation

/// 共有の絵「雑誌」（2026-11-18 owner 採用・模型は Artifact「共有の絵の新しい形」の「雑誌の表紙（新しい型）」8版）。
///
/// 今の「表紙」（`Style.cover`・下を黒へ溶かす形）は残し、別の型として足す（owner「今の表紙消したくない」）。
/// - 字は4つだけ: 上の帯（「JOURNEY PHOTO」と細い線と「Vol. N」）、題（明朝）、撮影地と日付の1行、撮影の値の1行
///   （写真の外に置けるときだけ）。副題・座標・2列は出さない（2026-11-18 owner「文字多すぎて、写真が見えない」）
/// - **写真は切らない。** 全面に敷くのは切れる量が 8% 以下のときだけ（題は上か下の静かな端、字の形に沿った薄い影だけ・
///   面を暗くしない）。それ以外は写真を切らずに置き、余白はその写真をぼかして埋め、字はすべて余白に置く（写真の上に字を載せない）
/// - 字の明暗の比は 4.5:1 以上（見出しは 7:1・`ShareCardAuditTests` の決まり）。届くまで字の形の影を重ねる
///
/// ストーリー（`TravelStory.Kind.magazine`・1080×1920）と投稿（`SignatureShareCardRenderer.Style.magazine`・4:5・1:1・9:16）の両方で使う。
/// 寸法・置き方・字の中身はここに1か所（Linux の `swift test` で見張る）。描くのは `MagazineCardRenderer`（UIKit）。
/// 仕様メモ（1080 幅の画素）は scratchpad の `share-new/magazine-spec.md`（模型との違いの判断も書いた）
enum MagazineCard {

    // MARK: - 寸法（1080 幅の画素）

    static let width: CGFloat = 1080
    /// 左右の余白と字の幅
    static let margin: CGFloat = 72
    static let contentWidth: CGFloat = 936
    static var right: CGFloat { margin + contentWidth }
    /// 全面に敷いてよい、切れる量の上限（8%）
    static let fullBleedMaxCrop: CGFloat = 0.08

    /// 上の帯。上端（`Frame.textTop`）からの位置
    enum Band {
        /// 番号（明朝 700 60px・白）。**2026-11-18 判断:** 模型は番号の上端が帯の字より 16 上（zT − 16）。
        /// 投稿の上端 72 − 16 = 56 は安全域（短い辺の 6% = 64.8）の外になるので、番号の上端を zT にそろえ、ほかを 16 下げた
        static let numberY: CGFloat = 0
        static let numberSize: CGFloat = 60
        /// 「JOURNEY PHOTO」（SF 500 33px・字間 0.42em）
        static let eyebrowY: CGFloat = 16
        static let eyebrowSize: CGFloat = 33
        static let eyebrowKern: CGFloat = 0.42
        static let eyebrow = "JOURNEY PHOTO"
        /// 「Vol.」（SF italic 400 33px・白 90%）。番号の左 14
        static let volY: CGFloat = 25
        static let volSize: CGFloat = 33
        static let volGap: CGFloat = 14
        static let vol = "Vol."
        /// 細い線（幅 150・高さ 2・白 75%）。帯の字の右 28。Vol. には 28 より近づけない
        static let ruleY: CGFloat = 33
        static let ruleWidth: CGFloat = 150
        static let ruleHeight: CGFloat = 2
        static let ruleGap: CGFloat = 28
        /// 線を出す最小の幅（これより短くなるなら線を出さない）
        static let ruleMinimumWidth: CGFloat = 40
        /// 帯の字の下端（上端から）
        static var eyebrowBottom: CGFloat { eyebrowY + eyebrowSize }
    }

    /// 題（明朝 700・字間 0.06em・行の高さ 1.25）
    enum Title {
        static let fullSize: CGFloat = 84
        static let storySize: CGFloat = 88
        static let postSize: CGFloat = 76
        static let minimumSize: CGFloat = 60
        static let kern: CGFloat = 0.06
        static let lineHeight: CGFloat = 1.25
        /// 2 行まで（模型に無い・長い題が入るように・2026-11-18 判断）
        static let maximumLines = 2
        /// 帯の字の下から題までの間（全面・余白の形）
        static let gapFull: CGFloat = 48
        static let gapMargin: CGFloat = 44
    }

    /// 撮影地と日付の1行（撮影地 SF 600 36px、30 空けて日付 SF 300 36px）
    enum Sub {
        static let gap: CGFloat = 16
        static let size: CGFloat = 36
        static let minimumSize: CGFloat = 33
        static let dateGap: CGFloat = 30
        static let lineHeight: CGFloat = 1.15
        static var height: CGFloat { size * lineHeight }
    }

    /// 撮影の値の1行（33px・カメラ 500、値 400・間 30）
    enum Exif {
        static let size: CGFloat = 33
        static let gap: CGFloat = 30
        static var height: CGFloat { size * 1.15 }
        /// 写真の下に置くときの写真との間
        static let below: CGFloat = 40
        /// 写真の上（撮影地の行の下）に置くときの、撮影地の行との間と、写真との間
        static let above: CGFloat = 14
        static let abovePhoto: CGFloat = 44
    }

    /// 撮影地の行（か題）と写真の間
    static let photoGap: CGFloat = 44
    /// 幅いっぱいに広げてよい差（幅が 97% を超えるなら、端の細い余白を出さず幅いっぱいに）
    static let snapWidthFraction: CGFloat = 0.97

    /// 字の白の濃さ。**不透明の灰で描く**（点検 `ShareCardAuditTests` が字の色をそのまま明暗の比に使う。
    /// 模型の白 90%・85%・80%・75% を、黒に近い地の上の見え方で灰にした）
    enum Ink {
        static let text: Double = 1
        static let vol: Double = 230.0 / 255
        static let date: Double = 217.0 / 255
        static let exif: Double = 204.0 / 255
        static let rule: Double = 0.75
    }

    /// 余白の地（ぼかした写真）。覆う大きさの 1.15 倍、黒 32% を重ねて写真と分ける
    enum Backdrop {
        static let overscan: CGFloat = 1.15
        static let dim: Double = 0.32
        /// 縮める幅の段（18 → 72 幅に縮めて広げる・模型の `softCopy`）
        static let steps: [CGFloat] = [18, 72]
    }

    // MARK: - 字の影（面を暗くしない）

    /// 影の決まり。字の形を少し太らせた（字の大きさの 10%）薄い影（黒 45%）を、明暗の比が届くまで重ねる。
    /// **2026-11-18 判断:** 模型は 8 回・ぼかし 0.26 → 3 回めから 0.14 だったが、真っ白な写真の上の見出し（7:1）に届かなかった
    /// ときの逃げとして、6 回めから 0.07 に寄せ、上限を 12 回にした（暗い地では1回も置かない）
    enum Shadow {
        static let alpha: Double = 0.45
        static let spread: CGFloat = 0.10
        static let maximumPasses = 12
        static let minimumBlur: CGFloat = 6

        static func blur(size: CGFloat, pass: Int) -> CGFloat {
            let factor: CGFloat = pass < 2 ? 0.26 : (pass < 5 ? 0.14 : 0.07)
            return max(minimumBlur, size * factor)
        }
    }

    /// 見出しとみなす字の大きさ（点検 `ShareCardAuditTests.headlineFontSize` と同じ 48）
    static let headlineSize: CGFloat = 48

    /// 届かせる明暗の比。見出し（題と Vol. の番号）は 7:1、ほかは 4.5:1
    static func targetContrast(fontSize: CGFloat) -> Double {
        fontSize >= headlineSize ? 7 : ShareCardSafeArea.minimumTextContrast
    }

    /// 灰（0〜1）の字と、相対輝度 `background` の地の明暗の比
    static func contrast(ink: Double, background: Double) -> Double {
        let v = ink * 255
        return ShareCardSafeArea.contrast(ShareCardSafeArea.luminance(red: v, green: v, blue: v), background)
    }

    // MARK: - 絵の枠

    /// 絵の高さと、字を置いてよい上下の線と、写真の下端の上限
    struct Frame: Equatable {
        let height: CGFloat
        /// 字の上端（ストーリーは 352、投稿は 72）
        let textTop: CGFloat
        /// 字の下端（ストーリーは 1528、投稿は下から 72）
        let textBottom: CGFloat
        /// 写真の下端の上限（ストーリーは下 10% の返信欄に写真も置かない）
        let photoFloor: CGFloat
        let isStory: Bool

        /// ストーリー（1080×1920）。**2026-11-18 判断:** 模型の上端は 277。9:16 は投稿でも選べ、フィードで真ん中を 4:5 に切られる
        /// （`ShareCardSafeArea.rect` の上 349.8）。帯の字が切られないよう、ストーリーも同じ 352 にそろえた（画面ごとに割らない）
        static let story = Frame(height: 1920, textTop: 352, textBottom: 1528, photoFloor: 1728, isStory: true)

        static func post(_ ratio: SignatureShareCardRenderer.Ratio) -> Frame {
            if ratio == .story { return story }
            let height = (MagazineCard.width / CGFloat(ratio.rawValue)).rounded()
            return Frame(height: height, textTop: MagazineCard.margin, textBottom: height - MagazineCard.margin,
                         photoFloor: height, isStory: false)
        }

        /// 絵の幅 ÷ 高さ
        var aspect: CGFloat { MagazineCard.width / height }
    }

    /// 写真（幅 ÷ 高さ = `aspect`）を枠いっぱいに覆ったときに切れる量（0〜1）
    static func crop(aspect: CGFloat, in frame: Frame) -> CGFloat {
        let a = sanitized(aspect), f = frame.aspect
        return 1 - min(a / f, f / a)
    }

    /// 全面に敷くか（切れる量が 8% 以下）
    static func isFullBleed(aspect: CGFloat, in frame: Frame) -> Bool {
        crop(aspect: aspect, in: frame) <= fullBleedMaxCrop + 0.0001
    }

    /// 題のはじめの大きさ（全面 84、余白に置く形はストーリー 88・投稿 76）
    static func titleSize(full: Bool, frame: Frame) -> CGFloat {
        full ? Title.fullSize : (frame.isStory ? Title.storySize : Title.postSize)
    }

    private static func sanitized(_ aspect: CGFloat) -> CGFloat {
        aspect.isFinite && aspect > 0 ? aspect : 1
    }

    // MARK: - 置き方

    /// 題の置き場（全面に敷くときだけ）
    enum Edge: String, Equatable { case top, bottom }

    /// 題と撮影地の行の大きさ（描く側が字を測って決める）
    struct Head: Equatable {
        /// 題の大きさと行の数（題が無ければ 0 行）
        var titleSize: CGFloat
        var titleLines: Int
        /// 撮影地と日付の行があるか
        var hasSub: Bool

        /// 題の上端から、撮影地の行の下端（無ければ題の下端）までの高さ
        var height: CGFloat { subTop + (hasSub ? Sub.height : 0) }
        /// 題の上端から撮影地の行の上端まで
        var subTop: CGFloat {
            titleLines > 0 ? CGFloat(titleLines) * titleSize * Title.lineHeight + Sub.gap : 0
        }
    }

    /// 写真の枠と字の位置
    struct Layout: Equatable {
        let photo: CGRect
        let full: Bool
        /// 全面のときの題の置き場（余白の形では nil）
        let edge: Edge?
        /// 帯の上端
        let bandTop: CGFloat
        /// 題の上端
        let titleTop: CGFloat
        /// 撮影地の行の上端
        let subTop: CGFloat
        /// 撮影の値の行の上端（全面のときは nil・出さない）
        let exifTop: CGFloat?
        /// 切れた量（全面のときだけ 0 より大きい）
        let crop: CGFloat
    }

    /// 写真の置き方と字の位置（模型の `layout` を写した）。
    /// - 全面（切れる量 8% 以下）: 写真で覆う。題は上の端（帯の字の下 48）か下の端（撮影地の行の下端 = 字の下端）。撮影の値は出さない
    /// - それ以外: 写真を切らずに置く。上に帯・題・撮影地、写真、下に撮影の値。入らなければ撮影の値を写真の上に上げ、
    ///   それでも入らない高さは写真を縮める（切らない）
    /// - `hasExif`: 撮影の値の行があるか。無ければ写真の上に値の行の場所を取らない（真ん中の決まりは同じ）
    static func layout(aspect: CGFloat, in frame: Frame, head: Head, hasExif: Bool = true, edge: Edge = .top) -> Layout {
        let a = sanitized(aspect)
        let zT = frame.textTop, zB = frame.textBottom
        if isFullBleed(aspect: a, in: frame) {
            var w = width, h = width / a
            if h < frame.height { h = frame.height; w = h * a }
            let photo = CGRect(x: (width - w) / 2, y: (frame.height - h) / 2, width: w, height: h)
            let titleTop = edge == .bottom ? zB - head.height : zT + Band.eyebrowBottom + Title.gapFull
            return Layout(photo: photo, full: true, edge: edge, bandTop: zT, titleTop: titleTop,
                          subTop: titleTop + head.subTop, exifTop: nil, crop: crop(aspect: a, in: frame))
        }
        let titleTop = zT + Band.eyebrowBottom + Title.gapMargin
        let headBottom = titleTop + head.height
        let top = headBottom + photoGap
        let floor = frame.photoFloor
        var h = width / a, w = width
        // 撮影の値を写真の下に置けるか（写真の下 40 + 値の行が字の下端に入り、写真が床を越えない）
        // **2026-11-18 判断:** 模型は値の行の高さを 33 で見ていたが、行の枠（33 × 1.15）が字の下端を 5px 越えるので枠で見る
        let split = (!hasExif || top + h + Exif.below + Exif.height <= zB + 0.5) && top + h <= floor
        var exifTop: CGFloat
        var photoTop = top
        if split || !hasExif {
            exifTop = 0
        } else {
            exifTop = headBottom + Exif.above
            photoTop = exifTop + Exif.height + Exif.abovePhoto
        }
        let available = floor - photoTop
        if h > available { h = available; w = h * a }
        // 端に細い余白が出るほどの差なら幅いっぱいに（床を越えない・切らない）
        if w < width, w > width * snapWidthFraction, photoTop + width / a <= floor { w = width; h = width / a }
        var y = photoTop
        if split {
            let room = min(floor, zB - Exif.below - Exif.height) - photoTop - h
            y = photoTop + max(0, room / 2)
            exifTop = y + h + Exif.below
        }
        let photo = CGRect(x: (width - w) / 2, y: y, width: w, height: h)
        return Layout(photo: photo, full: false, edge: nil, bandTop: zT, titleTop: titleTop,
                      subTop: titleTop + head.subTop, exifTop: hasExif ? exifTop : nil, crop: 0)
    }

    // MARK: - 題の置き場（全面のときだけ）

    /// 静かさ（小さいほど静か）。明るさのばらつき × 2 ＋ 明るさ × 0.6（模型の `quiet`）。相対輝度の並びから
    static func noise(_ luminances: [Double]) -> Double {
        guard !luminances.isEmpty else { return 0 }
        let mean = luminances.reduce(0, +) / Double(luminances.count)
        let variance = luminances.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(luminances.count)
        return variance.squareRoot() * 2 + mean * 0.6
    }

    /// 上と下の端の、静かで暗いほう（同じなら上）
    static func quieterEdge(top: [Double], bottom: [Double]) -> Edge {
        noise(bottom) < noise(top) ? .bottom : .top
    }

    /// 静かさを測る所（上の端・下の端の 936×300）
    static func edgeSample(_ edge: Edge, in frame: Frame) -> CGRect {
        let h: CGFloat = 300
        let y = edge == .top ? frame.textTop : frame.textBottom - h
        return CGRect(x: margin, y: y, width: contentWidth, height: h)
    }

    // MARK: - 題を幅に入れる

    /// 題の大きさと行。はじめの大きさから 60 まで縮めて1行に入れ、入らなければ2行に入る一番大きい大きさ。
    /// 60 の2行でも入らなければ2行目を「…」で切る（`truncated`）。`measure` は字の幅（字間込み）
    struct FittedTitle: Equatable {
        let size: CGFloat
        let lines: [String]
        let truncated: Bool
    }

    static func fitTitle(_ text: String, base: CGFloat, maxWidth: CGFloat = contentWidth,
                         measure: (String, CGFloat) -> CGFloat) -> FittedTitle {
        var size = base
        while size >= Title.minimumSize {
            if measure(text, size) <= maxWidth { return FittedTitle(size: size, lines: [text], truncated: false) }
            size -= 1
        }
        size = base
        while size >= Title.minimumSize {
            let lines = wrap(text, maxWidth: maxWidth) { measure($0, size) }
            if lines.count == 2, measure(lines[1], size) <= maxWidth {
                return FittedTitle(size: size, lines: lines, truncated: false)
            }
            size -= 1
        }
        let lines = wrap(text, maxWidth: maxWidth) { measure($0, Title.minimumSize) }
        return FittedTitle(size: Title.minimumSize, lines: lines, truncated: true)
    }

    /// 2行に分ける（1行目は幅に入る一番長い頭。ラテン文字の語の途中では切らない・行頭に句読点を置かない）
    static func wrap(_ text: String, maxWidth: CGFloat, measure: (String) -> CGFloat) -> [String] {
        let chars = Array(text)
        guard chars.count > 1 else { return [text] }
        var cut = 0
        for end in 1...chars.count {
            if measure(String(chars[0..<end])) <= maxWidth { cut = end } else { break }
        }
        if cut >= chars.count { return [text] }
        cut = max(1, cut)
        // ラテン文字の語の途中なら、その語の頭まで戻す（空白があれば）
        if chars[cut].isLetter, chars[cut - 1].isLetter, chars[cut].isASCII,
           let space = chars[0..<cut].lastIndex(of: " "), space > 0 {
            cut = space + 1
        }
        // 行頭に来てはいけない字（句読点・閉じ括弧・長音）は前の行に寄せず、1字前で切る
        let noStart: Set<Character> = ["、", "。", "，", "．", "」", "』", "）", ")", "！", "？", "!", "?", "ー", "…", ",", "."]
        while cut > 1, noStart.contains(chars[cut]) { cut -= 1 }
        let first = String(chars[0..<cut]).trimmingCharacters(in: .whitespaces)
        let rest = String(chars[cut...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? [first] : [first, rest]
    }

    // MARK: - 字の中身

    struct Texts: Equatable {
        /// 題（投稿の題。無ければ撮影地）。無ければ題の行を出さない
        let title: String?
        /// 撮影地（題が撮影地のときは nil・重ねない）
        let place: String?
        /// 撮影地を大きい単位だけにした字（撮影地の行が入らないとき）
        var placeFallback: String? = nil
        /// 「2026.10.10」。出さないなら nil
        let date: String?
        /// カメラ（無ければ nil）
        let camera: String?
        /// 絞り・シャッター・ISO（無い値は入れない）
        let values: [String]
        /// 自分の何番目の投稿か（`volume(of:among:)`）。分からなければ nil（「Vol.」も出さない）
        let volume: Int?

        var hasExif: Bool { camera != nil || !values.isEmpty }
    }

    /// 字を組む。`title` が空なら撮影地を題にし、撮影地の行には重ねない
    static func texts(title: String?, place: String?, placeFallback: String? = nil, takenDay: Date?, showsDate: Bool,
                      camera: String?, aperture: String?, exposure: String?, iso: Int?, volume: Int?) -> Texts {
        let ownTitle = title.flatMap(oneLine)
        let placeText = place.flatMap(oneLine)
        let date = showsDate ? takenDay.map(KoyomiCard.dateText) : nil
        // 大きい単位だけの字は、撮影地を出すときだけ（撮影地を伏せたら出さない）
        let fallback = placeText == nil ? nil : placeFallback.flatMap(oneLine).flatMap { $0 == placeText ? nil : $0 }
        let values = [aperture.flatMap(oneLine), exposure.flatMap(oneLine), iso.map { "ISO \($0)" }].compactMap { $0 }
        return Texts(title: ownTitle ?? placeText,
                     place: ownTitle == nil ? nil : placeText,
                     placeFallback: ownTitle == nil ? nil : fallback,
                     date: date,
                     camera: camera.flatMap(oneLine),
                     values: values,
                     volume: volume.flatMap { $0 > 0 ? $0 : nil })
    }

    /// 投稿の共有カード（`SignatureShareCardRenderer.Credit`）の字。撮影地は共有カードの2行（大きい単位・小さい単位）を1行に
    static func texts(for credit: SignatureShareCardRenderer.Credit) -> Texts {
        let place = credit.place ?? LocationMatch.shareCardPlace(credit.location)
        return texts(title: credit.title, place: placeLine(place), placeFallback: place?.primary,
                     takenDay: credit.takenDay, showsDate: credit.showsDate,
                     camera: credit.camera, aperture: credit.aperture, exposure: credit.exposure, iso: credit.iso,
                     volume: credit.volume)
    }

    /// 撮影地の2行を1行に。和文（日本・和名の国）は大きい順「石川県 金沢市」、ラテン文字は小さい順「Versailles, France」。
    /// 区切りに「・」を使わない
    static func placeLine(_ place: LocationMatch.ShareCardPlace?) -> String? {
        guard let place, let primary = oneLine(place.primary) else { return nil }
        guard let secondary = place.secondary.flatMap(oneLine), secondary != primary else { return primary }
        if LocationMatch.hasJapaneseScript(primary) { return "\(primary) \(secondary)" }
        return "\(secondary), \(primary)"
    }

    /// 改行・前後の空白を1行にそろえ、空なら nil
    static func oneLine(_ value: String) -> String? {
        let joined = value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - Vol. の番号

    /// その写真が自分の何番目の投稿か（2026-11-18 まとめ役の決定・判断）。
    /// - 数えるのは**自分の公開した投稿**（`/user/photos` の全件から下書き `published == false` を除く）
    /// - **同じ投稿の束（`groupId`）は1つ**と数える（何枚まとめて投稿しても1号）。束の時刻はいちばん早い1枚
    /// - 投稿した日時（`createdAt`・ISO8601 なので文字の順＝時刻の順）の古い順に 1 から。前の投稿を消すと繰り上がる
    /// - **分からないときは nil**（「Vol.」を出さない）: 一覧が無い（読めない・圏外）、写真が一覧に無い、
    ///   どれかの投稿に `createdAt` が無い（順が決められない）
    /// - `justPosted`: 投稿したばかりで、まだ一覧（利用者の索引・結果整合）に無い写真（`PostedPhotos` と同じ考え）
    static func volume(of photoId: String?, among mine: [Photo]?, justPosted: Photo? = nil) -> Int? {
        guard let photoId, !photoId.isEmpty, var all = mine else { return nil }
        if let justPosted, justPosted.id == photoId, !all.contains(where: { $0.id == photoId }) {
            all.append(justPosted)
        }
        let posts = all.filter { $0.published != false }
        guard let target = posts.first(where: { $0.id == photoId }) else { return nil }
        func key(_ photo: Photo) -> String {
            if let group = photo.groupId, !group.isEmpty { return "g:" + group }
            return "p:" + photo.id
        }
        var earliest: [String: String] = [:]
        for photo in posts {
            guard let created = photo.createdAt, !created.isEmpty else { return nil }
            let k = key(photo)
            if let known = earliest[k], known <= created { continue }
            earliest[k] = created
        }
        let ordered = earliest.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
        guard let index = ordered.firstIndex(where: { $0.key == key(target) }) else { return nil }
        return index + 1
    }
}
