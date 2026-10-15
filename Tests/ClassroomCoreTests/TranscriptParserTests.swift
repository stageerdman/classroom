#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class TranscriptParserTests: XCTestCase {
    func testParsesSpeakerTimestampAndText() {
        let cues = TranscriptParser.parse("""
        **Obchodník** [00:30]
        Radku, zdravím vás!

        **Obchodník** [00:37]
        Bespolu po týdnu.
        """)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].id, 0)
        XCTAssertEqual(cues[0].speaker, "Obchodník")
        XCTAssertEqual(cues[0].startSeconds, 30, accuracy: 0.0001)
        XCTAssertNil(cues[0].parenthetical)
        XCTAssertEqual(cues[0].text, "Radku, zdravím vás!")
        XCTAssertEqual(cues[1].startSeconds, 37, accuracy: 0.0001)
        XCTAssertEqual(cues[1].text, "Bespolu po týdnu.")
    }

    func testEndSecondsChainToNextStartAndLastIsInfinite() {
        let cues = TranscriptParser.parse("""
        **A** [00:10]
        one
        **A** [00:25]
        two
        """)

        XCTAssertEqual(cues[0].endSeconds, 25, accuracy: 0.0001)
        XCTAssertEqual(cues[1].endSeconds, .infinity)
    }

    func testParsesParentheticalAnnotation() {
        let cues = TranscriptParser.parse("""
        **Klient** [09:51] (interrupting)
        Uhu.
        """)

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].speaker, "Klient")
        XCTAssertEqual(cues[0].startSeconds, 9 * 60 + 51, accuracy: 0.0001)
        XCTAssertEqual(cues[0].parenthetical, "(interrupting)")
        XCTAssertEqual(cues[0].text, "Uhu.")
    }

    func testParsesLongMultiSentenceBodyAndInlineBrackets() {
        let cues = TranscriptParser.parse("""
        **Obchodník** [10:03]
        Ale říkám si, jakožto je tříměsíční program a tam je potřeba do toho dávat intenzivněji ten čas každý den a máte tam i to, že tam jsou konzultace, kde se scházíte s tím nějakým coachem.

        **Klient** [10:03] (interrupting)
        [nesrozumitelné]
        """)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startSeconds, 10 * 60 + 3, accuracy: 0.0001)
        XCTAssertTrue(cues[0].text.hasPrefix("Ale říkám si"))
        // Two cues can legitimately share a start (overlapping speech).
        XCTAssertEqual(cues[1].startSeconds, 10 * 60 + 3, accuracy: 0.0001)
        XCTAssertEqual(cues[1].parenthetical, "(interrupting)")
        XCTAssertEqual(cues[1].text, "[nesrozumitelné]")
    }

    func testMultiParagraphBodyKeepsInteriorBlankLine() {
        let cues = TranscriptParser.parse("""
        **A** [00:00]
        First paragraph.

        Second paragraph.
        """)

        XCTAssertEqual(cues[0].text, "First paragraph.\n\nSecond paragraph.")
    }

    func testTimestampFormats() {
        XCTAssertEqual(TranscriptParser.parseTimestampSeconds("00:30"), 30)
        XCTAssertEqual(TranscriptParser.parseTimestampSeconds("9:51"), 9 * 60 + 51)
        XCTAssertEqual(TranscriptParser.parseTimestampSeconds("1:02:03"), 3600 + 2 * 60 + 3)
        XCTAssertEqual(TranscriptParser.parseTimestampSeconds("01:02:03"), 3600 + 2 * 60 + 3)
        XCTAssertEqual(TranscriptParser.parseTimestampSeconds("00:00:04.500"), 4.5)
        XCTAssertNil(TranscriptParser.parseTimestampSeconds("nope"))
        XCTAssertNil(TranscriptParser.parseTimestampSeconds("12"))
    }

    func testPreambleBeforeFirstHeaderIsIgnored() {
        let cues = TranscriptParser.parse("""
        Some intro note without a timestamp.

        **A** [00:05]
        real content
        """)

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "real content")
    }

    func testHeaderWithUnparseableTimestampIsTreatedAsBodyNotDropped() {
        // A bold line that isn't a real header shouldn't start a cue, and its
        // text must survive as part of the current cue.
        let cues = TranscriptParser.parse("""
        **A** [00:05]
        line one
        **Note to self** not a timestamp
        line two
        """)

        XCTAssertEqual(cues.count, 1)
        XCTAssertTrue(cues[0].text.contains("line one"))
        XCTAssertTrue(cues[0].text.contains("not a timestamp"))
        XCTAssertTrue(cues[0].text.contains("line two"))
    }

    func testEmptyAndWhitespaceInputProduceNoCues() {
        XCTAssertTrue(TranscriptParser.parse("").isEmpty)
        XCTAssertTrue(TranscriptParser.parse("\n\n   \n").isEmpty)
    }

    func testActiveCueLookup() {
        let cues = TranscriptParser.parse("""
        **A** [00:10]
        one
        **B** [00:20]
        two
        **A** [00:30]
        three
        """)

        XCTAssertNil(cues.activeCueID(at: 5), "Before the first cue there is no active cue.")
        XCTAssertEqual(cues.activeCueID(at: 10), 0)
        XCTAssertEqual(cues.activeCueID(at: 15), 0)
        XCTAssertEqual(cues.activeCueID(at: 20), 1)
        XCTAssertEqual(cues.activeCueID(at: 29.9), 1)
        XCTAssertEqual(cues.activeCueID(at: 30), 2)
        XCTAssertEqual(cues.activeCueID(at: 9999), 2, "Past the end, the last cue stays active.")
    }

    func testActiveCueLookupEmpty() {
        XCTAssertNil([TranscriptCue]().activeCueID(at: 0))
    }
}
#endif
