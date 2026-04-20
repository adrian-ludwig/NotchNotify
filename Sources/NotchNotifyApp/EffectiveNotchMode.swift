struct EffectiveNotchMode {
    static func resolve(notchMode: NotchMode, targetScreenHasNotch: Bool) -> Bool {
        switch notchMode {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            return targetScreenHasNotch
        }
    }
}
