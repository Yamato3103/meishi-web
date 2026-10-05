import SwiftUI
import PhotosUI
import VisionKit
import MeishiKit

/// アプリのトップ。名刺一覧 + 取り込み導線(写真から / カメラスキャン)。
struct RootView: View {
    @Environment(AppModel.self) private var model

    @AppStorage("meishivault.onboarded") private var onboarded = false

    @State private var pickerItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var pendingImport: PendingImport?
    @State private var searchText = ""
    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var showOnboarding = false

    #if DEBUG
    @State private var demoDuplicate: DemoDuplicate?
    @State private var demoAddContact: Card?
    @State private var demoTagCard: Card?
    @State private var demoTipJar = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            CardListView(query: searchText)
                .navigationTitle("MeishiVault")
                .searchable(text: $searchText, prompt: "氏名・会社・メールなど")
                .navigationDestination(for: Card.self) { card in
                    CardDetailView(cardId: card.id)
                }
                .onAppear {
                    if !onboarded { showOnboarding = true }
                    runDemoHooksIfNeeded()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "photo.on.rectangle")
                        }
                        .accessibilityLabel("写真から取り込む")
                    }
                    if VNDocumentCameraViewController.isSupported {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showScanner = true
                            } label: {
                                Image(systemName: "camera")
                            }
                            .accessibilityLabel("カメラでスキャン")
                        }
                    }
                    if !model.cards.isEmpty, let allURL = VCardExporter.temporaryFile(for: model.cards) {
                        ToolbarItem(placement: .topBarLeading) {
                            ShareLink(item: allURL) {
                                Label("すべて共有", systemImage: "square.and.arrow.up.on.square")
                            }
                            .accessibilityLabel("すべてvCardで共有")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("設定")
                    }
                }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedImage(newItem) }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                onboarded = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScanned: { image in
                    showScanner = false
                    presentConfirm(for: image)
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $pendingImport) { pending in
            CaptureConfirmView(processed: pending.processed, draft: pending.draft)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #if DEBUG
        .sheet(item: $demoDuplicate) { demo in
            DuplicateResolutionView(
                matches: demo.matches,
                onMerge: { _ in demoDuplicate = nil },
                onRegisterAsNew: { demoDuplicate = nil },
                onCancel: { demoDuplicate = nil }
            )
        }
        .sheet(item: $demoAddContact) { card in
            AddToContactsView(
                card: card,
                imageData: model.frontImage(for: card)?.jpegData(compressionQuality: 0.8),
                onFinish: { demoAddContact = nil }
            )
        }
        .sheet(item: $demoTagCard) { card in
            TagEditorView(card: card)
        }
        .sheet(isPresented: $demoTipJar) {
            NavigationStack { TipJarView() }
        }
        #endif
    }

    private func loadPickedImage(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else { return }
        presentConfirm(for: image)
    }

    private func presentConfirm(for image: UIImage) {
        let processed = ImagePipeline.process(image)
        // OCR → フィールド抽出 → 確認画面の初期値(ドラフト)を作る。
        let extraction = VisionTextRecognizer.extract(from: processed.image)
        let draft = Card.draft(from: extraction)
        pendingImport = PendingImport(processed: processed, draft: draft)
    }

    // MARK: - 検証用フック(Release ビルドには含めない)

    private func runDemoHooksIfNeeded() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo-open-first"), path.isEmpty, let first = model.cards.first {
            path.append(first)
        }
        if args.contains("--demo-duplicate"), demoDuplicate == nil, let first = model.cards.first {
            var draft = first
            draft.id = UUID().uuidString
            let matches = model.findDuplicates(of: draft)
            if !matches.isEmpty { demoDuplicate = DemoDuplicate(matches: matches) }
        }
        if args.contains("--demo-add-contact"), demoAddContact == nil, let first = model.cards.first {
            demoAddContact = first
        }
        if args.contains("--demo-settings"), !showSettings {
            showSettings = true
        }
        if args.contains("--demo-tags"), demoTagCard == nil, let first = model.cards.first {
            demoTagCard = first
        }
        if args.contains("--demo-tipjar"), !demoTipJar {
            demoTipJar = true
        }
        #endif
    }
}

#if DEBUG
/// 検証用: 重複解決画面を提示するための Identifiable ラッパ。
struct DemoDuplicate: Identifiable {
    let id = UUID()
    let matches: [DuplicateMatch]
}
#endif

/// sheet(item:) 用に Processed とドラフトを Identifiable で包む。
struct PendingImport: Identifiable {
    let id = UUID()
    let processed: ImagePipeline.Processed
    let draft: Card
}
