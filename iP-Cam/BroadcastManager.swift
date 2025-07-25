import AVFoundation
import VideoToolbox

class BroadcastManager: ObservableObject {
    @Published var isBroadcasting = false
    
    private var hlsWriter: HLSWriter?
    private weak var cameraManager: CameraManager?
    
    deinit {
        stopBroadcast()
    }
    
    func startBroadcast(cameraManager: CameraManager) {
        guard !isBroadcasting else { return }
        
        self.cameraManager = cameraManager
        hlsWriter = HLSWriter()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSampleBuffer(_:)),
            name: NSNotification.Name("NewSampleBuffer"),
            object: nil
        )
        
        hlsWriter?.startWriting()
        isBroadcasting = true
    }
    
    func stopBroadcast() {
        guard isBroadcasting else { return }
        
        NotificationCenter.default.removeObserver(self)
        hlsWriter?.stopWriting()
        hlsWriter = nil
        cameraManager = nil
        isBroadcasting = false
    }
    
    @objc private func handleSampleBuffer(_ notification: Notification) {
        guard isBroadcasting,
              let sampleBuffer = notification.object,
              CFGetTypeID(sampleBuffer as CFTypeRef) == CMSampleBufferGetTypeID() else { return }
        
        let cmSampleBuffer = sampleBuffer as! CMSampleBuffer
        
        // Check if this is a video sample buffer
        guard let formatDescription = CMSampleBufferGetFormatDescription(cmSampleBuffer) else { return }
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
        
        // Only send video samples to HLS writer and check if video is enabled
        if mediaType == kCMMediaType_Video && cameraManager?.isVideoEnabled == true {
            hlsWriter?.processSampleBuffer(cmSampleBuffer)
        }
        // Handle audio samples if audio is enabled
        else if mediaType == kCMMediaType_Audio && cameraManager?.isAudioEnabled == true {
            hlsWriter?.processSampleBuffer(cmSampleBuffer)
        }
    }
}
