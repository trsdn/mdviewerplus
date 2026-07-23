import PDFKit
import XCTest
@testable import MDViewerPlus

@MainActor
final class MarkdownPrintControllerTests: XCTestCase {
    func testPrintRendersSuppliedCurrentText() async {
        let printed = expectation(description: "PDF produced")
        var printedText = ""
        let controller = MarkdownPrintController { document in
            printedText = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
            printed.fulfill()
        }

        controller.print(
            markdown: "# Current unsaved text",
            resourceRoot: nil
        ) { error in
            XCTFail(error)
            printed.fulfill()
        }

        await fulfillment(of: [printed], timeout: 10)
        XCTAssertTrue(printedText.contains("Current unsaved text"))
    }
}
