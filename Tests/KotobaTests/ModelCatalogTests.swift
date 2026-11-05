import XCTest
import PLaMoKit

final class ModelCatalogTests: XCTestCase {
    func testCatalogContainsTheThreePublishedQuantizations() {
        XCTAssertEqual(ModelCatalog.variants.map(\.quantization), ["Q2_K", "Q3_K_M", "Q4_K_M"])
        XCTAssertEqual(ModelCatalog.recommended.quantization, "Q3_K_M")
        XCTAssertEqual(ModelCatalog.recommended.approximateBytes, 486_000_000)
    }

    func testDownloadURLsPointAtTheHuggingFaceRepository() {
        for variant in ModelCatalog.variants {
            XCTAssertEqual(variant.downloadURL.host, "huggingface.co")
            XCTAssertEqual(variant.downloadURL.lastPathComponent, variant.fileName)
            XCTAssertTrue(variant.downloadURL.path.contains(ModelCatalog.repository))
            XCTAssertTrue(variant.fileName.hasSuffix(".gguf"))
        }
    }

    func testSizesIncreaseWithQuantizationQuality() {
        let sizes = ModelCatalog.variants.map(\.approximateBytes)
        XCTAssertEqual(sizes, sizes.sorted())
    }
}
