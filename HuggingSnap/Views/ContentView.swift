////
////  ContentView.swift
////  HuggingSnap
////
////  Created by Cyril Zakka on 2/11/25.
////
import AVKit
import PhotosUI
import SwiftUI
import CoreHaptics
import StoreKit

// TODO: Stop streaming when not displayed

enum LoadState {
    case unknown
    case loading
    case loadedMovie(Video)
    case loadedImage(UIImage)
    case failed
}

struct ContentView: View {
    
    // Misc
    @Environment(\.requestReview) var requestReview
    
    // Control state
    @StateObject private var model = ContentViewModel()
    @State private var isCaptured: Bool = false
    
    // Import from Photos
    @State private var selectedItem: PhotosPickerItem?
    @State private var loadState = LoadState.unknown
    
    // Videos
    @State var player = AVPlayer()
    
    // LLM
    @State var llm = VLMEvaluator()
    @State var isLLMLoaded: Bool = false
    
    // Custom Haptics
    @State private var engine: CHHapticEngine?
    
    // Settings
    @State private var showSettings: Bool = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.vertical)
            
            switch loadState {
            case .unknown, .loading, .failed:
#if !targetEnvironment(simulator)
                FrameView(image: model.frame)
                    .edgesIgnoringSafeArea(.vertical)
#endif
            case .loadedMovie(let movie):
                Group {
                    ZStack {
                        Color.clear
                            .edgesIgnoringSafeArea(.vertical)
                    }.background {
                        VideoPlayer(player: player)
                            .aspectRatio(contentMode: .fill)
                            .edgesIgnoringSafeArea(.vertical)
                            .onAppear() {
                                setupPlayer(with: movie.url)
                            }
                        
                    }
                }
                .ignoresSafeArea(.keyboard)
                //
            case .loadedImage(let image):
                //                // Handle loaded image
                //                // Little hacky but needed otherwise buttons overflow on edges
                //                // Do not be tempted to remove
                Group {
                    ZStack {
                        Color.clear.edgesIgnoringSafeArea(.vertical)
                    }.background {
                        Image(uiImage: image)
                            .resizable()
                            .edgesIgnoringSafeArea(.vertical)
                            .aspectRatio(contentMode: .fill)
                            .edgesIgnoringSafeArea(.vertical)
                        //
                    }
                }.ignoresSafeArea(.keyboard)
                //
            }
        }
        .onAppear {
            // Will always appear in DEBUG. Not a bug
             requestReview()
        }
        .overlay {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: { showSettings = true }, label: {
                            Image(systemName: "gearshape")
                                .fontWeight(.bold)
                                .foregroundStyle(.white.secondary)
                        })
                        Spacer()
                    }.padding(.horizontal, 40)
                    
                    MessageView(text: llm.output)
                        .opacity(llm.output.isEmpty ? 0:1)
                    
                    Spacer()
                    if !isLLMLoaded {
                        Text(llm.modelInfo)
                            .contentTransition(.numericText())
                            .font(.caption)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background {
                                Capsule()
                                    .fill(.regularMaterial)
                            }
                    }
                    ControlView(selectedItem: $selectedItem, isCaptured: $isCaptured, loadState: $loadState)
                        .environmentObject(model)
                        .environment(llm)
                        .padding()
                        .preferredColorScheme(.dark)
                }
            }
        }
        
        // MARK: Loading view
        .overlay {
#if !targetEnvironment(simulator)
            if !isLLMLoaded {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .edgesIgnoringSafeArea(.vertical)
                        .transition(.blurReplace)
                    
                    VStack {
                        VStack {
                            Text("Visual Intelligence\nwith Hugging Face")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(

                                        LinearGradient(
                                            colors: [.orange, .yellow],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                .padding(.bottom)
                            
                            Text("Learn about the objects and places around you and get information about what you see")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                            
                            Text("Photos and videos used are processed entirely on your device. No data is sent to the cloud.")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            //                            .padding(.bottom, 100)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        
                        Button(action: {
                            // Dismiss
                        }, label: {
                            HStack {
                                ProgressView()
                                Text(llm.modelInfo)
                                    .contentTransition(.numericText())
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 15)
                            .background {
                                Capsule()
                                    .fill(.regularMaterial)
                            }
                        })
                        .tint(.white)
                    }
                    .padding(.horizontal)
                    
                    
                }
            }
#endif
        }
        // Detect photo capture
        .onChange(of: model.photo) {
            if let photoData = model.photo {
                isCaptured = true
                if !model.isStreamingPaused {
                    model.toggleStreaming()
                }
                if let uiImage = UIImage(data: photoData) {
                    loadState = .loadedImage(uiImage)
                }
            }
        }
        .onChange(of: llm.running) { oldValue, newValue in
            if newValue == false { // on llm completion
                triggerHapticsOnFinish()
            }
        }
        .onChange(of: model.movieURL) {
            if !model.isRecording {
                if let movieURL = model.movieURL {
                    isCaptured = true
                    if !model.isStreamingPaused {
                        model.toggleStreaming()
                    }
                    loadState = .loadedMovie(Video(url: movieURL))
                }
            }
            
        }
        // Detect photo picker selection
        .onChange(of: selectedItem) {
            if !model.isStreamingPaused {
                model.toggleStreaming()
            }
            Task {
                do {
                    if selectedItem == nil {
                        loadState = .unknown
                    } else {
                        loadState = .loading
                        if let video = try await selectedItem?.loadTransferable(type: Video.self) {
                            // Video
                            loadState = .loadedMovie(video)
                            isCaptured = true
                        } else if let image = try await selectedItem?.loadTransferable(type: Data.self) {
                            // Image
                            if let uiImage = UIImage(data: image) {
                                loadState = .loadedImage(uiImage)
                            }
                            isCaptured = true
                        }
                    }
                    
                    
                } catch {
                    loadState = .failed
                }
            }
        }
        .onAppear { prepareHaptics() }
        .task {
#if !targetEnvironment(simulator)
            _ = try? await llm.load()
            await MainActor.run {
                withAnimation {
                    isLLMLoaded = true
                }
            }
#endif
        }
        .sheet(isPresented: $showSettings, content: {
            SettingsView()
        })
    }
    
    // MARK: Helpers
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("There was an error creating the engine: \(error.localizedDescription)")
        }
    }
    
    func triggerHapticsOnFinish() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        var events = [CHHapticEvent]()

        // sharp tap
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        events.append(event)
        
        // two soft taps
        let intensity2 = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
        let sharpness2 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
        let event2 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity2, sharpness2], relativeTime: 0.1)
        events.append(event2)

        
        let intensity3 = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
        let sharpness3 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        let event3 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity3, sharpness3], relativeTime: 0.2)
        events.append(event3)

        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play pattern: \(error.localizedDescription).")
        }
    }
    
    private func setupPlayer(with url: URL) {
        player = AVPlayer(url: url)
        
        // Add loop observation
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        player.play()
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
