//
//  ConvertifyDiagnostics.swift
//  Convertify
//
//  Lightweight runtime logging controls (CLI + UI debugging)
//

import Foundation

enum ConvertifyDiagnostics {
    /// Enables extra internal logging (command building, config parsing, pipeline setup).
    static var enabled: Bool = false

    static func log(_ message: String) {
        guard enabled else { return }
        debugLog("[Diag] \(message)")
    }
}

