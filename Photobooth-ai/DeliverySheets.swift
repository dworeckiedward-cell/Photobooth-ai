import SwiftUI
import UIKit

// Extracted in Phase 1 (blueprint 4.A) from ResultView.swift before the AI
// result screen was cut — the 360 hub and settings sheets share this bridge.

/// UIKit share-sheet bridge (AirDrop, Messages, Mail, WhatsApp, …).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
