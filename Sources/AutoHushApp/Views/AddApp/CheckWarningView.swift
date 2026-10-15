import AppKit
import SwiftUI
import CheckedPlayers

/// The window the check step's Continue… opens before the check starts
/// (W6, the user, 2026-10-15): the 7 states the app's window goes
/// through, that the mouse and keyboard are blocked meanwhile and the
/// screen dims (but for the panel), how long it takes; Start the Check.
struct CheckWarningView: View {
    let app: CheckableApp
    let start: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                WindowHeader(icon: AppIcon.appImage(bundlePath: app.url.path, size: 56),
                             description: Text(verbatim: AddAppText.warningDescription(app.name)))
                SectionHeading(Text(verbatim: AddAppText.statesHeading(app.name))).padding(.top, 8)
                Card {
                    VStack(spacing: 10) {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(Array(CheckResult.WindowState.allCases.prefix(4)), id: \.self, content: tile)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(Array(CheckResult.WindowState.allCases.dropFirst(4)), id: \.self, content: tile)
                        }
                        Text(verbatim: AddAppText.statesNote(app.name))
                            .captionStyle().fixedSize(horizontal: false, vertical: true)
                    }
                }
                SectionHeading(Text(verbatim: AddAppText.movingHeading)).padding(.top, 8)
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        DimmedScreenPicture()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: AddAppText.blockedTitle).fontWeight(.semibold)
                            Text(verbatim: AddAppText.blockedDetail)
                                .captionStyle().fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 14) {
                    Label(AddAppText.aboutThreeMinutes, systemImage: "clock")
                    Label(AddAppText.mutedMeanwhile(app.name), systemImage: "speaker.slash")
                    Label(AddAppText.allPutBack, systemImage: "arrow.uturn.backward")
                }
                .font(.appCaption)
                .foregroundStyle(.appSecondary)
                .padding(.top, 2)
            }
            .windowMargins()
            BottomBar(margin: HostedWindowController.margin) {
                Button(action: cancel) { Text(verbatim: AddAppText.cancel) }
                    .buttonStyle(.chip)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: start) {
                    Text(verbatim: AddAppText.startCheck).font(.appBody.weight(.semibold)).padding(.horizontal, 6)
                }
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 460)
        .font(.appBody)
    }

    private func tile(_ state: CheckResult.WindowState) -> some View {
        VStack(spacing: 4) {
            SymbolTile(symbol: Self.symbol(state))
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
        case .otherDesktopCovered: "rectangle.on.rectangle"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .minimized: "dock.arrow.down.rectangle"
        case .hidden: "eye.slash"
        }
    }
}

/// A screen while the check moves windows: dimmed, but for its panel.
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
