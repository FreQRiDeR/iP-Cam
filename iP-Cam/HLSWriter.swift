import AVFoundation
import VideoToolbox

class HLSWriter {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private let processingQueue = DispatchQueue(label: "hlsWriter", qos: .userInitiated)
    private var segmentCount = 0
    private var lastSegmentTime: CMTime = .zero
    private var segmentDuration: Double = 2.0
    private var frameCount = 0
    
    deinit {
        stopWriting()
    }
    
    func startWriting() {
        setupHLSDirectory()
        createInitialPlaylist()
        setupAssetWriter()
    }
    
    func stopWriting() {
        processingQueue.sync {
            if let writer = assetWriter, writer.status == .writing {
                writer.finishWriting { }
            }
            assetWriter = nil
            videoInput = nil
            pixelBufferAdaptor = nil
            sessionStarted = false
        }
    }
    
    private func setupHLSDirectory() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let hlsPath = documentsPath.appendingPathComponent("hls")
        
        try? FileManager.default.removeItem(at: hlsPath)
        try? FileManager.default.createDirectory(at: hlsPath, withIntermediateDirectories: true, attributes: nil)
        
        print("📁 HLS directory: \(hlsPath.path)")
    }
    
    private func createInitialPlaylist() {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:3
        #EXT-X-MEDIA-SEQUENCE:0
        
        """
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let playlistURL = documentsPath.appendingPathComponent("hls/playlist.m3u8")
        
        try? playlist.write(to: playlistURL, atomically: true, encoding: .utf8)
        print("📝 Created initial playlist")
    }
    
    private func setupAssetWriter() {
        segmentCount = 0
        frameCount = 0
        createNewSegmentWriter()
    }
    
    private func createNewSegmentWriter() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let segmentName = "segment\(segmentCount).mp4"
        let outputURL = documentsPath.appendingPathComponent("hls/\(segmentName)")
        
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2000000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoMaxKeyFrameIntervalKey: 30
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // Create pixel buffer adaptor
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1280,
                kCVPixelBufferHeightKey as String: 720
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )
            
            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)
            }
            
            guard assetWriter?.startWriting() == true else {
                print("❌ Failed to start writing: \(assetWriter?.error?.localizedDescription ?? "unknown")")
                return
            }
            
            sessionStarted = false
            frameCount = 0
            print("🎬 Created new segment writer: \(segmentName)")
            
        } catch {
            print("❌ Failed to setup asset writer: \(error)")
        }
    }
    
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        processingQueue.async { [weak self] in
            self?.processBufferInternal(sampleBuffer)
        }
    }
    
    private func processBufferInternal(_ sampleBuffer: CMSampleBuffer) {
        guard let assetWriter = assetWriter,
              assetWriter.status == .writing else {
            print("⚠️ Asset writer not ready")
            return
        }
        
        guard let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor else {
            print("⚠️ No video input or adaptor")
            return
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("⚠️ No image buffer")
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if !sessionStarted {
            assetWriter.startSession(atSourceTime: timestamp)
            sessionStarted = true
            lastSegmentTime = timestamp
            print("✅ Started session")
        }
        
        if videoInput.isReadyForMoreMediaData {
            if pixelBufferAdaptor.append(imageBuffer, withPresentationTime: timestamp) {
                frameCount += 1
                print("📹 Frame \(frameCount) written at \(CMTimeGetSeconds(timestamp))")
            } else {
                print("❌ Failed to append frame")
            }
        }
        
        // Check if we should create a new segment
        let timeSinceLastSegment = CMTimeSubtract(timestamp, lastSegmentTime)
        if CMTimeGetSeconds(timeSinceLastSegment) >= segmentDuration && frameCount > 0 {
            print("🔄 Finishing segment with \(frameCount) frames")
            finishCurrentSegment()
            segmentCount += 1
            lastSegmentTime = timestamp
            createNewSegmentWriter()
        }
    }
    
    private func finishCurrentSegment() {
        guard let writer = assetWriter, writer.status == .writing else { return }
        
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                self?.updatePlaylist()
            }
        }
    }
    
    private func updatePlaylist() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let playlistURL = documentsPath.appendingPathComponent("hls/playlist.m3u8")
        
        var playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:3
        #EXT-X-MEDIA-SEQUENCE:\(max(0, segmentCount - 3))
        
        """
        
        let startSegment = max(0, segmentCount - 3)
        for i in startSegment..<segmentCount {
            let segmentPath = documentsPath.appendingPathComponent("hls/segment\(i).mp4")
            if FileManager.default.fileExists(atPath: segmentPath.path) {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: segmentPath.path),
                   let fileSize = attributes[.size] as? Int64, fileSize > 1000 {
                    playlist += "#EXTINF:\(segmentDuration),\n"
                    playlist += "segment\(i).mp4\n"
                }
            }
        }
        
        try? playlist.write(to: playlistURL, atomically: true, encoding: .utf8)
        print("🔄 Updated playlist with segments \(startSegment) to \(segmentCount-1)")
    }
}
