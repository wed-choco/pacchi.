import SwiftUI
import CoreText

@MainActor enum LCDTypography {
    private static let available: Bool = {
        for name in ["DotGothic16-Regular", "DotGothic16"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        return names.contains("DotGothic16-Regular")
    }()
    static func font(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if available { return .custom("DotGothic16-Regular", fixedSize: size).weight(weight) }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
