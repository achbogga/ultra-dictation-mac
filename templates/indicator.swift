#!/usr/bin/env swift

import AppKit

enum IndicatorState: String {
    case on
    case off
    case error
}

struct IndicatorStyle {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: NSColor
}

let args = Array(CommandLine.arguments.dropFirst())
let state = IndicatorState(rawValue: args.first ?? "") ?? .on

let style: IndicatorStyle = {
    switch state {
    case .on:
        return IndicatorStyle(
            title: "Dictation On",
            subtitle: "Recording session",
            symbolName: "mic.fill",
            tint: .systemGreen
        )
    case .off:
        return IndicatorStyle(
            title: "Dictation Off",
            subtitle: "Transcribing and pasting",
            symbolName: "mic.slash.fill",
            tint: .systemRed
        )
    case .error:
        return IndicatorStyle(
            title: "Dictation Error",
            subtitle: "Check the install or log",
            symbolName: "exclamationmark.triangle.fill",
            tint: .systemOrange
        )
    }
}()

final class IndicatorDelegate: NSObject, NSApplicationDelegate {
    private var window: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 280, height: 140)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 26
        effectView.layer?.masksToBounds = true

        let iconView = NSImageView(frame: NSRect(x: 112, y: 78, width: 56, height: 56))
        if let image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: style.title) {
            let config = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.contentTintColor = style.tint
        }

        let titleField = NSTextField(labelWithString: style.title)
        titleField.frame = NSRect(x: 20, y: 44, width: 240, height: 24)
        titleField.alignment = .center
        titleField.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleField.textColor = .labelColor

        let subtitleField = NSTextField(labelWithString: style.subtitle)
        subtitleField.frame = NSRect(x: 20, y: 22, width: 240, height: 18)
        subtitleField.alignment = .center
        subtitleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitleField.textColor = .secondaryLabelColor

        effectView.addSubview(iconView)
        effectView.addSubview(titleField)
        effectView.addSubview(subtitleField)
        panel.contentView = effectView
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        self.window = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: {
                NSApp.terminate(nil)
            })
        }
    }
}

let app = NSApplication.shared
let delegate = IndicatorDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
