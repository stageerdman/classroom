#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class PageQuoteFormatTests: XCTestCase {
    func testEncodeDecodeRoundTripsArbitraryText() {
        let quote = "Quote with \"quotes\", commas, braces {} and\na newline."
        let encoded = PageQuoteFormat.encode(quote)
        // Base64 alphabet only — nothing that could break directive syntax.
        XCTAssertFalse(encoded.contains("\""))
        XCTAssertFalse(encoded.contains("}"))
        XCTAssertFalse(encoded.contains(","))
        XCTAssertEqual(PageQuoteFormat.decode(encoded), quote)
    }

    func testLinePrefixIsParseableDirectiveWithReadablePreview() {
        let line = PageQuoteFormat.linePrefix(quote: "The key point about pricing")
        XCTAssertTrue(line.hasPrefix("> @pagequote(ref: \""))
        XCTAssertTrue(line.contains("{“The key point about pricing”}"))
        XCTAssertTrue(line.hasSuffix("} "))
    }

    func testPreviewCollapsesWhitespaceAndTruncates() {
        let preview = PageQuoteFormat.preview(of: "  line one\n   line two   ")
        XCTAssertEqual(preview, "“line one line two”")

        let long = String(repeating: "word ", count: 50)
        XCTAssertTrue(PageQuoteFormat.preview(of: long).hasSuffix("…”"))
    }

    func testRangeOfQuoteMatchesAcrossDifferentWhitespace() {
        let page = "Intro paragraph.\n\nThe key point\nabout   pricing is value.\n\nMore."
        // Stored quote collapsed to spaces; Page has a newline + double space.
        let range = PageQuoteFormat.range(ofQuote: "The key point about pricing is value.", in: page)
        XCTAssertNotNil(range)
        let matched = (page as NSString).substring(with: range!)
        XCTAssertTrue(matched.contains("key point"))
        XCTAssertTrue(matched.contains("pricing is value"))
    }

    func testRangeOfMissingQuoteIsNil() {
        XCTAssertNil(PageQuoteFormat.range(ofQuote: "not present at all", in: "Some other text."))
    }
}
#endif
