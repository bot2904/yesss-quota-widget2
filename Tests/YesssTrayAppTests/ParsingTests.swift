import XCTest
@testable import YesssTrayApp

final class ParsingTests: XCTestCase {
    func testHtmlTextExtractorRemovesMarkupAndDecodesEntities() {
        let html = """
        <html><head><style>.hidden{}</style><script>alert(1)</script></head>
        <body><div>Datenvolumen&nbsp;Österreich<br>Verf&uuml;gbar: 8,25 GB</div></body></html>
        """

        XCTAssertEqual(
            HtmlTextExtractor.textLines(from: html),
            ["Datenvolumen Österreich", "Verfügbar: 8,25 GB"]
        )
    }

    func testProgressQuotaExtractionParsesGermanNumbersAndBytes() {
        let lines = [
            "Datenvolumen Österreich",
            "Verfügbar: 8,25 GB",
            "Verbraucht: 1,75 GB (von 10 GB)",
        ]

        let quotas = QuotaParser.extractProgressQuotas(lines: lines)

        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(quotas[0].title, "Datenvolumen Österreich")
        XCTAssertEqual(quotas[0].category, "data")
        XCTAssertEqual(quotas[0].remainingHuman, "8.25 GB")
        XCTAssertEqual(quotas[0].totalHuman, "10.0 GB")
        XCTAssertEqual(quotas[0].percentUsed, 17.5)
    }

    func testEUQuotaExtraction() {
        let lines = ["Datenvolumen EU verbleibend: 3,5 GB von 5 GB"]

        let quotas = QuotaParser.extractEUDataQuota(lines: lines, existingCount: 1)

        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(quotas[0].id, "datenvolumen-eu-2")
        XCTAssertEqual(quotas[0].category, "eu_data")
        XCTAssertEqual(quotas[0].remainingHuman, "3.5 GB")
        XCTAssertEqual(quotas[0].percentUsed, 30)
    }

    func testBuildSnapshotAttachesValidityAndSelectsPrimaryNonEUData() {
        let html = """
        <section>
          <h2>Datenvolumen Österreich</h2>
          <p>Verfügbar: 8 GB</p>
          <p>Verbraucht: 2 GB (von 10 GB)</p>
          <p>gültig bis: 25.04.2026 23:59</p>
        </section>
        <p>Datenvolumen EU verbleibend: 3 GB von 5 GB</p>
        """
        let fetch = YesssFetchResult(
            authState: .authenticated,
            fetchedAt: "2026-04-10T12:00:00Z",
            expertHtml: html,
            account: .empty,
            fallbackQuota: nil,
            warnings: [],
            error: nil,
            diagnostics: YesssDiagnostics()
        )

        let snapshot = QuotaParser.buildSnapshot(fetch: fetch)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.count, 2)
        XCTAssertEqual(snapshot.primaryQuota?.title, "Datenvolumen Österreich")
        XCTAssertEqual(snapshot.menuTitle, "8.0 GB")
        XCTAssertNotNil(snapshot.primaryQuota?.validUntil)
        XCTAssertNotNil(snapshot.primaryQuota?.resetAt)
    }

    func testSubscriberParserExtractsOptionsAndCurrentLabel() {
        let html = """
        <div>Admin</div><div>+43 681 12345678</div>
        <a href="kundendaten.php?subscriber=1001">Main line</a>
        <a href="kundendaten.php?subscriber=1002">Backup&nbsp;line</a>
        """

        let result = SubscriberParser.parse(html: html)

        XCTAssertEqual(result.currentLabel, "Admin +43 681 12345678")
        XCTAssertEqual(result.subscribers.map(\.id), ["1001", "1002"])
        XCTAssertEqual(result.subscribers.map(\.label), ["Main line", "Backup line"])
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testSnapshotDateParserAcceptsFractionalAndPlainISO8601() {
        XCTAssertNotNil(SnapshotDateParser.parse("2026-04-10T12:00:00Z"))
        XCTAssertNotNil(SnapshotDateParser.parse("2026-04-10T12:00:00.123Z"))
        XCTAssertNil(SnapshotDateParser.parse(nil))
    }
}
