import SwiftUI
import UIKit

/// Exports collected guest survey data as a CSV the operator can share (Mail,
/// Files, AirDrop, Numbers…). A real lead-capture/export feature — a business
/// reason operators pay for booth software.
enum CSVExporter {
    static func surveyCSV(_ responses: [SurveyResponse], question: String) -> String {
        let header = ["submitted_at", "question", "answer_type", "rating", "yes_no", "text", "photo_id"]
        let iso = ISO8601DateFormatter()
        var rows = [header.joined(separator: ",")]
        for r in responses {
            let answer: String
            switch r.answerType {
            case .rating: answer = r.rating.map(String.init) ?? ""
            case .yesNo:  answer = r.yesNo.map { $0 ? "yes" : "no" } ?? ""
            case .text:   answer = ""
            }
            let cols = [
                iso.string(from: r.submittedAt),
                question,
                r.answerType.rawValue,
                r.answerType == .rating ? answer : "",
                r.answerType == .yesNo ? answer : "",
                r.text ?? "",
                r.photoId?.uuidString ?? "",
            ]
            rows.append(cols.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// Write CSV to a temp file and return the URL for sharing.
    static func writeTemp(_ csv: String, name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// RFC-4180 field escaping.
    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

/// Minimal UIActivityViewController bridge for sharing files (CSV, etc.).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
