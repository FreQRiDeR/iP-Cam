//
//  ContentView.swift
//  iP-Cam
//
//  Created by terraMODA on 7/23/25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var broadcastManager = BroadcastManager()
    @StateObject private var httpServerManager = HTTPServerManager()
    @State private var showSettings = false
    @State private var isScreenDimmed = false
    @State private var dimTimer: Timer?
    
    var body: some View {
        ZStack {
            // Fullscreen Camera Preview
            CameraPreviewView(session: cameraManager.captureSession)
                .ignoresSafeArea()
            
            // Black overlay when dimmed
            if isScreenDimmed {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture {
                        undimScreen()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                undimScreen()
                            }
                    )
            }
            
            // UI elements (only show when not dimmed)
            if !isScreenDimmed {
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: "video.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                Text("iP-Cam")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        Spacer()
                        
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                    Spacer()
                }
                
                // Settings overlay
                if showSettings {
                    VStack(spacing: 20) {
                        Text("Settings")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Video Resolution")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Picker("Resolution", selection: $cameraManager.selectedResolution) {
                                ForEach(CameraManager.VideoResolution.allCases, id: \.self) { resolution in
                                    Text(resolution.rawValue).tag(resolution)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: cameraManager.selectedResolution) { resolution in
                                cameraManager.updateResolution(resolution)
                            }
                        }
                        
                        Button("Done") {
                            showSettings = false
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(15)
                    .padding()
                }
                
                // Bottom overlay with controls
                VStack {
                    Spacer()
                    
                    // Network Info
                    if broadcastManager.isBroadcasting {
                        VStack(spacing: 4) {
                            Text("http://\(httpServerManager.localIPAddress):8080")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                        }
                        .padding(.bottom, 8)
                    }
                    
                    // Controls
                    HStack(spacing: 20) {
                        // Video toggle
                        Button(action: { cameraManager.isVideoEnabled.toggle() }) {
                            Image(systemName: cameraManager.isVideoEnabled ? "video.fill" : "video.slash.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(cameraManager.isVideoEnabled ? Color.blue : Color.gray)
                                .clipShape(Circle())
                        }
                        
                        // Broadcast button
                        Button(action: toggleBroadcast) {
                            Image(systemName: broadcastManager.isBroadcasting ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 70, height: 70)
                                .background(broadcastManager.isBroadcasting ? Color.red : Color.green)
                                .clipShape(Circle())
                        }
                        
                        // Audio toggle
                        Button(action: { cameraManager.isAudioEnabled.toggle() }) {
                            Image(systemName: cameraManager.isAudioEnabled ? "mic.fill" : "mic.slash.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(cameraManager.isAudioEnabled ? Color.blue : Color.gray)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            cameraManager.requestPermissions()
            startDimTimer()
        }
        .onTapGesture {
            resetDimTimer()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    resetDimTimer()
                }
        )
    }
    
    private func toggleBroadcast() {
        if broadcastManager.isBroadcasting {
            print("🛑 Stopping broadcast...")
            broadcastManager.stopBroadcast()
            httpServerManager.stopServer()
        } else {
            print("🚀 Starting broadcast...")
            print("📱 Device IP: \(httpServerManager.localIPAddress)")
            broadcastManager.startBroadcast(cameraManager: cameraManager)
            httpServerManager.startServer()
        }
    }
    
    private func startDimTimer() {
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                isScreenDimmed = true
            }
        }
    }
    
    private func resetDimTimer() {
        if isScreenDimmed {
            undimScreen()
        } else {
            startDimTimer()
        }
    }
    
    private func undimScreen() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isScreenDimmed = false
        }
        startDimTimer()
    }
}

struct ToggleButton: View {
    let title: String
    @Binding var isOn: Bool
    let systemImage: String
    
    var body: some View {
        VStack {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(isOn ? .white : .gray)
            Text(title)
                .font(.caption)
                .foregroundColor(isOn ? .white : .gray)
        }
        .frame(width: 80, height: 60)
        .background(isOn ? Color.blue : Color.gray.opacity(0.2))
        .cornerRadius(12)
        .onTapGesture {
            isOn.toggle()
        }
    }
}
