import Foundation

/// Minimal async wrapper around Process. Runs off the main thread and returns
/// stdout as a string (stderr discarded). Never throws for non-zero exit — an
/// empty/partial result just means fewer rows, which the parser tolerates.
enum Shell {
    static func run(_ launchPath: String, _ args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
