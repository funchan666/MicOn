import SwiftUI

extension Font {
    static func booth(_ style: Font.TextStyle, weight: Font.Weight = .regular, display: Bool = false) -> Font {
        let emphasized = display || style == .headline
        return .system(style, weight: emphasized && weight == .regular ? .semibold : weight)
    }
}

struct CoverTitle: View {
    @Environment(\.locale) private var locale
    let title: String
    var size: CGFloat = 58

    private var font: Font {
        switch AppLanguage.from(locale) {
        case .ar, .ja, .ko:
            .system(.largeTitle, weight: .semibold)
        case .en, .es, .id, .pt:
            .custom("InstrumentSerif-Regular", size: size, relativeTo: .largeTitle)
        }
    }

    var body: some View {
        LocalizedText(title)
            .font(font)
            .foregroundStyle(MicOnStyle.paper)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
