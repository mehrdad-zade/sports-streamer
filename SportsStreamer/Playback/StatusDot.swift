import SwiftUI

struct StatusDot: View {
    let status: StreamSource.Status

    var body: some View {
        Group {
            if status == .checking {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
        }
        .frame(width: 12, height: 12)
    }

    private var color: Color {
        switch status {
        case .alive: .green
        case .dead: .red
        case .checking, .unknown: .gray
        }
    }
}

extension StreamSource.Status {
    var description: String {
        switch self {
        case .unknown: "Not checked yet"
        case .checking: "Checking…"
        case .alive: "Live"
        case .dead: "Offline"
        }
    }
}
