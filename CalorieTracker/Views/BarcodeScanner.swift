import SwiftUI
import VisionKit

struct BarcodeScanner: View {
    let onScan: (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            LiveBarcodeScanner(onScan: onScan)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 250, height: 120)
                }
        } else {
            ContentUnavailableView(
                "Scanner unavailable",
                systemImage: "barcode.viewfinder",
                description: Text("Use manual barcode entry below on this device.")
            )
            .background(Color.black.opacity(0.05))
        }
    }
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var lastCode: String?

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let code = barcode.payloadStringValue,
                      code != lastCode else { continue }
                lastCode = code
                onScan(code)
                break
            }
        }
    }
}

