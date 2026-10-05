import SwiftUI
import VisionKit

/// 端末カメラで名刺をスキャンする(VisionKit のドキュメントスキャナ)。
/// カメラが必要なため実機専用。シミュレータでは利用不可(PhotoPicker を使う)。
struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanned: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanned: (UIImage) -> Void
        let onCancel: () -> Void

        init(onScanned: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScanned = onScanned
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // 先頭ページのみ扱う(裏面対応は Phase 1.5)。
            if scan.pageCount > 0 {
                onScanned(scan.imageOfPage(at: 0))
            } else {
                onCancel()
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}
