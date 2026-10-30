//
//  ContentView.swift
//  LidarPhoto
//
//  Created by Shubhankar Singh on 10/28/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var camera = DepthCamera()
    @State private var showingRange = false

    private static let minGap: Float = 0.1
    private static let maxMeters: Float = 10

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .running:
                if let preview = camera.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea(edges: .bottom)
                }
            case .idle:
                ProgressView().tint(.white)
            case .unsupported:
                notice("LiDAR not available", "This app needs an iPhone or iPad Pro with a LiDAR scanner.")
            case .denied:
                notice("Camera access needed", "Enable camera access for LidarPhoto in Settings.")
            case .failed(let reason):
                notice("Camera error", reason)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if let message = camera.message {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                HStack {
                    rangeButton
                    Spacer()
                    shutterButton
                    Spacer()
                    paletteMenu
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingRange) { rangeSheet }
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var isRunning: Bool { camera.status == .running }

    private var shutterButton: some View {
        Button {
            Task { await camera.capture() }
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .background(Circle().fill(.white).padding(6))
                .frame(width: 72, height: 72)
        }
        .disabled(!isRunning)
        .opacity(isRunning ? 1 : 0.3)
    }

    private var rangeButton: some View {
        Button {
            showingRange = true
        } label: {
            Image(systemName: "ruler.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(!isRunning)
        .opacity(isRunning ? 1 : 0.3)
    }

    private var rangeSheet: some View {
        let near = Binding(
            get: { camera.nearMeters },
            set: { camera.nearMeters = min($0, camera.farMeters - Self.minGap) }
        )
        let far = Binding(
            get: { camera.farMeters },
            set: { camera.farMeters = max($0, camera.nearMeters + Self.minGap) }
        )
        return VStack(spacing: 20) {
            HStack {
                Text("Depth range").font(.headline)
                Spacer()
                Button("Reset") {
                    camera.nearMeters = DepthRenderer.defaultRange.lowerBound
                    camera.farMeters = DepthRenderer.defaultRange.upperBound
                }
            }
            rangeSlider("Min", value: near, range: 0...(Self.maxMeters - Self.minGap))
            rangeSlider("Max", value: far, range: Self.minGap...Self.maxMeters)
        }
        .padding(24)
        .presentationDetents([.height(250)])
        .presentationBackgroundInteraction(.enabled)
        .preferredColorScheme(.dark)
    }

    private func rangeSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack {
            Text(title).frame(width: 36, alignment: .leading)
            Slider(value: value, in: range, step: 0.05)
            Text(String(format: "%.2f m", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var paletteMenu: some View {
        Menu {
            Picker("Gradient", selection: $camera.palette) {
                ForEach(DepthPalette.allCases) { palette in
                    Text(palette.rawValue).tag(palette)
                }
            }
        } label: {
            Image(systemName: "paintpalette.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(!isRunning)
        .opacity(isRunning ? 1 : 0.3)
    }

    private func notice(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding()
    }
}

#Preview {
    ContentView()
}
