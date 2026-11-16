import SwiftUI

extension Font {
    static func booth(_ style: Font.TextStyle, weight: Font.Weight = .regular, display: Bool = false) -> Font {
        let emphasized = display || style == .headline
        return .system(style, weight: emphasized && weight == .regular ? .semibold : weight)
    }
}

struct MediaTitle: View {
    let title: String
    var textStyle: Font.TextStyle = .largeTitle
    var tint = MicOnStyle.paper

    var body: some View {
        LocalizedText(title)
            .font(.booth(textStyle, weight: .semibold))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct CoverTitle: View {
    @Environment(\.locale) private var locale
    let title: String
    var size: CGFloat = 58
    var textStyle: Font.TextStyle = .largeTitle
    var tint = MicOnStyle.paper

    private var font: Font {
        switch AppLanguage.from(locale) {
        case .ar, .ja, .ko:
            .system(textStyle, weight: .semibold)
        case .en, .es, .id, .pt:
            .custom("InstrumentSerif-Regular", size: size, relativeTo: textStyle)
        }
    }

    var body: some View {
        LocalizedText(title)
            .font(font)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
