//
//  ExecutableLocator.swift
//  Convertify
//
//  Resolves command-line tool paths reliably (Homebrew paths + PATH via `which`)
//

import Foundation

enum ExecutableLocator {
    static func resolveExecutableURL(
        named name: String,
        preferredAbsolutePaths: [String]
    ) -> URL? {
        for path in preferredAbsolutePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Fall back to PATH (best-effort; Finder-launched apps may have a minimal PATH).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty,
              FileManager.default.isExecutableFile(atPath: output)
        else {
            return nil
        }

        return URL(fileURLWithPath: output)
    }
}


