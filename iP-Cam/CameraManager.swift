import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var isVideoEnabled = true
    @Published var isAudioEnabled = true
    @Published var selectedResolution: VideoResolution = .hd720p
    
    enum VideoResolution: String, CaseIterable {
        case low = "Low (480p)"
        case medium = "Medium (720p)"
        case hd720p = "HD (720p)"
        case hd1080p = "Full HD (1080p)"
        case hd4K3840x2160 = "4K (2160p)"
        
        var preset: AVCaptureSession.Preset {
            switch self {
            case .low: return .vga640x480
            case .medium: return .medium
            case .hd720p: return .hd1280x720
            case .hd1080p: return .hd1920x1080
            case .hd4K3840x2160: return .hd4K3840x2160
            }
        }
    }
    
    let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let videoQueue = DispatchQueue(label: "videoQueue")
    private let audioQueue = DispatchQueue(label: "audioQueue")
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    override init() {
        super.init()
        setupAudioSession()
        setupCaptureSession()
        setupBackgroundHandling()
        setupRemoteControlListeners()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .allowAirPlay])
            try audioSession.setActive(true)
            
            // Keep audio session active for background operation
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                DispatchQueue.main.async {
                    self.startSession()
                }
            }
        }
    }
    
    private func setupBackgroundHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appWillResignActive() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "CameraCapture") {
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }
    }
    
    @objc private func appDidBecomeActive() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Request extended background time for camera capture
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "CameraCapture") {
            print("⚠️ Background task expired - attempting to restart")
            // Try to restart background task
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "CameraCapture") {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
        
        // Keep capture session running
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
    }
    
    func updateResolution(_ resolution: VideoResolution) {
        selectedResolution = resolution
        captureSession.beginConfiguration()
        captureSession.sessionPreset = resolution.preset
        captureSession.commitConfiguration()
    }
    
    private func setupCaptureSession() {
        captureSession.sessionPreset = selectedResolution.preset
        
        // Setup video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        
        // Configure for low latency
        try? videoDevice.lockForConfiguration()
        videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30) // 30 FPS max
        if videoDevice.isLowLightBoostSupported {
            videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = false
        }
        videoDevice.unlockForConfiguration()
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        // Setup audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else { return }
        
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }
        
        // Setup video output
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        videoOutput?.setSampleBufferDelegate(self, queue: videoQueue)
        
        if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            
            // Listen for orientation changes to update capture connection
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(orientationChanged),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            
            updateCaptureOrientation()
        }
        
        // Setup audio output
        audioOutput = AVCaptureAudioDataOutput()
        audioOutput?.setSampleBufferDelegate(self, queue: audioQueue)
        
        if let audioOutput = audioOutput, captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        }
    }
    
    func startSession() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Check if video/audio is enabled before sending
        if output == videoOutput && !isVideoEnabled {
            return
        }
        if output == audioOutput && !isAudioEnabled {
            return
        }
        
        // Send to both old and new notification names for compatibility
        NotificationCenter.default.post(name: NSNotification.Name("NewSampleBuffer"), object: sampleBuffer)
        NotificationCenter.default.post(name: NSNotification.Name("NewVideoSampleBuffer"), object: sampleBuffer)
    }

    @objc private func orientationChanged() {
        updateCaptureOrientation()
    }

    private func updateCaptureOrientation() {
        guard let connection = videoOutput?.connection(with: .video),
              connection.isVideoOrientationSupported else { return }
        
        let deviceOrientation = UIDevice.current.orientation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch deviceOrientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeRight  // This was backwards
        case .landscapeRight:
            videoOrientation = .landscapeLeft   // This was backwards
        default:
            videoOrientation = .portrait
        }
        
        connection.videoOrientation = videoOrientation
    }

    private func setupRemoteControlListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteResolutionChange),
            name: NSNotification.Name("ChangeResolution"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteVideoToggle),
            name: NSNotification.Name("ToggleVideo"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteAudioToggle),
            name: NSNotification.Name("ToggleAudio"),
            object: nil
        )
    }

    @objc private func handleRemoteResolutionChange(_ notification: Notification) {
        if let resolutionString = notification.object as? String,
           let resolution = VideoResolution.allCases.first(where: { $0.rawValue == resolutionString }) {
            DispatchQueue.main.async {
                self.selectedResolution = resolution
                self.updateResolution(resolution)
            }
        }
    }

    @objc private func handleRemoteVideoToggle(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isVideoEnabled.toggle()
        }
    }

    @objc private func handleRemoteAudioToggle(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isAudioEnabled.toggle()
        }
    }
}
