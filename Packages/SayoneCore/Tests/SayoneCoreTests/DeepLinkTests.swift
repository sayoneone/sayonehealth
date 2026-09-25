import Foundation
import XCTest
@testable import SayoneCore

final class DeepLinkTests: XCTestCase {
    private func parse(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink(url: url)
    }

    func testScheme() {
        XCTAssertEqual(DeepLink.scheme, "sayonehealth")
    }

    func testBuildExactFormats() {
        XCTAssertEqual(DeepLink.today.url.absoluteString, "sayonehealth://today")
        XCTAssertEqual(DeepLink.healthAccess.url.absoluteString, "sayonehealth://health")
        XCTAssertEqual(DeepLink.confirmLog(drinkID: "water", volumeML: 250).url.absoluteString,
                       "sayonehealth://log?drink=water&ml=250")
        let custom = "custom-8C1E0D4A-1111-2222-3333-44445555669A"
        XCTAssertEqual(DeepLink.confirmLog(drinkID: custom, volumeML: 330).url.absoluteString,
                       "sayonehealth://log?drink=\(custom)&ml=330")
    }

    func testParse() {
        XCTAssertEqual(parse("sayonehealth://today"), .today)
        XCTAssertEqual(parse("sayonehealth://health"), .healthAccess)
        XCTAssertEqual(parse("sayonehealth://log?drink=colaZero&ml=330"), .confirmLog(drinkID: "colaZero", volumeML: 330))
        XCTAssertEqual(parse("sayonehealth://log?ml=500&drink=water"), .confirmLog(drinkID: "water", volumeML: 500))
        XCTAssertEqual(parse("sayonehealth://today/"), .today)
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(parse("SayoneHealth://today"), .today)
        XCTAssertEqual(parse("SAYONEHEALTH://Health"), .healthAccess)
        XCTAssertEqual(parse("SayoneHealth://LOG?drink=tea&ml=250"), .confirmLog(drinkID: "tea", volumeML: 250))
    }

    func testRejects() {
        XCTAssertNil(parse("https://today"))
        XCTAssertNil(parse("otherapp://today"))
        XCTAssertNil(parse("sayonehealth://settings"))
        XCTAssertNil(parse("sayonehealth:today"))
        XCTAssertNil(parse("sayonehealth://log"))
        XCTAssertNil(parse("sayonehealth://log?drink=water"))
        XCTAssertNil(parse("sayonehealth://log?ml=250"))
        XCTAssertNil(parse("sayonehealth://log?drink=&ml=250"))
        XCTAssertNil(parse("sayonehealth://log?drink=water&ml="))
        XCTAssertNil(parse("sayonehealth://log?drink=water&ml=abc"))
        XCTAssertNil(parse("sayonehealth://log?drink=water&ml=2.5"))
        XCTAssertNil(parse("sayonehealth://log?drink=water&ml=99999999999999999999999"))
    }

    func testRoundTrips() {
        let links: [DeepLink] = [
            .today,
            .healthAccess,
            .confirmLog(drinkID: "water", volumeML: 250),
            .confirmLog(drinkID: "custom-8C1E0D4A-1111-2222-3333-44445555669A", volumeML: 5000),
            .confirmLog(drinkID: "odd id&x=1+2/ё", volumeML: 10)
        ]
        for link in links {
            XCTAssertEqual(DeepLink(url: link.url), link, link.url.absoluteString)
        }
    }
}
