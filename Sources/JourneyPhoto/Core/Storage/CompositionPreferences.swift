import Foundation

/// 「構図を重ねて撮る」で選んだものを端末に覚える（最後の構図・最近の4つ・構図ごとの向き・回した角度・線の濃さ）。
///
/// **サーバーには送らない**（端末の好みだけ・2026-10-10）。アカウントにも結び付けない——
/// 構図の好みは人の情報ではなく道具の設定なので、同じ端末で別の人が使っても困らない。
/// 壊れた値・知らない名前（構図を減らした版で残った値）は黙って捨て、既定（三分割）に戻す。
struct CompositionPreferences {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let last = "journey-photo-composition-last"
        static let recents = "journey-photo-composition-recents"
        static let variants = "journey-photo-composition-variants"
        static let lineOpacity = "journey-photo-composition-line-opacity"
        /// 構図ごとの回した角度（2026-10-16）。**向き（反転）の `variants` とは別の鍵**——前の版で
        /// 覚えた向きの値（整数）はそのまま読める
        static let rotations = "journey-photo-composition-rotations"
    }

    /// 「なし」を覚えるときの値
    private static let noneValue = "none"

    /// 最後に選んだ構図。nil は「なし」。まだ何も選んでいなければ既定（三分割）
    var lastKind: CompositionKind? {
        guard let raw = defaults.string(forKey: Key.last) else { return CompositionKind.defaultKind }
        if raw == Self.noneValue { return nil }
        return CompositionKind(rawValue: raw) ?? CompositionKind.defaultKind
    }

    /// 最近の構図（新しい順・重ならない・上限 4）
    var recents: [CompositionKind] {
        let raw = defaults.stringArray(forKey: Key.recents) ?? []
        var out: [CompositionKind] = []
        for value in raw {
            guard let kind = CompositionKind(rawValue: value), !out.contains(kind) else { continue }
            out.append(kind)
        }
        return Array(out.prefix(CompositionGuide.recentLimit))
    }

    /// 構図を選んだ。nil は「なし」（最近には足さない）
    func select(_ kind: CompositionKind?) {
        defaults.set(kind?.rawValue ?? Self.noneValue, forKey: Key.last)
        // 2026-10-16 判断: 回した角度は「その構図を選び直すまで」保つ。シートで選び直したら真っ直ぐ（0°）に戻す
        setRotation(0, for: kind)
        guard let kind else { return }
        defaults.set(CompositionGuide.recents(adding: kind, to: recents).map(\.rawValue), forKey: Key.recents)
    }

    /// 構図ごとの向き（覚えていなければ 0）
    func variant(for kind: CompositionKind) -> Int {
        let map = defaults.dictionary(forKey: Key.variants) as? [String: Int] ?? [:]
        return kind.normalizedVariant(map[kind.rawValue] ?? 0)
    }

    func setVariant(_ variant: Int, for kind: CompositionKind) {
        var map = defaults.dictionary(forKey: Key.variants) as? [String: Int] ?? [:]
        map[kind.rawValue] = kind.normalizedVariant(variant)
        defaults.set(map, forKey: Key.variants)
    }

    /// 回した角度（時計回りの度・0〜360 未満）。覚えていない・壊れた値は 0。
    /// `kind` が nil（「なし」）でも、重ねている参考写真の向きとして覚える
    func rotation(for kind: CompositionKind?) -> Double {
        let map = defaults.dictionary(forKey: Key.rotations) ?? [:]
        guard let value = map[kind?.rawValue ?? Self.noneValue] as? Double else { return 0 }
        return CompositionGuide.normalizedRotation(value)
    }

    func setRotation(_ degrees: Double, for kind: CompositionKind?) {
        var map = defaults.dictionary(forKey: Key.rotations) as? [String: Double] ?? [:]
        map[kind?.rawValue ?? Self.noneValue] = CompositionGuide.normalizedRotation(degrees)
        defaults.set(map, forKey: Key.rotations)
    }

    /// 線の濃さ（覚えていなければ既定 0.35）
    var lineOpacity: Double {
        guard defaults.object(forKey: Key.lineOpacity) != nil else { return CompositionGuide.defaultLineOpacity }
        return CompositionGuide.clampedLineOpacity(defaults.double(forKey: Key.lineOpacity))
    }

    func setLineOpacity(_ value: Double) {
        defaults.set(CompositionGuide.clampedLineOpacity(value), forKey: Key.lineOpacity)
    }
}
