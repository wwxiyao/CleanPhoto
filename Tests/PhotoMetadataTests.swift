import Testing
@testable import CleanPhotoLogic

@MainActor
struct PhotoMetadataTests {
    @Test func locationIsDirectlyBelowDate() {
        let metadata = PhotoMetadata(dateText: "2026-10-26", locationText: "杭州市 · 西湖区", deviceText: "iPhone")
        #expect(metadata.lines == ["日期: 2026-10-26", "位置: 杭州市 · 西湖区", "设备: iPhone"])
    }

    @Test func missingLocationIsExplainedInsteadOfHidden() {
        let metadata = PhotoMetadata(dateText: "2026-10-26", locationText: nil, deviceText: nil)
        #expect(metadata.lines == ["日期: 2026-10-26", "位置: 未记录位置"])
    }

    @Test func missingDateStillKeepsLocationInSecondRow() {
        let metadata = PhotoMetadata(dateText: nil, locationText: "上海市", deviceText: nil)
        #expect(metadata.lines == ["日期: 未记录日期", "位置: 上海市"])
    }
}
