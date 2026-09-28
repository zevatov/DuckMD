import Foundation

/// Быстрый кэш переносов строк: бинарный поиск строки за O(log K) и поиск смещения за O(1)
final class LineIndexCache {
    private(set) var lineStarts: [Int] = [0]
    private var lastLength: Int = -1

    func update(text: String) {
        let ns = text as NSString
        let len = ns.length
        if len == lastLength && !lineStarts.isEmpty { return }
        lastLength = len
        var starts: [Int] = [0]
        for i in 0..<len {
            if ns.character(at: i) == 10 { // \n
                starts.append(i + 1)
            }
        }
        lineStarts = starts
    }

    func line(for charIndex: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        var result = 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= charIndex {
                result = mid + 1
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func characterIndex(for line: Int) -> Int {
        let idx = line - 1
        if idx <= 0 { return 0 }
        if idx < lineStarts.count { return lineStarts[idx] }
        return lineStarts.last ?? 0
    }
}
