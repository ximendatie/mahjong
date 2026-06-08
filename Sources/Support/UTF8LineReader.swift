import Foundation

enum UTF8LineReader {
    static func readLines(
        from url: URL,
        chunkSize: Int = 64 * 1024,
        _ body: (Substring) -> Void
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return
        }
        defer {
            try? handle.close()
        }

        var pending = Data()
        pending.reserveCapacity(chunkSize)

        var shouldStop = false
        while !shouldStop {
            autoreleasepool {
                let chunk = handle.readData(ofLength: chunkSize)
                guard !chunk.isEmpty else {
                    if !pending.isEmpty,
                       let line = String(data: pending, encoding: .utf8) {
                        body(line[...])
                    }
                    pending.removeAll(keepingCapacity: false)
                    shouldStop = true
                    return
                }

                pending.append(chunk)
                var searchStart = pending.startIndex

                while let newline = pending[searchStart...].firstIndex(of: 0x0A) {
                    let lineData = pending[searchStart..<newline]
                    if let line = String(data: lineData, encoding: .utf8) {
                        body(line[...])
                    }
                    searchStart = pending.index(after: newline)
                }

                if searchStart > pending.startIndex {
                    pending.removeSubrange(pending.startIndex..<searchStart)
                }
            }
        }
    }
}
