import SwiftUI

/// The text sizes of the menu, Settings and the welcome window: one step
/// above the system's, so descriptions and labels read easily.
extension Font {
    /// The app's name in Settings → About.
    static let appLargeTitle = Font.system(size: 24, weight: .bold)
    /// Plain text and rows' titles.
    static let appBody = Font.system(size: 14)
    /// A card's title, e.g. the media player's name.
    static let appHeadline = Font.system(size: 14, weight: .bold)
    /// Buttons, values and notes.
    static let appCallout = Font.system(size: 13)
    /// The line under the card's title: what's happening.
    static let appSubheadline = Font.system(size: 12)
    /// Descriptions under rows, section labels and captions.
    static let appCaption = Font.system(size: 11)
    /// A page's name in Settings' sidebar.
    static let appSidebarRow = Font.system(size: 16)
    /// AutoHush's name at the foot of Settings' sidebar.
    static let appSidebarName = Font.system(size: 15, weight: .semibold)
}

/// A style with one value in light mode and another in dark mode. The
/// system's secondary text, orange and fills are too faint in light mode,
/// on the menu's white and on Settings' grey, so light mode gets darker ones;
/// dark mode keeps the system's.
struct AppearanceStyle: ShapeStyle {
    let light: AnyShapeStyle
    let dark: AnyShapeStyle

    init(light: some ShapeStyle, dark: some ShapeStyle) {
        self.light = AnyShapeStyle(light)
        self.dark = AnyShapeStyle(dark)
    }

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.colorScheme == .dark ? dark : light
    }
}

/// The colors the menu, Settings and the welcome window share. In light
/// mode, text keeps a contrast of at least 4.5:1 against its background.
extension ShapeStyle where Self == AppearanceStyle {
    /// Descriptions under rows, section labels and captions.
    static var appSecondary: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.68), dark: .secondary)
    }
    /// Text and icons that need the user's attention: a deep orange in light
    /// mode, where the system's is hard to read.
    static var appWarning: AppearanceStyle {
        AppearanceStyle(light: Color(red: 0xB0 / 255, green: 0x30 / 255, blue: 0), dark: .orange)
    }
    /// A card's background.
    static var cardFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.05), dark: .quaternary.opacity(0.6))
    }
    /// A card's outline: in light mode only, where the fill alone barely
    /// shows against the menu's white.
    static var cardBorder: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.1), dark: Color.clear)
    }
    /// A filled chip's background, at rest.
    static var chipFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.08), dark: .quaternary.opacity(0.6))
    }
    /// A chip's background under the pointer: a step above `chipFill`.
    static var chipHoverFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.13), dark: .quaternary)
    }
    /// Icons for what works: Diagnostics' checks.
    static var appSuccess: AppearanceStyle {
        AppearanceStyle(light: Color.green, dark: Color.green)
    }
    /// A switch's track while it's off.
    static var switchOffFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.26), dark: .quaternary)
    }
    /// Behind a `HeadingBadge`: `appWarning`, faint.
    static var warningBadgeFill: AppearanceStyle {
        AppearanceStyle(light: Color(red: 0xB0 / 255, green: 0x30 / 255, blue: 0).opacity(0.12), dark: Color.orange.opacity(0.18))
    }

    /// Behind a list row the user selected (Settings → Apps).
    static var selectedRowFill: AppearanceStyle {
        AppearanceStyle(light: Color.accentColor.opacity(0.14), dark: Color.accentColor.opacity(0.18))
    }

    /// Behind the chosen player's tile (`PlayerTiles`).
    static var selectedTileFill: AppearanceStyle {
        AppearanceStyle(light: Color.accentColor.opacity(0.18), dark: Color.accentColor.opacity(0.22))
    }

    /// Behind the page shown, in Settings' sidebar.
    static var sidebarSelectionFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.1), dark: .quaternary)
    }

    /// The square behind a `SymbolTile`'s symbol (Settings' sidebar, the
    /// welcome window's permissions): the accent color the user picked,
    /// faint.
    static var symbolTileFill: AppearanceStyle {
        AppearanceStyle(light: Color.accentColor.opacity(0.16), dark: Color.accentColor.opacity(0.2))
    }
}

/// A switch drawn in the accent color, the same in the menu and in Settings.
/// The system's switch would be grey in the menu: menus draw it inactive,
/// since AutoHush doesn't become the active app when its menu opens.
struct PillToggleStyle: ToggleStyle {
    var width: CGFloat = 36
    var height: CGFloat = 21

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.switchOffFill))
                .frame(width: width, height: height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5).padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // VoiceOver gets a switch with its label.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A rounded button that lights up under the pointer, like the menu's rows.
/// Filled, it's a chip, as for the menu's duration buttons and Settings'
/// buttons; selected, it's filled with the accent color. On macOS 26 and
/// later a filled chip is Liquid Glass (tinted with the accent color when
/// selected); a button's chip (`padded`) is then a capsule.
struct ChipButtonStyle: ButtonStyle {
    var filled = false
    var isSelected = false
    var cornerRadius: CGFloat = 8
    /// Room around a plain label, such as a text button's title; off for
    /// labels that make their own.
    var padded = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *), filled {
            GlassChip(isSelected: isSelected, shape: padded ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))) {
                configuration.label
                    .padding(.horizontal, padded ? 14 : 0)
                    .padding(.vertical, padded ? 6 : 0)
            }
        } else {
            HoverHighlight(isPressed: configuration.isPressed, filled: filled, isSelected: isSelected, cornerRadius: cornerRadius) {
                configuration.label
                    .padding(.horizontal, padded ? 12 : 0)
                    .padding(.vertical, padded ? 5 : 0)
            }
        }
    }

    /// A filled chip as Liquid Glass, which lights up under the pointer and
    /// when pressed by itself (`interactive`).
    @available(macOS 26, *)
    private struct GlassChip<Label: View>: View {
        let isSelected: Bool
        let shape: AnyShape
        @ViewBuilder let label: Label
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .glassEffect(isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: shape)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }

    private struct HoverHighlight<Label: View>: View {
        let isPressed: Bool
        let filled: Bool
        let isSelected: Bool
        let cornerRadius: CGFloat
        @ViewBuilder let label: Label
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }

        private var fill: AnyShapeStyle {
            if isSelected { return AnyShapeStyle(Color.accentColor.opacity(isPressed ? 0.8 : 1)) }
            guard isEnabled else { return filled ? AnyShapeStyle(.chipFill) : AnyShapeStyle(.clear) }
            if isPressed { return AnyShapeStyle(.tertiary) }
            if isHovered { return AnyShapeStyle(.chipHoverFill) }
            return filled ? AnyShapeStyle(.chipFill) : AnyShapeStyle(.clear)
        }
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    /// A filled chip, the look of Settings' buttons.
    static var chip: ChipButtonStyle { ChipButtonStyle(filled: true, padded: true) }
}

/// A small heading over a group of controls: a card, or the menu's buttons.
struct SectionLabel: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title.font(.appCaption).foregroundStyle(.appSecondary)
    }
}

/// A word in a capsule after a heading that qualifies everything under it,
/// e.g. "Experimental" after "Safari Web Apps".
struct HeadingBadge: View {
    /// Already localized.
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(.appWarning)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.warningBadgeFill))
            .fixedSize()
    }
}

/// The heading over a card in Settings, e.g. "Timing": a section label in
/// line with the card's text, with room above it unless it's the first
/// thing on its tab.
struct SectionHeading: View {
    let title: Text
    var isFirst = false

    init(_ title: Text, isFirst: Bool = false) {
        self.title = title
        self.isFirst = isFirst
    }

    var body: some View {
        SectionLabel(title)
            .padding(.leading, 4)
            .padding(.top, isFirst ? 0 : 6)
    }
}

extension View {
    /// Descriptions and notes under a card or a control: small, grey, and
    /// on as many lines as they need.
    func captionStyle() -> some View {
        font(.appCaption)
            .foregroundStyle(.appSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small chip showing a symbol, beside a heading or a pop-up: the Apps
/// tab's order and search, and the music players' search. Its label is what
/// VoiceOver says and, without a `help` of its own, its tooltip.
struct IconChipButton: View {
    let symbol: String
    let label: Text
    var help: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.appCaption.weight(.semibold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(ChipButtonStyle(filled: true, cornerRadius: 6))
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

/// A symbol on a square tinted with the accent color: Settings' sidebar
/// shows its pages this way, the welcome window its permissions.
struct SymbolTile: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.symbolTileFill)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .accessibilityHidden(true)
    }
}

/// A group of controls on a rounded, tinted background: the menu's card,
/// and each group in Settings. On macOS 26 and later it's a Liquid Glass
/// panel, a little rounder and roomier.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    @ViewBuilder var body: some View {
        if #available(macOS 26, *) {
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(padding + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.cardBorder, lineWidth: 1))
        }
    }
}

/// The line between two rows of a card.
struct CardDivider: View {
    var body: some View {
        Divider().opacity(0.5)
    }
}

/// A title, an optional description under it, and a switch.
struct SwitchRow: View {
    let title: Text
    var subtitle: Text?
    @Binding var isOn: Bool

    init(_ title: Text, subtitle: Text? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 10) {
            RowTitle(title, subtitle: subtitle)
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) { title }
                .toggleStyle(PillToggleStyle())
        }
    }
}

/// A row's title, with an optional description under it.
struct RowTitle: View {
    let title: Text
    var subtitle: Text?

    init(_ title: Text, subtitle: Text? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            title
            if let subtitle {
                subtitle
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One choice among a few, as a row of chips; the chosen one is filled with
/// the accent color. An option can be unavailable: dimmed and not chosen,
/// but a click on it is reported, so the view can say why.
struct ChoiceChips<Value: Hashable>: View {
    struct Option {
        let title: String
        let value: Value
        var isAvailable = true
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void
    /// A click on an unavailable option.
    var onUnavailableClick: () -> Void = {}
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    option.isAvailable ? onSelect(option.value) : onUnavailableClick()
                } label: {
                    Text(verbatim: option.title)
                        .font(.appCallout)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: option.value == selection))
                // A disabled group is dimmed already: once is enough.
                .opacity(option.isAvailable || !isEnabled ? 1 : 0.45)
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The buttons at the foot of a Settings page whose list scrolls (Apps,
/// Diagnostics) or of a window (welcome, Add a Web App, learning): a line
/// above them while the content runs under them. `margin`: the page's or
/// window's side margin, which the buttons line up with.
struct BottomBar<Content: View>: View {
    var showsDivider = true
    var margin: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { Divider() }
            HStack { content }
                .padding(.horizontal, margin)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
    }
}
