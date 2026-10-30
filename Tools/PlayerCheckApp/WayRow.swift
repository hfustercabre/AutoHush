import PlayerCheckKit
import SwiftUI

struct WayRow: View {
    let way: Way
    /// Plays or pauses it this way; nil: no buttons.
    var control: ((CommandLineOptions.Action) -> Void)?
    var isBusy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(way.title).fontWeight(.medium)
                    if !way.detail.isEmpty {
                        Text(way.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    // The window states it failed in, and those not tested.
                    ForEach(way.states.indices, id: \.self) { index in
                        let state = way.states[index]
                        Label {
                            Text("\(Text(state.state).fontWeight(.medium)): \(state.why)")
                        } icon: {
                            Image(systemName: state.failed ? "xmark" : "minus")
                        }
                        .font(.caption)
                        .foregroundStyle(state.failed ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(way.title). \(way.detail)"
                                + way.states.map { ". \($0.failed ? "Failed" : "Not tested") \($0.state): \($0.why)" }.joined())
            Spacer(minLength: 8)
            if let control, let via = way.via {
                let name = via.inSentence
                Button { control(.play) } label: { Image(systemName: "play.fill") }
                    .help("Play by \(name)").accessibilityLabel("Play by \(name)")
                Button { control(.pause) } label: { Image(systemName: "pause.fill") }
                    .help("Pause by \(name)").accessibilityLabel("Pause by \(name)")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
    }

    private var symbol: String {
        switch way.mark {
        case .works: "checkmark.circle.fill"
        case .some: "exclamationmark.triangle.fill"
        case .notTried: "questionmark.circle.fill"
        case .none: "xmark.circle.fill"
        case .notChecked: "minus.circle"
        }
    }
    private var tint: Color {
        switch way.mark {
        case .works: .green
        case .some: .orange
        case .notTried: .orange
        case .none: .red
        case .notChecked: .secondary
        }
    }
    private var label: String {
        switch way.mark {
        case .works: "Works"
        case .some: "Works in some states"
        case .notTried: "Found, not tried"
        case .none: "No"
        case .notChecked: "Not checked"
        }
    }
}
