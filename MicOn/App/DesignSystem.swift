import SwiftUI
import UIKit

enum MicOnStyle {
    static let background = Color(red: 0.137, green: 0.082, blue: 0.071)
    static let surface = Color(red: 0.208, green: 0.129, blue: 0.114)
    static let raised = Color(red: 0.290, green: 0.176, blue: 0.153)
    static let accent = Color(red: 1.000, green: 0.667, blue: 0.557)
    static let ink = Color(red: 0.169, green: 0.090, blue: 0.071)
    static let secondary = Color(red: 0.839, green: 0.722, blue: 0.671)
    static let paper = Color(red: 0.980, green: 0.929, blue: 0.882)
    static let paperSecondary = Color(red: 0.439, green: 0.282, blue: 0.231)
    static let mist = Color(red: 0.929, green: 0.831, blue: 0.765)
    static let line = Color.white.opacity(0.10)
    static let danger = Color(red: 1.000, green: 0.612, blue: 0.533)
}

// MARK: - Original raster artwork (Asset Catalog). Missing art never blocks layout or touch.

enum ArtworkCatalog {
    private static var cache: [String: Bool] = [:]
    static func has(_ name: String) -> Bool {
        if let known = cache[name] { return known }
        let found = UIImage(named: name) != nil
        cache[name] = found
        return found
    }
}

/// Square spot illustrations for empty states, sheets and cards.
struct BoothArtwork: View {
    enum Kind: String { case studio = "ArtStudio", lesson = "ArtLesson", pass = "ArtPass", notebook = "ArtNotebook" }
    let kind: Kind
    var height: CGFloat = 160
    var body: some View {
        Group {
            if ArtworkCatalog.has(kind.rawValue) {
                Image(kind.rawValue).renderingMode(.original).resizable().interpolation(.high).scaledToFit()
            } else { Color.clear }
        }
        .frame(width: height, height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Editorial covers for the guide and practice tools.
struct GuideArtwork: View {
    enum Subject: String {
        case breath = "GuideBreath"
        case phrase = "GuidePhrase"
        case distance = "GuideDistance"
        case chorus = "GuideChorus"
        case rest = "GuideRest"
        case listen = "GuideListen"
        case review = "ToolReview", speed = "ToolSpeed", frame = "ToolFrame", audio = "ToolAudio"
    }
    let subject: Subject
    var body: some View {
        MicOnStyle.raised.overlay {
            if ArtworkCatalog.has(subject.rawValue) {
                Image(subject.rawValue).renderingMode(.original).resizable().interpolation(.high).scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct BoothBanner: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalizedText("Find your karaoke voice.")
                .font(.booth(.largeTitle, display: true)).foregroundStyle(MicOnStyle.paper)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            LocalizedText("Work on a phrase, listen back, and take it to the next chorus.")
                .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(22).frame(maxWidth: .infinity, minHeight: 244, alignment: .bottomLeading)
            .background {
                GeometryReader { geometry in
                    Image("HeroBooth").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay {
                            LinearGradient(colors: [.clear, MicOnStyle.background.opacity(typeSize.isAccessibilitySize ? 0.94 : 0.86)],
                                           startPoint: .top, endPoint: .bottom)
                        }.clipped()
                }
            }.clipShape(.rect(cornerRadius: 22))
    }
}

// MARK: - Glyphs

enum MicOnGlyph: String, CaseIterable {
    case home, feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, mute, folder, settings
    var assetName: String { "Glyph" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    // Shown only while the original glyph artwork is missing, so every control stays usable.
    var fallbackTitle: String {
        switch self {
        case .home: "Home"; case .feed: "Watch"; case .edit: "Edit"; case .library: "Library"
        case .link: "Link"; case .search: "Search"; case .bookmark: "Saved"; case .download: "Download"
        case .play: "Play"; case .pause: "Pause"; case .close: "Close"; case .back: "Back"
        case .sound: "Sound"; case .mute: "Mute"; case .folder: "Folder"; case .settings: "Me"
        }
    }
}

/// Single-colour original glyph artwork, tinted at display time.
struct Glyph: View {
    @Environment(\.layoutDirection) private var direction
    let symbol: MicOnGlyph
    var size: CGFloat = 25
    var tint: Color = .white
    var body: some View {
        Group {
            if ArtworkCatalog.has(symbol.assetName) {
                Image(symbol.assetName).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(tint)
                    .scaleEffect(x: symbol == .back && direction == .rightToLeft ? -1 : 1, y: 1)
            } else { Color.clear }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Template artwork by asset name (player rail, tab-like controls).
struct TintedArtwork: View {
    let name: String
    var tint: Color = .white
    var body: some View {
        if ArtworkCatalog.has(name) {
            Image(name).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                .foregroundStyle(tint).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct IconButton: View {
    let symbol: MicOnGlyph
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if ArtworkCatalog.has(symbol.assetName) {
                    Glyph(symbol: symbol, size: 21, tint: selected ? MicOnStyle.accent : .white)
                } else {
                    LocalizedText(symbol.fallbackTitle).font(.booth(.caption2, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .background { if selected { BoothSurface(tone: .plum) } }
            .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey(label))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Controls

struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
// Compact controls keep their full localized label; enclosing layouts scroll or use ViewThatFits.
struct CompactActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.booth(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(MicOnStyle.paper)
            .background { BoothSurface(tone: .plum) }
            .contentShape(.interaction, Rectangle())
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
    }
}
struct ActionButton: View {
    let title: String
    var primary = true
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            LocalizedText(busy ? "Please wait…" : title).font(.booth(.headline, display: true))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(primary ? MicOnStyle.ink : MicOnStyle.paper)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(primary ? MicOnStyle.accent : MicOnStyle.raised, in: RoundedRectangle(cornerRadius: 22))
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).disabled(busy)
    }
}
struct MessagePanel: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText(title).font(.booth(.headline)).foregroundStyle(MicOnStyle.paper)
            LocalizedText(message).font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { ActionButton(title: actionTitle, primary: false, action: action) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MicOnStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
struct ErrorNote: View {
    @Environment(\.locale) private var locale
    let message: String
    var body: some View {
        LocalizedText(message).font(.booth(.subheadline)).foregroundStyle(MicOnStyle.danger)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityLabel(Text(verbatim: L10n.display("Error: \(message)", language: AppLanguage.from(locale))))
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.booth(.subheadline)).foregroundStyle(MicOnStyle.paper).padding(14)
            .background(MicOnStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .tint(MicOnStyle.accent)
    }
}
// Measure in the owning screen, so scrolling, keyboard avoidance and resizing
// keep the input exclusion region aligned. No global window or focus broadcast.
private struct KeyboardInputBounds: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $0.union($1) })
    }
}
private struct OutsideInputTap: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let scope: String
    @State private var inputBounds: CGRect?
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle()) // Hit area only.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(scope)).onEnded { tap in
                guard focus.wrappedValue, let inputBounds, !inputBounds.contains(tap.location) else { return }
                focus.wrappedValue = false
            })
            .onPreferenceChange(KeyboardInputBounds.self) { inputBounds = $0[scope] }
            .coordinateSpace(name: scope)
    }
}

extension View {
    func keyboardInputRegion(_ scope: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: KeyboardInputBounds.self,
                                       value: [scope: geometry.frame(in: .named(scope))])
            }.allowsHitTesting(false)
        }
    }
    func dismissKeyboardOnOutsideTap(_ focus: FocusState<Bool>.Binding, scope: String) -> some View {
        modifier(OutsideInputTap(focus: focus, scope: scope))
    }
    func miconField() -> some View { modifier(FieldStyle()) }
    // Extend visual surfaces to every container edge, while preserving keyboard avoidance
    // and the foreground's safe area for interactive controls.
    func miconScreenBackground(_ color: Color = MicOnStyle.background) -> some View {
        background { color.ignoresSafeArea(.container, edges: .all) }
    }
    // A readable column follows the available container (outer or inner display) without resetting state.
    func miconPage() -> some View {
        pageHorizontalMargins().padding(.top, 16).padding(.bottom, 24)
            .frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .top)
    }
    @ViewBuilder
    fileprivate func pageHorizontalMargins() -> some View {
        if #available(iOS 27.1, *) {
            contentMargins(for: .container, edges: .horizontal)
        } else {
            padding(.horizontal, 20)
        }
    }
}
struct MediaCover: View {
    let url: URL?
    var folder = false
    var body: some View {
        MicOnStyle.raised.overlay {
            GeometryReader { geometry in
                Group {
                    if folder { Glyph(symbol: .folder, size: 30) }
                    else if let url {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Glyph(symbol: .feed, size: 30) }
                        }
                    } else { Glyph(symbol: .feed, size: 30) }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }.clipped()
    }
}
struct SheetHeading: View {
    let title: String
    var close: () -> Void
    var body: some View {
        HStack {
            LocalizedText(title).font(.booth(.headline)).lineLimit(2)
            Spacer()
            IconButton(symbol: .close, label: "Close", action: close)
        }.pageHorizontalMargins().padding(.top, 8)
    }
}

struct SectionLabel: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText(title).font(.booth(.headline))
                Spacer(minLength: 12)
                if let detail { LocalizedText(detail).font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(title).font(.booth(.headline))
                if let detail { LocalizedText(detail).font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Original raster artwork. Its layout never participates in navigation hit testing.
struct MicOnIllustration: View {
    let name: String
    var height: CGFloat = 180
    var body: some View {
        Group {
            if ArtworkCatalog.has(name) {
                Image(name).renderingMode(.original).resizable().scaledToFit()
            } else { Color.clear }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct FeatureRow: View {
    let symbol: MicOnGlyph
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 16) {
            Glyph(symbol: symbol, size: 22)
                .frame(width: 48, height: 48)
                .background(MicOnStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(title).font(.booth(.subheadline, weight: .semibold)).foregroundStyle(MicOnStyle.paper)
                LocalizedText(detail).font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Surfaces (native fills; no drawn artwork)

struct BoothSurface: View {
    enum Tone { case accent, plum, blush, mist }
    let tone: Tone
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        switch tone {
        case .accent: shape.fill(MicOnStyle.accent)
        case .plum: shape.fill(MicOnStyle.raised).overlay(shape.strokeBorder(MicOnStyle.line))
        case .blush: shape.fill(MicOnStyle.paper)
        case .mist: shape.fill(MicOnStyle.surface).overlay(shape.strokeBorder(MicOnStyle.line))
        }
    }
}

/// Surfaces for controls placed on the blush paper card.
struct PaperSurface: View {
    enum Tone { case accent, plum, inkOnPaper, mistOnPaper }
    let tone: Tone
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        switch tone {
        case .accent: shape.fill(MicOnStyle.accent)
        case .plum: shape.fill(MicOnStyle.raised)
        case .inkOnPaper: shape.fill(MicOnStyle.ink)
        case .mistOnPaper: shape.fill(MicOnStyle.mist)
        }
    }
}

struct MatteActionStyle: ButtonStyle {
    var onPaper = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.booth(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(onPaper ? MicOnStyle.ink : MicOnStyle.paper)
            .background { PaperSurface(tone: onPaper ? .mistOnPaper : .plum) }
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.75 : 1))
    }
}

struct ChoiceStrip: View {
    let values: [String]
    let selected: String
    let select: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { select(value) } label: {
                        LocalizedText(value).font(.booth(.footnote, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected == value ? MicOnStyle.ink : MicOnStyle.paper)
                            .background { BoothSurface(tone: selected == value ? .accent : .plum) }
                            .contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                        .accessibilityAddTraits(selected == value ? .isSelected : [])
                }
            }
        }
    }
}
