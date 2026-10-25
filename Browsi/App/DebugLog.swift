import Foundation

#if DEBUG
/// Appends a line to <container>/tmp/browsi-debug.log (manual QA aid; debug builds only).
nonisolated func debugLog(_ message: @autoclosure () -> String) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "browsi-debug.log")
    let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message())\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}
#else
@inline(__always) nonisolated func debugLog(_ message: @autoclosure () -> String) {}
#endif
