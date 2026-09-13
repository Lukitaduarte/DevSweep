import AppKit
import SwiftUI

@main
struct DevSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.shared.setup()
        Task { @MainActor in
            AppModel.shared.start()
            Updater.shared.start()
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let count = model.recommendations.filter { $0.risk != .dataLoss }.count
        let urgent = model.recommendations.contains(where: \.urgent) || model.system.pressure == .critical
        HStack(spacing: 3) {
            Image(systemName: urgent ? "exclamationmark.triangle.fill" : "sparkles")
            if count > 0 {
                Text("\(count)")
            }
        }
    }
}
