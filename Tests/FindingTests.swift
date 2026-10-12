import Foundation
import Redact
import Testing

struct FindingTests {
    @Test func groupsSpansTheWayAPersonCountsThem() {
        let finding = Finding(
            items: [
                (.givenName, "Anna"), (.surname, "Kovács"),
                (.streetName, "Váci utca"), (.buildingNumber, "12"), (.city, "Budapest"),
                (.email, "anna@example.hu"), (.email, "info@example.hu"),
            ],
            redactedText: ""
        )
        #expect(finding.summary == "1 name, 1 address, and 2 emails")
    }

    @Test func dropsLinksAndCompanies() {
        let finding = Finding(items: [(.url, "https://example.hu"), (.org, "Odoo")], redactedText: "")
        #expect(finding.isEmpty)
    }

    @Test func catchesAnEmailInsideALink() {
        let swept = Finding.sweepEmails(
            in: "Join https://meet.google.com/home?authuser=sam@example.com or ?u=anna%40example.hu, [EMAIL_1]",
            numberingFrom: 2
        )
        #expect(swept.text == "Join https://meet.google.com/home?authuser=[EMAIL_2] or ?u=[EMAIL_3], [EMAIL_1]")
        #expect(swept.emails == ["sam@example.com", "anna@example.hu"])
    }

    @Test func neverFlagsTheUsersOwnDetails() {
        let allowlist = Allowlist(["Sam@Example.com", "+31 6 1234 5678", "Sam Taylor"])
        #expect(allowlist.allows("sam@example.com", as: .email))
        #expect(allowlist.allows("06 1234 5678", as: .phone))
        #expect(allowlist.allows("Taylor", as: .surname))
        #expect(!allowlist.allows("Anna", as: .givenName))
        #expect(!allowlist.allows("06 9999 5678", as: .phone))

        let swept = Finding.sweepEmails(
            in: "?authuser=sam%40example.com and anna@example.hu",
            numberingFrom: 1,
            allowing: allowlist
        )
        #expect(swept.text == "?authuser=sam%40example.com and [EMAIL_1]")
    }

    @Test func leavesTurnedOffKindsAlone() {
        let detection = Chunking.Detection(
            items: [
                .init(label: .givenName, original: "Anna", placeholder: "[GIVEN_NAME_1]"),
                .init(label: .city, original: "Budapest", placeholder: "[CITY_1]"),
            ],
            redactedText: "[GIVEN_NAME_1] from [CITY_1], anna@example.hu"
        )
        let finding = Finding(detection, skipping: [.address, .email])
        #expect(finding.redactedText == "[GIVEN_NAME_1] from Budapest, anna@example.hu")
        #expect(finding.summary == "1 name")
    }

    @Test func masksWithoutShowingTheValue() {
        #expect(Finding.mask("anna@example.hu") == "a•••@example.hu")
        #expect(Finding.mask("4111 1111 1111 1111") == "•••• 1111")
        #expect(Finding.mask("Kovács") == "K•••")
    }

    @Test func watchesAgentAppsButNotTerminals() {
        let file = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../App/Resources/app-watchlist.json")
        let apps = AppList.load(file) ?? []
        #expect(apps.contains("com.anthropic.claudefordesktop"))
        #expect(apps.contains("com.apple.mail"))
        #expect(!apps.contains("com.apple.Terminal"))
    }

    @Test func chunksCoverTheTextAtSentenceEnds() {
        let text = String(repeating: "Anna Kovács lives in Budapest and works at the market. ", count: 12)
        let chunks = Chunking.chunks(of: text)
        #expect(chunks.map { String(text[$0]) }.joined() == text)
        #expect(chunks.allSatisfy { text[$0].count <= Chunking.chunkLength })
        #expect(chunks.dropLast().allSatisfy { text[$0].hasSuffix(". ") })
    }

    @Test func leavesOneTimeCodesAlone() {
        let detection = Chunking.Detection(
            items: [
                .init(label: .zipCode, original: "482913", placeholder: "[ZIP_CODE_1]"),
                .init(label: .phone, original: "123 456", placeholder: "[PHONE_1]"),
                .init(label: .phone, original: "+31 6 1234 5678", placeholder: "[PHONE_2]"),
            ],
            redactedText: "Your code is [ZIP_CODE_1], or [PHONE_1], call [PHONE_2]"
        )
        let finding = Finding(detection)
        #expect(finding.redactedText == "Your code is 482913, or 123 456, call [PHONE_2]")
        #expect(finding.summary == "1 phone number")
    }
}
