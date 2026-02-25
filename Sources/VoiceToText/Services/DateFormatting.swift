import Foundation

enum DateFormatting {

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .long
        return f
    }()

    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
