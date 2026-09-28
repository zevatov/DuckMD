import XCTest
@testable import DuckMD

final class LineIndexCacheTests: XCTestCase {

    func testSingleLine() {
        let cache = LineIndexCache()
        cache.update(text: "Hello World")
        
        XCTAssertEqual(cache.lineStarts, [0])
        XCTAssertEqual(cache.line(for: 0), 1)
        XCTAssertEqual(cache.line(for: 5), 1)
        XCTAssertEqual(cache.line(for: 11), 1)
        XCTAssertEqual(cache.characterIndex(for: 1), 0)
        XCTAssertEqual(cache.characterIndex(for: 2), 0)
    }

    func testMultipleLines() {
        let cache = LineIndexCache()
        // Lines:
        // 1: "abc\n" (indices 0..3, start 0)
        // 2: "defgh\n" (indices 4..9, start 4)
        // 3: "ij" (indices 10..11, start 10)
        let text = "abc\ndefgh\nij"
        cache.update(text: text)

        XCTAssertEqual(cache.lineStarts, [0, 4, 10])
        XCTAssertEqual(cache.line(for: 0), 1)
        XCTAssertEqual(cache.line(for: 3), 1)
        XCTAssertEqual(cache.line(for: 4), 2)
        XCTAssertEqual(cache.line(for: 9), 2)
        XCTAssertEqual(cache.line(for: 10), 3)
        XCTAssertEqual(cache.line(for: 11), 3)

        XCTAssertEqual(cache.characterIndex(for: 1), 0)
        XCTAssertEqual(cache.characterIndex(for: 2), 4)
        XCTAssertEqual(cache.characterIndex(for: 3), 10)
    }

    func testTrailingNewlineCreatesEmptyLine() {
        let cache = LineIndexCache()
        cache.update(text: "line1\n")
        XCTAssertEqual(cache.lineStarts, [0, 6])
        XCTAssertEqual(cache.line(for: 6), 2)
        XCTAssertEqual(cache.characterIndex(for: 2), 6)
    }

    func testEmptyString() {
        let cache = LineIndexCache()
        cache.update(text: "")
        XCTAssertEqual(cache.lineStarts, [0])
        XCTAssertEqual(cache.line(for: 0), 1)
        XCTAssertEqual(cache.characterIndex(for: 1), 0)
    }
}
