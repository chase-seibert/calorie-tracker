import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct MealPhotoAnalysisView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let targetDate: Date
    let onLogged: () -> Void
    private let analysisClient: any MealAnalysisClient
    private let credentialStore: any OpenAICredentialStoring

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sourceImage: Data?
    @State private var context = ""
    @State private var analysisTask: Task<Void, Never>?
    @State private var requestGeneration = UUID()
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var reviewingFile: CustomMealFile?
    @State private var showingCamera = false
    @State private var showingCameraUnavailable = false
    @State private var cameraError: String?

    init(
        targetDate: Date,
        onLogged: @escaping () -> Void,
        analysisClient: any MealAnalysisClient = OpenAIMealAnalysisClient(),
        credentialStore: any OpenAICredentialStoring = OpenAICredentialStore.shared
    ) {
        self.targetDate = targetDate
        self.onLogged = onLogged
        self.analysisClient = analysisClient
        self.credentialStore = credentialStore
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let sourceImage, let image = UIImage(data: sourceImage) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Selected meal photo")
                    } else {
                        ContentUnavailableView("Choose a meal photo", systemImage: "fork.knife", description: Text("Take a photo or select one from your library."))
                            .frame(maxWidth: .infinity)
                    }
                    HStack {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose Photo", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            Task { await prepareCamera() }
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let cameraError { Text(cameraError).font(.caption).foregroundStyle(.red) }
                    Text("Before you analyze, the photo and context shown here will be sent to OpenAI. The estimate is not a measured nutrition result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: { Text("Photo") }

                Section("Meal context (optional)") {
                    TextField("Portion, ingredients, or preparation", text: $context, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: context) { _, value in
                            if value.count > MealAnalysisRequest.maximumContextCharacters {
                                context = String(value.prefix(MealAnalysisRequest.maximumContextCharacters))
                            }
                        }
                    Text("\(context.count)/\(MealAnalysisRequest.maximumContextCharacters)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section {
                    if isAnalyzing {
                        ProgressView("Analyzing meal photo…")
                        Text("This sends one request to OpenAI. Cancel stops waiting here, but it may not stop provider processing or charges.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Cancel Analysis", role: .cancel, action: cancelAnalysis)
                    } else {
                        Button {
                            startAnalysis()
                        } label: {
                            Label("Analyze Photo", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sourceImage == nil)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.callout).foregroundStyle(.red)
                        if sourceImage != nil && !isAnalyzing {
                            Button("Retry Analysis") { startAnalysis() }
                        }
                    }
                } footer: {
                    Text("Each retry sends a new API request and may incur usage charges. Analysis alone does not save anything to your diary or Apple Health.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Analyze Meal Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { cancelAnalysis(); dismiss() }
                }
            }
            .sheet(isPresented: $showingCamera) {
                MealCameraPicker { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else {
                        cameraError = MealAnalysisError.invalidImage.localizedDescription
                        return
                    }
                    sourceImage = data
                    errorMessage = nil
                }
            }
            .alert("Camera unavailable", isPresented: $showingCameraUnavailable) {
                Button("OK", role: .cancel) { }
            } message: { Text(cameraError ?? "Allow camera access in Settings or select a photo instead.") }
            .sheet(item: Binding(get: { reviewingFile.map(ReviewingMeal.init) }, set: { reviewingFile = $0?.file })) { item in
                CustomMealImportView(file: item.file, targetDate: targetDate, source: .openAIPhoto, onLogged: {
                    reviewingFile = nil
                    onLogged()
                })
                .environmentObject(diary)
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                        throw MealAnalysisError.invalidImage
                    }
                    guard data.count <= MealPhotoPreprocessor.maximumSourceBytes else { throw MealAnalysisError.imageTooLarge }
                    sourceImage = data
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelAnalysis() }
            }
            .onDisappear { cancelAnalysis() }
        }
    }

    private func startAnalysis() {
        guard let sourceImage, !isAnalyzing else { return }
        let generation = UUID()
        requestGeneration = generation
        let requestContext = context
        errorMessage = nil
        isAnalyzing = true
        analysisTask = Task {
            defer {
                if requestGeneration == generation { isAnalyzing = false; analysisTask = nil }
            }
            do {
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    try MealPhotoPreprocessor().jpeg(from: sourceImage)
                }.value
                let key = try credentialStore.load()
                guard let key else { throw MealAnalysisError.missingCredential }
                let file = try await analysisClient.analyze(jpeg: jpeg, context: requestContext, apiKey: key)
                guard !Task.isCancelled, requestGeneration == generation else { return }
                reviewingFile = file
            } catch is CancellationError {
                // Cancellation is local. Keep the draft and let the user explicitly retry.
            } catch {
                guard !Task.isCancelled, requestGeneration == generation else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelAnalysis() {
        requestGeneration = UUID()
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    private func prepareCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraError = "This device does not have an available camera. Select a photo instead."
            showingCameraUnavailable = true
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed: Bool
        if status == .authorized { allowed = true }
        else if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        else { allowed = false }
        guard allowed else {
            cameraError = "Allow camera access in Settings or select a photo instead."
            showingCameraUnavailable = true
            return
        }
        showingCamera = true
    }
}

private struct ReviewingMeal: Identifiable {
    let id = UUID()
    let file: CustomMealFile
    init(_ file: CustomMealFile) { self.file = file }
}

private struct MealCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MealCameraPicker
        init(_ parent: MealCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
