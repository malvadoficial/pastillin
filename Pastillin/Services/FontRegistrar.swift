import Foundation
import CoreText

enum FontRegistrar {
    static func registerAppFonts() {
        registerFont(filename: "Manrope.ttf")
    }

    private static func registerFont(filename: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
