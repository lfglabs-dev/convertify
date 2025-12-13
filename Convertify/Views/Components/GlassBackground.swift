//
//  GlassBackground.swift
//  Convertify
//
//  System Liquid Glass background.
//  - Uses NSGlassEffectView when available (macOS Tahoe+).
//  - Falls back to NSVisualEffectView otherwise.
//

import SwiftUI
import AppKit

struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSView {
        // Prefer system Liquid Glass when available.
        if #available(macOS 26.0, *), let glass = makeGlassEffectView() {
            return glass
        }

        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? NSVisualEffectView {
            v.material = material
            v.blendingMode = blendingMode
            v.state = .followsWindowActiveState
        }
        // NSGlassEffectView is intentionally left system-configured.
    }

    @available(macOS 26.0, *)
    private func makeGlassEffectView() -> NSView? {
        // NSGlassEffectView is a Tahoe-era API. We avoid hard coupling to its exact initializer
        // shape by constructing it via NSClassFromString, so builds still succeed on older SDKs.
        guard let cls = NSClassFromString("NSGlassEffectView") as? NSView.Type else { return nil }
        let view = cls.init(frame: .zero)
        // Best-effort configuration via KVC (keeps source compatible if Apple changes details).
        view.setValue(true, forKey: "wantsLayer")
        return view
    }
}

