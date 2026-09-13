import AppKit
import SwiftUI

struct SuggestionsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 0) {
            if let version = updater.availableVersion {
                UpdateCard(version: version)
                    .padding([.horizontal, .top], 12)
            }
            if model.recommendations.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38))
                .foregroundStyle(.green)
            Text(tr("suggestions.empty.title")).font(.headline)
            Text(model.isScanningStorage ? tr("suggestions.empty.scanning") : tr("suggestions.empty.idle"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.recommendations) { recommendation in
                    RecommendationRow(recommendation: recommendation)
                }
                if model.isScanningStorage {
                    Label(tr("suggestions.measuring"), systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(12)
            .padding(.bottom, 40)
        }
    }
}

private struct UpdateCard: View {
    let version: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("update.available_title", ["version": version]))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(tr("update.available_detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(tr("update.changelog")) {
                NSWorkspace.shared.open(Updater.releaseURL(for: version))
            }
            .controlSize(.small)
            Button(tr("update.install")) {
                Updater.shared.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .card()
    }
}

private struct RecommendationRow: View {
    @EnvironmentObject private var model: AppModel
    let recommendation: Recommendation

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: recommendation.isProcess ? "bolt.horizontal.circle" : recommendation.stack.icon)
                .font(.system(size: 16))
                .foregroundStyle(recommendation.urgent ? Color.red : Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(recommendation.title).font(.system(size: 12.5, weight: .semibold))
                    if recommendation.risk != .safe {
                        Tag(text: recommendation.risk.label, color: recommendation.risk.color)
                    }
                }
                Text(recommendation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(recommendation.amountText)
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            Spacer(minLength: 8)
            ActionButton(
                title: recommendation.isProcess ? tr("action.stop") : tr("action.clean"),
                symbol: recommendation.isProcess ? "xmark.circle" : "trash",
                confirm: recommendation.risk == .dataLoss,
                busy: model.isBusy(recommendation)
            ) {
                Task { await model.perform(recommendation) }
            }
        }
        .padding(10)
        .card()
    }
}
