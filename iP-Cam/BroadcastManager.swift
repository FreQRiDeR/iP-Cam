import AVFoundation
import VideoToolbox
import UIKit
import CoreImage

class BroadcastManager: ObservableObject {
    @Published var isBroadcasting = false
    @Published var isRecording = false
    
    private weak var cameraManager: CameraManager?
    private var recordingFileHandle: FileHandle?
    private var recordingURL: URL?
    private let boundary = "recordingboundary"
    
    deinit {
        stopBroadcast()
        stopRecording()
    }
    
    func startBroadcast(cameraManager: CameraManager) {
        guard !isBroadcasting else { return }
        
        self.cameraManager = cameraManager
        
        // Listen for video frames if recording
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVideoSampleBuffer),
            name: NSNotification.Name("NewSampleBuffer"),
            object: nil
        )
        
        // Listen for remote recording toggle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteRecordingToggle),
            name: NSNotification.Name("ToggleRecording"),
            object: nil
        )
        
        isBroadcasting = true
    }
    
    func stopBroadcast() {
        guard isBroadcasting else { return }
        
        NotificationCenter.default.removeObserver(self)
        stopRecording()
        cameraManager = nil
        isBroadcasting = false
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        recordingURL = documentsPath.appendingPathComponent("recording_\(timestamp).mjpeg")
        
        guard let url = recordingURL else { return }
        
        do {
            // Create initial MJPEG header
            let header = """
            Content-Type: multipart/x-mixed-replace; boundary=\(boundary)\r\n\r\n
            """.data(using: .utf8)!
            
            try header.write(to: url)
            recordingFileHandle = try FileHandle(forWritingTo: url)
            recordingFileHandle?.seekToEndOfFile()
            
            isRecording = true
            print("📹 Started recording to: \(url.lastPathComponent)")
            print("📹 Full path: \(url.path)")
        } catch {
            print("❌ Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        recordingFileHandle?.closeFile()
        recordingFileHandle = nil
        
        if let url = recordingURL {
            print("📹 Recording saved to: \(url.lastPathComponent)")
        }
        recordingURL = nil
        isRecording = false
    }
    
    @objc private func handleVideoSampleBuffer(_ notification: Notification) {
        guard let sampleBuffer = notification.object,
              CFGetTypeID(sampleBuffer as CFTypeRef) == CMSampleBufferGetTypeID() else { return }
        
        let cmSampleBuffer = sampleBuffer as! CMSampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer) else { return }
        
        // Only record if recording is enabled
        if isRecording {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            
            let image = UIImage(cgImage: cgImage)
            guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return }
            
            // Write MJPEG frame
            let frameHeader = """
            --\(boundary)\r
            Content-Type: image/jpeg\r
            Content-Length: \(jpegData.count)\r
            \r
            
            """.data(using: .utf8)!
            
            recordingFileHandle?.write(frameHeader)
            recordingFileHandle?.write(jpegData)
            recordingFileHandle?.write("\r\n".data(using: .utf8)!)
            
            print("📹 Wrote frame: \(jpegData.count) bytes")
        }
    }
    
    @objc private func handleRemoteRecordingToggle(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isRecording.toggle()
            if self.isRecording {
                self.startRecording()
            } else {
                self.stopRecording()
            }
        }
    }
}
