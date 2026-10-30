import AppKit
import SwiftUI
import CheckedPlayers

/// The window the check step's Continue… opens before the check starts
/// (W6, the user, 2026-10-15): the 7 states the app's window goes
/// through, that the mouse and keyboard are blocked meanwhile and the
/// screen dims (but for the panel), how long it takes; Start the Check.
struct CheckWarningView: View {
    let app: CheckableApp
    /// What's muted during the check: the app (its sound tapped), else the
    /// Mac's output; an output with no mute control can't be, and the user
    /// hears the app.
    var muting = AddAppModel.CheckMuting.app
    /// Mission Control's desktop shortcuts are off (`DesktopShortcuts`):
    /// the check can't show another desktop, and says how to turn them on,
    /// with a button to Keyboard settings (K2, the user's pick, 2026-10-30).
    var desktopShortcutsOff = false
    var openKeyboardSettings: () -> Void = {}
    let start: () -> Void
    let cancel: () -> Void

    /// The window's width, Add an App's, which its bottom bar's buttons fit
    /// in every language.
    static let width = AddAppView.width

    var body: some View {
        WindowPage(icon: AppIcon.appImage(bundlePath: app.url.path, size: 56),
                   description: Text(verbatim: AddAppText.warningDescription(app.name)), width: Self.width) {
            SectionHeading(Text(verbatim: AddAppText.statesHeading(app.name))).padding(.top, 8)
            Card {
                VStack(spacing: 10) {
                    // Four columns: the last row's tiles under the first row's.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 4), spacing: 10) {
                        ForEach(CheckResult.WindowState.trip, id: \.self, content: tile)
                    }
                    Text(verbatim: AddAppText.statesNote(app.name)).captionStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if desktopShortcutsOff {
                        NoteLabel(AddAppText.desktopShortcutsOff(app.name), font: .appCaption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: openKeyboardSettings) { Text(verbatim: AddAppText.openKeyboardSettings) }
                            .buttonStyle(.chip)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            SectionHeading(Text(verbatim: AddAppText.movingHeading)).padding(.top, 8)
            Card {
                HStack(alignment: .top, spacing: 12) {
                    DimmedScreenPicture()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: AddAppText.blockedTitle).fontWeight(.semibold)
                        Text(verbatim: AddAppText.blockedDetail).captionStyle()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 14) {
                Label(AddAppText.aboutThreeMinutes, systemImage: "clock")
                switch muting {
                case .app: Label(AddAppText.mutedMeanwhile(app.name), systemImage: "speaker.slash")
                case .mac: Label(AddAppText.macMutedMeanwhile, systemImage: "speaker.slash")
                case .none: Label(AddAppText.heardMeanwhile(app.name), systemImage: "speaker.wave.2")
                }
                Label(AddAppText.allPutBack, systemImage: "arrow.uturn.backward")
            }
            .font(.appCaption)
            .foregroundStyle(.appSecondary)
            .padding(.top, 2)
        } bar: {
            Button(action: cancel) { Text(verbatim: ButtonText.cancel) }
                .buttonStyle(.chip)
                .keyboardShortcut(.cancelAction)
            Spacer()
            MainButton(AddAppText.startCheck, action: start)
        }
    }

    private func tile(_ state: CheckResult.WindowState) -> some View {
        VStack(spacing: 4) {
            SymbolTile(symbol: Self.symbol(state))
                // Its arrow points the way the next desktop is, also right to left.
                .flipsForRightToLeftLayoutDirection(state == .otherDesktop)
            Text(verbatim: AddAppText.stateLabel(state))
                .font(.appCaption).foregroundStyle(.appSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ state: CheckResult.WindowState) -> String {
        switch state {
        case .visible: "macwindow"
        case .covered: "macwindow.on.rectangle"
        case .otherDesktop: "rectangle.righthalf.inset.filled.arrow.right"
        // Another desktop, as switching to it (unlike "Covered"'s windows).
        case .otherDesktopCovered: "rectangle.2.swap"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .minimized: "dock.arrow.down.rectangle"
        case .hidden: "eye.slash"
        // Never a tile: an app with no window open, whose window isn't moved.
        case .windowsClosed: "xmark.rectangle"
        }
    }
}

/// A screen while the check moves windows: dimmed, but for its panel. A
/// drawing of a screen, in a wallpaper's colours (the style guide's
/// exception for drawn pictures).
private struct DimmedScreenPicture: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9)).frame(width: 64, height: 40)
                .padding(.trailing, 58).padding(.bottom, 34)
            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.55))
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(.secondary.opacity(0.6)).frame(width: 30, height: 3)
                Capsule().fill(Color.accentColor).frame(height: 2)
                Capsule().fill(.secondary.opacity(0.4)).frame(width: 14, height: 6)
            }
            .padding(6).frame(width: 54)
            .background(RoundedRectangle(cornerRadius: 4).fill(.background))
            .padding(5)
        }
        .frame(width: 136, height: 86)
        .accessibilityHidden(true)
    }
}
