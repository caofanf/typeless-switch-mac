import Foundation
import XCTest
@testable import TypelessToolkit

final class JSONLineTransportTests: XCTestCase {
    func testDecoderHandlesSplitAndMultipleFrames() throws {
        var decoder = JSONLineDecoder(maxFrameBytes: 8 * 1024 * 1024)

        XCTAssertEqual(try decoder.append(Data(#"{"id":"1""#.utf8)).count, 0)
        let frames = try decoder.append(Data("}\n{\"id\":\"2\"}\n".utf8))

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(String(decoding: frames[0], as: UTF8.self), #"{"id":"1"}"#)
        XCTAssertEqual(String(decoding: frames[1], as: UTF8.self), #"{"id":"2"}"#)
    }

    func testDecoderIgnoresBlankLinesAndAcceptsCRLF() throws {
        var decoder = JSONLineDecoder(maxFrameBytes: 64)

        let frames = try decoder.append(Data("\n{\"ok\":true}\r\n\n".utf8))

        XCTAssertEqual(frames, [Data(#"{"ok":true}"#.utf8)])
    }

    func testDecoderRejectsOversizedUnterminatedFrame() throws {
        var decoder = JSONLineDecoder(maxFrameBytes: 4)

        XCTAssertThrowsError(try decoder.append(Data("12345".utf8))) { error in
            XCTAssertEqual(error as? JSONLineDecoderError, .frameTooLarge(maxBytes: 4))
        }
    }
}
