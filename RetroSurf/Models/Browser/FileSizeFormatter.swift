import Foundation

/// Shared byte-sized formatting for the file archive. Used both by the
/// files.su pages and the browser's download status bar so both agree.
enum FileSizeFormatter {
    /// "85 КБ", "1.2 МБ", "3.8 МБ"
    static func format(_ bytes: Int) -> String {
        let value = max(bytes, 0)
        let mebibytes = Double(value) / (1024 * 1024)
        if mebibytes >= 1 {
            return "\(dotTenths(mebibytes)) МБ"
        }
        let kibibytes = Double(value) / 1024
        return "\(Int(kibibytes.rounded())) КБ"
    }

    /// "Загрузка: 45% (123 КБ из 275 КБ)"
    static func progress(_ sent: Int, _ total: Int) -> String {
        let clampedSent = max(0, sent)
        let percent = total > 0
            ? Int((Double(clampedSent) / Double(total)) * 100)
            : 0
        return "Загрузка: \(min(percent, 100))% (\(format(clampedSent)) из \(format(total)))"
    }

    private static func dotTenths(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded).replacingOccurrences(of: ",", with: ".")
    }
}