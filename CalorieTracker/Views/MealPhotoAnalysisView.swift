import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct MealAnalysisView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let targetDate: Date
    let onLogged: () -> Void
    private let analysisClient: any MealAnalysisClient
    private let credentialStore: any OpenAICredentialStoring

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sourceImage: Data?
    @State private var mealDescription = ""
    @State private var analysisTask: Task<Void, Never>?
    @State private var requestGeneration = UUID()
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var errorNeedsUsageHelp = false
    @State private var reviewingFile: CustomMealFile?
    @State private var showingCamera = false
    @State private var showingCameraUnavailable = false
    @State private var cameraError: String?
    @FocusState private var descriptionIsFocused: Bool

    private var hasUsableInput: Bool {
        sourceImage != nil || !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        targetDate: Date,
        initialDescription: String? = nil,
        onLogged: @escaping () -> Void,
        analysisClient: any MealAnalysisClient = OpenAIMealAnalysisClient(),
        credentialStore: any OpenAICredentialStoring = OpenAICredentialStore.shared
    ) {
        self.targetDate = targetDate
        self.onLogged = onLogged
        self.analysisClient = analysisClient
        self.credentialStore = credentialStore
        _mealDescription = State(initialValue: initialDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meal description")
                            .font(.headline)
                        TextField("What did you eat? Include portions or ingredients if you know them.", text: $mealDescription, axis: .vertical)
                            .lineLimit(3...5)
                            .focused($descriptionIsFocused)
                            .accessibilityLabel("Meal description")
                            .onChange(of: mealDescription) { _, value in
                                if value.count > MealAnalysisRequest.maximumDescriptionCharacters {
                                    mealDescription = String(value.prefix(MealAnalysisRequest.maximumDescriptionCharacters))
                                }
                            }
                            .padding(12)
                            .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                        Text("\(mealDescription.count)/\(MealAnalysisRequest.maximumDescriptionCharacters)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photo (optional)")
                            .font(.headline)
                        if let sourceImage, let image = UIImage(data: sourceImage) {
                            HStack(spacing: 12) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .accessibilityLabel("Selected meal photo")
                                Text("Photo added")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Button("Remove", systemImage: "xmark.circle.fill", role: .destructive) {
                                    selectedPhoto = nil
                                    self.sourceImage = nil
                                }
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("Remove selected photo")
                            }
                        }
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label(sourceImage == nil ? "Add Photo" : "Change Photo", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                Task { await prepareCamera() }
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        if let cameraError { Text(cameraError).font(.caption).foregroundStyle(.red) }
                    }

                    Text("Your description and any photo you add will be sent to OpenAI. The estimate is not a measured nutrition result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(errorMessage).font(.callout).foregroundStyle(.red)
                            if errorNeedsUsageHelp {
                                Link("Check OpenAI API rate limits", destination: URL(string: "https://platform.openai.com/settings/organization/limits")!)
                                Link("Check OpenAI API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if isAnalyzing {
                        ProgressView("Analyzing meal…")
                        Text("This sends one request to OpenAI. Cancel stops waiting here, but it may not stop provider processing or charges.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Cancel Analysis", role: .cancel, action: cancelAnalysis)
                            .buttonStyle(.bordered)
                    } else {
                        Button(action: startAnalysis) {
                            Label(errorMessage == nil ? "Analyze Meal" : "Retry Analysis", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasUsableInput)
                        Text("Each analysis may incur usage charges. Nothing is logged until you review the estimate.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.regularMaterial)
            }
            .navigationTitle("Analyze Meal")
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
                    errorNeedsUsageHelp = false
                }
            }
            .alert("Camera unavailable", isPresented: $showingCameraUnavailable) {
                Button("OK", role: .cancel) { }
            } message: { Text(cameraError ?? "Allow camera access in Settings or select a photo instead.") }
            .sheet(item: Binding(get: { reviewingFile.map(ReviewingMeal.init) }, set: { reviewingFile = $0?.file })) { item in
                CustomMealImportView(file: item.file, targetDate: targetDate, source: .openAIAnalysis, onLogged: {
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
        guard hasUsableInput, !isAnalyzing else { return }
        let generation = UUID()
        requestGeneration = generation
        let requestDescription = mealDescription
        let requestImage = sourceImage
        descriptionIsFocused = false
        errorMessage = nil
        errorNeedsUsageHelp = false
        isAnalyzing = true
        analysisTask = Task {
            defer {
                if requestGeneration == generation { isAnalyzing = false; analysisTask = nil }
            }
            do {
                let jpeg: Data? = try await Task.detached(priority: .userInitiated) {
                    guard let requestImage else { return nil }
                    return try MealPhotoPreprocessor().jpeg(from: requestImage)
                }.value
                let key = try credentialStore.load()
                guard let key else { throw MealAnalysisError.missingCredential }
                let file = try await analysisClient.analyze(description: requestDescription, jpeg: jpeg, apiKey: key)
                guard !Task.isCancelled, requestGeneration == generation else { return }
                reviewingFile = file
            } catch is CancellationError {
                // Cancellation is local. Keep the draft and let the user explicitly retry.
            } catch {
                guard !Task.isCancelled, requestGeneration == generation else { return }
                errorMessage = error.localizedDescription
                errorNeedsUsageHelp = (error as? MealAnalysisError)?.hasAPIUsageHelp == true
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
