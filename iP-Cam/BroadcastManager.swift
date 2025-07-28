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
        setupNotificationListeners()
        isBroadcasting = true
    }

    func setupNotificationListeners() {
        // Listen for video frames for recording
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
    }
    
    func stopBroadcast() {
        guard isBroadcasting else { return }
        
        NotificationCenter.default.removeObserver(self)
        stopRecording()
        cameraManager = nil
        isBroadcasting = false
    }
    
    func startRecording() {
        guard !isRecording else {
            print("⚠️ Recording already in progress")
            return
        }

        guard isBroadcasting else {
            print("⚠️ Cannot start recording - broadcast is not active")
            return
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Ensure documents directory exists
        do {
            try FileManager.default.createDirectory(at: documentsPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ Failed to create documents directory: \(error)")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        recordingURL = documentsPath.appendingPathComponent("recording_\(timestamp).mjpeg")

        guard let url = recordingURL else {
            print("❌ Failed to create recording URL")
            return
        }

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
            print("📹 Documents directory: \(documentsPath.path)")

            // Verify file was created
            if FileManager.default.fileExists(atPath: url.path) {
                print("✅ Recording file created successfully")
            } else {
                print("❌ Recording file was not created")
            }
        } catch {
            print("❌ Failed to start recording: \(error)")
            isRecording = false
            recordingURL = nil
            recordingFileHandle = nil
        }
    }
    
    func stopRecording() {
        guard isRecording else {
            print("⚠️ No recording in progress to stop")
            return
        }

        recordingFileHandle?.closeFile()
        recordingFileHandle = nil

        if let url = recordingURL {
            print("📹 Recording saved to: \(url.lastPathComponent)")
            print("📹 Full path: \(url.path)")

            // Check file size
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? Int64 {
                    print("📹 Recording file size: \(fileSize) bytes")
                }
            } catch {
                print("❌ Failed to get file attributes: \(error)")
            }
        }
        recordingURL = nil
        isRecording = false
        print("✅ Recording stopped successfully")
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

            // Only print every 30 frames to reduce log spam
            if Int.random(in: 1...30) == 1 {
                print("📹 Recording frame: \(jpegData.count) bytes")
            }
        }
    }
    
    @objc private func handleRemoteRecordingToggle(_ notification: Notification) {
        DispatchQueue.main.async {
            print("📹 Remote recording toggle received")

            // Only allow recording toggle if broadcasting is active
            guard self.isBroadcasting else {
                print("⚠️ Recording toggle ignored - broadcast is not active")
                return
            }

            if self.isRecording {
                self.stopRecording()
            } else {
                self.startRecording()
            }
        }
    }

    func listRecordedFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [])
            let recordingFiles = files.filter { $0.pathExtension == "mjpeg" }

            print("📹 Found \(recordingFiles.count) recording files:")
            for file in recordingFiles {
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
                let fileSize = attributes?[.size] as? Int64 ?? 0
                let creationDate = attributes?[.creationDate] as? Date ?? Date()
                print("  - \(file.lastPathComponent) (\(fileSize) bytes, created: \(creationDate))")
            }
        } catch {
            print("❌ Failed to list recording files: \(error)")
        }
    }
}
