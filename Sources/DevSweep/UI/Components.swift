import SwiftUI

extension Risk {
    var color: Color {
        switch self {
        case .safe: .green
        case .redownload: .orange
        case .dataLoss: .red
        }
    }
}

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// One-click button; items that lose data turn into a red "Confirm" on the first click.
struct ActionButton: View {
    var title: String?
    var symbol: String
    var confirm = false
    var busy = false
    var help: String?
    let action: () -> Void

    @State private var armed = false

    var body: some View {
        Button {
            if confirm && !armed {
                armed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { armed = false }
            } else {
                armed = false
                action()
            }
        } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.mini).frame(minWidth: 16)
                } else if armed {
                    Text(tr("action.confirm")).fontWeight(.semibold)
                } else if let title {
                    Label(title, systemImage: symbol)
                } else {
                    Image(systemName: symbol)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(armed ? .red : nil)
        .disabled(busy)
        .help(armed ? tr("action.confirm_help") : (help ?? title ?? ""))
    }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct MeterView: View {
    let title: String
    let fraction: Double
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(caption).font(.caption.monospacedDigit())
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(tint)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

extension View {
    func card() -> some View {
        background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.045)))
    }
}
