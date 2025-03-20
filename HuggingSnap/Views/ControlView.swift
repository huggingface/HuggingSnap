//
//  ControlView.swift
//  HuggingSnap
//
//  Created by Cyril Zakka on 2/18/25.
//

import Foundation
import SwiftUI
import PhotosUI

struct ControlView: View {
    // SORRY THIS IS MESSY. Should clean it up someday when we know what features should be added.
    
    @EnvironmentObject var model: ContentViewModel
    
    // Bindings
    @Binding var selectedItem: PhotosPickerItem?
    
    @State private var isProcessing = false
    
    // Main button
    @Binding var isCaptured: Bool
    @State private var scaleDown: Bool = false
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0.3
    
    @Environment(VLMEvaluator.self) private var llm
    @Binding var loadState: LoadState
    
    // Alt buttons
    @State private var showInputView: Bool = false
    @State private var isAudioMode: Bool = false
    @State private var textFieldText = ""

    private var gradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                .clear,
                .white.opacity(opacity+0.1),
                .clear,
                .white.opacity(opacity),
                .clear,
                .white.opacity(opacity+0.1),
            ]),
            center: .center,
            startAngle: .degrees(270),
            endAngle: .degrees(0)
        )
    }
    
    var body: some View {
        
        if showInputView {
            InputView(isTextMode: $showInputView, isAudioMode: $isAudioMode, textFieldText: $textFieldText) { textPrompt in
                llm.customUserInput = textPrompt
                textFieldText = ""
                Task {
                    if case .loadedImage(let uIImage) = loadState {
                        let ciImage = CIImage(image: uIImage)
                        await llm.generate(image: ciImage ?? CIImage(), videoURL: nil)
                    }
                    if case .loadedMovie(let video) = loadState { await llm.generate(image: nil, videoURL: video.url) }
                }
            }
        } else {
            VStack(alignment: .center, spacing: 20) {
                
                if isCaptured {
                    HStack(spacing: 20) {
                        if case .loadedImage(let uIImage) = loadState {
                            Button {
                                // Image description
                                llm.customUserInput = ""
                                Task {
                                    let ciImage = CIImage(image: uIImage)
                                    await llm.generate(image: ciImage ?? CIImage(), videoURL: nil)
                                }
                                
                            } label: {
                                Label("Describe", systemImage: "text.quote")
                                    .foregroundStyle(.white)
                                    .fontWeight(.semibold)
                                    .font(.footnote)
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 12)
                                    .background {
                                        Capsule()
                                            .fill(.ultraThickMaterial)
                                    }
                            }
                            .accessibilityLabel(Text("Press this button to have HuggingSnap describe the current image"))
                            .transition(.blurReplace.combined(with: .scale))
                        }
                        
                        if case .loadedMovie(let video) = loadState {
                            Button {
                                llm.customUserInput = ""
                                Task {
                                    await llm.generate(image: nil, videoURL: video.url)
                                }
                            } label: {
                                Label("Summarize", systemImage: "text.append")
                                    .foregroundStyle(.white)
                                    .fontWeight(.semibold)
                                    .font(.footnote)
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 12)
                                    .background {
                                        Capsule()
                                            .fill(.ultraThickMaterial)
                                    }
                            }
                            .accessibilityLabel(Text("Press this button to have HuggingSnap summarize the current video."))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                
                HStack {
                    if isCaptured {
                        Button {
                            isAudioMode = false
                            showInputView = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.regularMaterial)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "text.bubble")
                                    .foregroundStyle(.white)
                                    .fontWeight(.bold)
                            }
                        }
                        .accessibilityLabel(Text("Press the button to type a message to HuggingSnap"))
                    } else {
                        PhotosPicker(selection: $selectedItem,
                                     matching: .any(of: [.images, .videos])) {
                            ZStack {
                                Circle()
                                    .fill(.regularMaterial)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "photo.fill.on.rectangle.fill")
                                    .foregroundStyle(.white)
                                    .fontWeight(.bold)
                            }
                        }
                                     .accessibilityLabel(Text("Press the button to select a photo or video as input to HuggingSnap"))
                    }
                    
                    
                    Spacer()
                    
                    
                    
                    // Capture button which serves as photo capture and video recording
                    ZStack {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 20)
                            TransparentBlurView(removeAllFilters: true)
                                .blur(radius: 9, opaque: true)
                                .background(.white.opacity(0.05))
                        }
                        .clipShape(.circle)
                        .frame(width: 60, height: 60)
                        
                        
                        Circle()
                            .stroke(gradient, lineWidth: 1)
                            .frame(width: 80, height: 80)
                        
                            .rotationEffect(.degrees(rotation))
                            .onAppear {
                                withAnimation(.linear(duration: 20)
                                    .repeatForever(autoreverses: false)) {
                                        rotation = 360
                                    }
                                
                                withAnimation(
                                    .easeInOut(duration: 4)
                                    .repeatForever(autoreverses: true)
                                ) {
                                    opacity = 0.4
                                }
                            }
                        
                        ZStack {
                            if isCaptured {
                                Image(systemName: "xmark")
                                    .foregroundStyle(.white)
                                    .fontWeight(.bold)
                                    .imageScale(.large)
                                    .transition(.blurReplace)
                                    .contentShape(.rect)
                            } else {
                                RoundedRectangle(cornerRadius: scaleDown ? 24:100)
                                    .fill(scaleDown ? .red:.white)
                                    .frame(width: 70, height: 70)
                                    .transition(.blurReplace)
                                    .scaleEffect(scaleDown ? 0.65 : 1)
                            }
                        }
                        .frame(width: 70, height: 70)
                        .contentShape(.rect)
                        .accessibilityLabel(Text(isCaptured ? "Press the button to clear the capture.":"Press the button to snap a picture. Tap and hold to record a video."))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !model.isRecording {
                                        withAnimation {
                                            scaleDown = true
                                        }
#if targetEnvironment(simulator)
#else
                                        if !model.isRecording {
                                            model.toggleRecording()
                                        }
#endif
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.smooth(duration: 0.1)) {
                                        scaleDown = false
                                    }
                                    if !isCaptured {
#if targetEnvironment(simulator)
#else
                                        if model.isRecording {
                                            model.toggleRecording()
                                        }
#endif
                                    }
                                }
                        )
                        .highPriorityGesture(
                            TapGesture()
                                .onEnded {
                                    if !isCaptured {
#if targetEnvironment(simulator)
#else
                                        model.capturePhoto()
#endif
                                    } else {
                                        clearAllInputs()
                                    }
                                    
                                }
                        )
                        
                    }
                    
                    Spacer()
                    
                    if isCaptured {
                        Button {
                            isAudioMode = true
                            showInputView = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.regularMaterial)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "mic")
                                    .foregroundStyle(.white)
                                    .fontWeight(.bold)
                            }
                        }
                        .accessibilityLabel(Text("Press the button to dictate a message to HuggingSnap"))
                    } else {
                        Button {
#if targetEnvironment(simulator)
#else
                            model.switchCamera()
#endif
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.regularMaterial)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.white)
                                    .fontWeight(.bold)
                            }
                        }
                        .accessibilityLabel(Text("Press the button to switch between front and back cameras"))
                        .disabled(isCaptured)
                    }
                    
                    
                }
            }
            .padding(.horizontal, 40)
            .preferredColorScheme(.dark)
            .animation(.spring, value: isCaptured)
        }
        
        
    }
    
    func clearAllInputs() {
        model.toggleStreaming()
        model.movieURL = nil
        model.photo = nil
        selectedItem = nil
        isCaptured = false
        loadState = .unknown
        llm.output = ""
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
