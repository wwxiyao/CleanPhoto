import Foundation

nonisolated enum SimilarGroupHeading {
    static func summary(for group: SimilarGroup, timeZone: TimeZone = .current) -> String {
        "\(text(date: group.assets.first?.creationDate, timeZone: timeZone)) · 共 \(group.assets.count) 张 · 已选 \(group.assetsToDelete.count) 张"
    }

    static func text(date: Date?, timeZone: TimeZone = .current) -> String {
        let dateText: String
        if let date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            dateText = formatter.string(from: date)
        } else {
            dateText = "未记录日期"
        }
        return dateText
    }
}
