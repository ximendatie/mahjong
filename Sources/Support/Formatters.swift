import Foundation

enum Formatters {
    static func tokens(_ value: Int) -> String {
        let units: [(threshold: Int, suffix: String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "k")
        ]

        for unit in units where value >= unit.threshold {
            let abbreviated = Double(value) / Double(unit.threshold)
            return String(format: "%.1f%@", abbreviated, unit.suffix)
        }

        return "\(value)"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
