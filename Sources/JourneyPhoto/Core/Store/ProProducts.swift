import Foundation

// Pro（定期購入）の決まり。**StoreKit を読まない**——Linux の模型でもテストできるように、
// 商品の名前・プラン・購入者の印（appAccountToken）・画面の文字の計算だけをここに置く。
// StoreKit に触るのは `StoreService.swift`。

/// Pro のプラン。**並びは板 63 のとおり**（左が1年ごと・選んである方、右が月ごと）
enum ProPlan: String, CaseIterable, Identifiable, Equatable {
    case yearly, monthly

    var id: String { rawValue }

    /// 商品の名前の末尾（`<接頭辞>.pro.yearly`）
    var productSuffix: String { "pro.\(rawValue)" }

    /// 板の札の上の行（「1年ごと」「月ごと」）
    var cycleLabel: String {
        switch self {
        case .yearly: return L("1年ごと", "Yearly")
        case .monthly: return L("月ごと", "Monthly")
        }
    }

    /// 値段に付ける単位（「¥5,000 / 年」）
    var perUnit: String {
        switch self {
        case .yearly: return L("年", "year")
        case .monthly: return L("月", "month")
        }
    }

    /// 設定の行の頭（「月 ¥500」「年 ¥5,000」）
    var shortUnit: String {
        switch self {
        case .yearly: return L("年", "Yearly")
        case .monthly: return L("月", "Monthly")
        }
    }

    /// App Store Connect に置く値段（円）。**画面には StoreKit の値段を出す**——これは
    /// 商品が読めないとき（圏外・シミュレータ）に板どおりの値段を見せるためだけのもの
    var listPriceYen: Int {
        switch self {
        case .yearly: return 5_000
        case .monthly: return 500
        }
    }

    /// 商品が読めないときの値段の字（「¥5,000」）
    var fallbackPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return "¥" + (formatter.string(from: NSNumber(value: listPriceYen)) ?? String(listPriceYen))
    }

    /// 札の値段の行（「¥5,000 / 年」）
    func priceLine(displayPrice: String?) -> String {
        "\(displayPrice ?? fallbackPrice) / \(perUnit)"
    }
}

/// 商品の名前（App Store Connect の Product ID）。
///
/// **接頭辞はアプリの束の名前**（本番 `com.journeyphoto.JourneyPhoto`・staging は `….staging`）。
/// Info.plist の `JPStoreProductPrefix`（xcconfig の `JP_BUNDLE_ID`）から読み、無ければ束の名前。
/// staging と本番は App Store Connect では別のアプリなので、商品も別の名前になる
enum ProProducts {

    /// グループ名（App Store Connect のサブスクリプショングループ）。画面には出さない
    static let groupName = "Journey Photo Pro"

    static func productID(_ plan: ProPlan, prefix: String) -> String {
        "\(prefix).\(plan.productSuffix)"
    }

    static func allIDs(prefix: String) -> [String] {
        ProPlan.allCases.map { productID($0, prefix: prefix) }
    }

    /// 商品の名前からプランを引く（知らない名前は nil）
    static func plan(for productID: String, prefix: String) -> ProPlan? {
        ProPlan.allCases.first { self.productID($0, prefix: prefix) == productID }
    }

    /// 実行中のアプリの接頭辞
    static var currentPrefix: String {
        if let value = AppConfig.testOverrides?["JPStoreProductPrefix"] { return value }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "JPStoreProductPrefix") as? String {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // 置き換えられていない `$(JP_BUNDLE_ID)` を名前にしない
            if !value.isEmpty, !value.contains("$(") { return value }
        }
        return Bundle.main.bundleIdentifier ?? "com.journeyphoto.JourneyPhoto"
    }
}

// MARK: - 購入者の印（appAccountToken）

/// 購入に添える「誰が買ったか」の印。**サーバーと同じ作り方**で、利用者 ID から決まる UUID。
///
/// UUID 第5版（RFC 9562 の §5.5・SHA-1）: 名前空間 `namespace` と、利用者 ID の UTF-8 から作る。
/// サーバー（`api-user/src/appStore.ts`）は届いた取引の `appAccountToken` を同じ式で作った値と
/// 比べ、ほかの人の購入を自分のものとして受け取らない。
///
/// **名前空間を変えると、それまでの購入が誰のものか分からなくなる。** 変えない
enum AppAccountToken {

    /// 名前空間（サーバーと同じ値）
    static let namespace = UUID(uuidString: "5bbfc476-7442-4f3d-8d7e-4f55931ae30f")!

    static func make(userId: String) -> UUID {
        uuidV5(namespace: namespace, name: userId)
    }

    /// UUID 第5版
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        let ns = namespace.uuid
        var bytes: [UInt8] = [ns.0, ns.1, ns.2, ns.3, ns.4, ns.5, ns.6, ns.7,
                              ns.8, ns.9, ns.10, ns.11, ns.12, ns.13, ns.14, ns.15]
        bytes.append(contentsOf: Array(name.utf8))
        var hash = SHA1.digest(bytes)
        hash[6] = (hash[6] & 0x0F) | 0x50   // 版 5
        hash[8] = (hash[8] & 0x3F) | 0x80   // RFC の変種
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
    }
}

/// SHA-1（UUID 第5版のためだけ）。**署名や秘密には使わない**——CryptoKit は Linux の模型に無いので
/// 自前で持つ（RFC 3174）。正しさはテストの既知の値で見張る
enum SHA1 {
    static func digest(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }

        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(data[j]) << 24 | UInt32(data[j + 1]) << 16 | UInt32(data[j + 2]) << 8 | UInt32(data[j + 3])
            }
            for i in 16..<80 {
                w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default: f = b ^ c ^ d; k = 0xCA62C1D6
                }
                let temp = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotl(b, 30)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }
        var out: [UInt8] = []
        for h in [h0, h1, h2, h3, h4] {
            out.append(contentsOf: [UInt8(h >> 24), UInt8((h >> 16) & 0xFF), UInt8((h >> 8) & 0xFF), UInt8(h & 0xFF)])
        }
        return out
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
}

// MARK: - 取引を終えるか（サーバーに渡した結果で決める）

/// `POST /user/purchases` の結果から、StoreKit の取引を終える（`finish()`）かを決める。
///
/// Apple の決まり: **中身を渡し終えてから終える**。終えていない取引は、次の起動・
/// `Transaction.unfinished` で何度でも届き直す（渡し損ねても失われない）。
///
/// - 受け取った（2xx）→ 終える
/// - サーバーが「この取引は受け取れない」と言い切った（400 署名・商品が違う／403 ほかの人の
///   appAccountToken／410 退会済み）→ 終える。何度送っても通らず、終えないと起動のたびに
///   送り直し続ける（権利はサーバーが持つので、終えても購入は失われない）
/// - それ以外 → **終えない**（あとでやり直す）: 送れなかった（圏外）・ログインが切れた（401）・
///   409（「別のアカウントで使われている」と「書き込みが重なり続けた」の両方がこの番号で、
///   後者はやり直せば通る）・5xx・503（サーバーに App Store の設定がまだ無い）
enum PurchaseDelivery {
    enum Outcome: Equatable {
        case accepted
        case retryLater
        case rejected
    }

    /// サーバーの答え（結果と、画面に出してよい本文）
    struct Result: Equatable {
        let outcome: Outcome
        /// サーバーの `{ error }`（日本語）。無ければ nil
        let message: String?
        /// この Apple ID の購読が**別のアカウントのもの**（サーバーの 403・手元で見分けた前の人の印）。
        /// 画面は失敗の赤ではなく、ふつうの補足の字で `otherAccountMessage` を出す
        let otherAccount: Bool

        init(_ outcome: Outcome, message: String? = nil, otherAccount: Bool = false) {
            self.outcome = outcome
            self.message = message.flatMap { $0.isEmpty ? nil : $0 }
            self.otherAccount = otherAccount
        }
    }

    static func outcome(statusCode: Int?) -> Outcome {
        guard let code = statusCode else { return .retryLater }
        switch code {
        case 200..<300: return .accepted
        case 400, 403, 410: return .rejected
        default: return .retryLater
        }
    }

    static func shouldFinish(_ outcome: Outcome) -> Bool { outcome != .retryLater }

    /// 取引が**いまログインしている人のものではない**か（`appAccountToken` で見る）。
    ///
    /// 2026-10-09 判断: ほかの人の印が付いた取引は**送らず、終えもしない**（`retryLater` と同じ扱い）。
    /// 送るとサーバーは 403（ほかの人の購入）を返し、`shouldFinish` で終えてしまう。すると
    /// 「A が買った → サーバーに届かず（圏外・5xx）終えずに残る → 同じ端末で B がログイン →
    /// 送り直しで 403 → 終える」で、A の購入が二度と自動で届かなくなり、サーバーにも結び付かない
    /// （App Store の知らせも「まだ誰にも結び付いていない取引」として捨てられる）。
    /// 残しておけば、A がログインし直したときに `deliverUnfinished` で届く。
    ///
    /// 印の無い取引（App Store のアプリでコードを使った等）はサーバーに任せる（届いた人に結び付ける）
    static func belongsToSomeoneElse(appAccountToken: UUID?, userId: String) -> Bool {
        guard let token = appAccountToken else { return false }
        return token != AppAccountToken.make(userId: userId)
    }

    /// この Apple ID の購読が別のアカウントのものだったときの1行（owner 2026-10-09 の文言）。
    /// 退会して作り直したアカウントで、前のアカウントで買った購読を使おうとしたときなど。
    /// **Pro にはならない**（権利を決めるのはサーバー）
    static var otherAccountMessage: String {
        L("この Apple ID の購読は、別のアカウントで使われています。",
          "This Apple ID's subscription is being used by a different account.")
    }

    /// ファミリー共有で使えている取引は数えない（owner 2026-10-09: ファミリー共有は切ってある）。
    /// 送らず・終えず・設定の行にも出さない
    static func countsAsOwnPurchase(isFamilyShared: Bool) -> Bool { !isFamilyShared }
}

// MARK: - 設定の行の文字

/// 定期購入のいまの姿（StoreKit から読んだもの）
struct ProSubscriptionState: Equatable {
    let plan: ProPlan
    /// 次の更新日（自動更新が止まっていれば、期限の日）
    let renewalDate: Date?
    /// 自動で更新されるか（解約の予約をしていれば false）
    let willAutoRenew: Bool
    /// 値段（StoreKit の字。読めなければ nil）
    let displayPrice: String?
}

enum ProStatusText {

    /// 「2026.11.09」
    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 設定の「Journey Photo Pro」の行の2行目（板 43: 「月 ¥500 · 次の更新 2026.11.09 · App Store で管理」）。
    ///
    /// - Pro で、この端末の App Store で買った定期購入が読めた → 板の形。
    ///   解約を予約していれば「次の更新」の代わりに「2026.11.09 まで」
    /// - Pro だが読めない（別の Apple ID・読み込み中）→ 「App Store で管理」だけ
    /// - Pro でない → 値段と、案内の一言。**値段は App Store の字**（`monthlyPrice`・`Product.displayPrice`）。
    ///   読めないときだけ板の値段（2026-10-09 判断: 日本以外の App Store では円ではないのに「¥500」と出ていた）
    static func settingsDetail(isPro: Bool, state: ProSubscriptionState?, monthlyPrice: String? = nil,
                               timeZone: TimeZone = .current) -> String {
        let manage = L("App Store で管理", "Manage in App Store")
        guard isPro else {
            let price = monthlyPrice ?? ProPlan.monthly.fallbackPrice
            return L("月 \(price) から。サポーターバッジも付きます",
                     "From \(price)/month. Includes the supporter badge")
        }
        guard let state else { return manage }
        var parts = ["\(state.plan.shortUnit) \(state.displayPrice ?? state.plan.fallbackPrice)"]
        if let date = state.renewalDate {
            let day = self.day(date, timeZone: timeZone)
            parts.append(state.willAutoRenew ? L("次の更新 \(day)", "Renews \(day)") : L("\(day) まで", "Until \(day)"))
        }
        parts.append(manage)
        return parts.joined(separator: " · ")
    }

    /// 設定の「サポーター証」の行の2行目（板 43: 「No. 0001 · 手に取って回せます」）
    static func supporterDetail(number: Int) -> String {
        "\(SupporterText.numberLabel(number)) · " + L("手に取って回せます", "Turn it in your hand")
    }

    /// 設定の「名前の横のバッジと Pro マーク」の行の2行目（板 43: 「初期ユーザー · Pro マークは 絞り羽根」）。
    /// Pro でなければバッジだけ（Pro マークは Pro の間だけ出る）
    static func nameSideDetail(_ profile: UserProfile) -> String {
        let badge = profile.shownBadge.flatMap { BadgeCatalog.isKnown($0.key) ? BadgeCatalog.name($0.key) : nil }
            ?? L("バッジなし", "No badge")
        guard profile.isPro else { return badge }
        return badge + " · " + L("Pro マークは \(profile.markStyle.label)", "Pro mark: \(profile.markStyle.label)")
    }
}
