import AppKit
import SwiftUI

@MainActor
final class DialUpPanelController: ObservableObject {
    private let connection: ConnectionManager
    private var panel: NSPanel?

    init(connection: ConnectionManager) {
        self.connection = connection
    }

    func show() {
        let targetPanel: NSPanel
        if let panel {
            targetPanel = panel
        } else {
            targetPanel = makePanel()
            panel = targetPanel
        }
        if let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow {
            let frame = targetPanel.frame
            let origin = NSPoint(
                x: mainWindow.frame.maxX - frame.width - 16,
                y: mainWindow.frame.minY + 80
            )
            targetPanel.setFrameOrigin(origin)
        }
        targetPanel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let collapsedHeight: CGFloat = 310
        let expandedHeight: CGFloat = 460

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: collapsedHeight),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "RetroSurf ISP"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(
            rootView: DialUpStatusView(onDebugToggle: { [weak panel] expanded in
                guard let panel else { return }
                let targetHeight: CGFloat = expanded ? expandedHeight : collapsedHeight
                if abs(panel.frame.height - targetHeight) > 1 {
                    panel.setContentSize(NSSize(width: 400, height: targetHeight))
                }
            })
            .environmentObject(connection)
        )
        hosting.autoresizingMask = [.width, .height]

        panel.contentView = hosting
        hosting.frame = panel.contentView?.bounds ?? hosting.frame
        return panel
    }
}