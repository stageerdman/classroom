#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class TimenoteFormatTests: XCTestCase {
    func testFormatTimestampProducesZeroPaddedHoursMinutesSecondsMilliseconds() {
        XCTAssertEqual(TimenoteFormat.formatTimestamp(0), "00:00:00.000")
        XCTAssertEqual(TimenoteFormat.formatTimestamp(65.25), "00:01:05.250")
        XCTAssertEqual(TimenoteFormat.formatTimestamp(3661.5), "01:01:01.500")
    }

    func testFormatTimestampClampsNegativeToZero() {
        XCTAssertEqual(TimenoteFormat.formatTimestamp(-5), "00:00:00.000")
    }

    func testParseTimestampRoundTripsWithFormat() {
        for seconds in [0.0, 1.005, 65.25, 3661.5, 7199.999] {
            let timestamp = TimenoteFormat.formatTimestamp(seconds)
            let parsed = TimenoteFormat.parseTimestamp(timestamp)
            XCTAssertNotNil(parsed)
            XCTAssertEqual(parsed!, seconds, accuracy: 0.001)
        }
    }

    func testParseTimestampRejectsMalformedInput() {
        XCTAssertNil(TimenoteFormat.parseTimestamp("not a timestamp"))
        XCTAssertNil(TimenoteFormat.parseTimestamp("00:00"))
        XCTAssertNil(TimenoteFormat.parseTimestamp("00:00:00"))
    }

    func testLinePrefixAndParseLineRoundTrip() {
        let line = TimenoteFormat.linePrefix(timestampSeconds: 125.5) + "Key insight here"
        let parsed = TimenoteFormat.parseLine(line)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.timestampSeconds ?? -1, 125.5, accuracy: 0.001)
        XCTAssertEqual(parsed?.text, "Key insight here")
    }

    func testParseLineRejectsNonTimenoteLines() {
        XCTAssertNil(TimenoteFormat.parseLine("Just a regular note."))
        XCTAssertNil(TimenoteFormat.parseLine("> A regular quote."))
    }

    func testMigratingLegacySyntaxRewritesOldTimenoteLines() {
        let legacy = "Intro\n> [!timenote 00:02:05.500] Key insight here\nOutro"
        let migrated = TimenoteFormat.migratingLegacySyntax(in: legacy)

        let lines = migrated.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Intro")
        XCTAssertEqual(lines[2], "Outro")

        let parsed = TimenoteFormat.parseLine(lines[1])
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.timestampSeconds ?? -1, 125.5, accuracy: 0.001)
        XCTAssertEqual(parsed?.text, "Key insight here")
    }

    func testMigratingLegacySyntaxIsIdempotentOnCurrentSyntax() {
        let current = TimenoteFormat.linePrefix(timestampSeconds: 42) + "Already current"
        XCTAssertEqual(TimenoteFormat.migratingLegacySyntax(in: current), current)
    }

    func testMigratingLegacySyntaxLeavesUnrelatedTextUnchanged() {
        let text = "Just a regular note.\n> A regular quote."
        XCTAssertEqual(TimenoteFormat.migratingLegacySyntax(in: text), text)
    }

    func testInlineTimeRefIsParseableAndShowsBracketedPill() {
        let ref = TimenoteFormat.inlineTimeRef(seconds: 65)
        XCTAssertTrue(ref.hasPrefix("@timeref(at: "))
        XCTAssertTrue(ref.hasSuffix("{[01:05]}"))
    }

    func testTrailingBracketTimestampDetection() {
        let text = "See this point [29:43]"
        let hit = TimenoteFormat.trailingBracketTimestamp(in: text, endingAt: (text as NSString).length)
        XCTAssertEqual(hit?.seconds, Double(29 * 60 + 43))
        XCTAssertEqual((text as NSString).substring(with: hit!.range), "[29:43]")

        XCTAssertEqual(TimenoteFormat.trailingBracketTimestamp(in: "[1:02:03]", endingAt: 9)?.seconds, Double(3723))
        XCTAssertNil(TimenoteFormat.trailingBracketTimestamp(in: "[not a time]", endingAt: 12))
        XCTAssertNil(TimenoteFormat.trailingBracketTimestamp(in: "mid [29:43] text", endingAt: 16), "Only a trailing token converts")
    }

    func testBracketedTimestampFormats() {
        XCTAssertEqual(TimenoteFormat.bracketedTimestamp(0), "[00:00]")
        XCTAssertEqual(TimenoteFormat.bracketedTimestamp(65.25), "[01:05]")
        XCTAssertEqual(TimenoteFormat.bracketedTimestamp(3661), "[01:01:01]")
        XCTAssertEqual(TimenoteFormat.bracketedTimestamp(65, forcingHours: true), "[00:01:05]")
    }

    func testLinePrefixUsesBracketedPill() {
        // The visible pill (directive body) is the bracketed timestamp.
        XCTAssertTrue(TimenoteFormat.linePrefix(timestampSeconds: 65.25).contains("{[01:05]}"))
    }

    func testMigratingUpgradesOldMillisecondPillToBracketedPill() {
        // A current-syntax directive saved with the old HH:MM:SS.mmm body.
        let old = "> @timenote(at: 65.250){00:01:05.250} Key insight"
        let migrated = TimenoteFormat.migratingLegacySyntax(in: old)

        XCTAssertTrue(migrated.contains("{[01:05]}"), "Old millisecond pill should become the bracketed pill")
        XCTAssertFalse(migrated.contains("00:01:05.250"))
        let parsed = TimenoteFormat.parseLine(migrated)
        XCTAssertEqual(parsed?.timestampSeconds ?? -1, 65.25, accuracy: 0.001)
        XCTAssertEqual(parsed?.text, "Key insight")
        // And running it again changes nothing.
        XCTAssertEqual(TimenoteFormat.migratingLegacySyntax(in: migrated), migrated)
    }
}
#endif
