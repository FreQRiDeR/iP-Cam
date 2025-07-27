import AVFoundation
import UIKit
import Network

class SimpleStreamer: ObservableObject {
    private var connections: [NWConnection] = []
    private let boundary = "myboundary"
    
    func stopStreaming() {
        // Remove notification observer first
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("NewSampleBuffer"), object: nil)
        
        // Close all connections properly
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        print("🛑 All streaming connections closed")
    }
    
    func addConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        let initialHeader = """
        HTTP/1.1 200 OK\r
        Content-Type: multipart/x-mixed-replace; boundary=\(boundary)\r
        Cache-Control: no-cache, no-store, must-revalidate\r
        Pragma: no-cache\r
        Expires: 0\r
        Connection: close\r
        \r
        
        """.data(using: .utf8)!
        
        connection.send(content: initialHeader, completion: .contentProcessed { _ in })
        
        // Start listening for frame notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrame(_:)),
            name: NSNotification.Name("NewSampleBuffer"),
            object: nil
        )
        
        print("📺 Added streaming connection")
    }
    
    @objc private func handleFrame(_ notification: Notification) {
        guard let sampleBuffer = notification.object,
              CFGetTypeID(sampleBuffer as CFTypeRef) == CMSampleBufferGetTypeID() else { return }
        
        let cmSampleBuffer = sampleBuffer as! CMSampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let image = UIImage(cgImage: cgImage)
        guard let jpegData = image.jpegData(compressionQuality: 0.6) else { return }
        
        let frameHeader = """
        --\(boundary)\r
        Content-Type: image/jpeg\r
        Content-Length: \(jpegData.count)\r
        Cache-Control: no-cache, no-store, must-revalidate\r
        Pragma: no-cache\r
        Expires: 0\r
        \r
        
        """.data(using: .utf8)!
        
        var frameData = Data()
        frameData.append(frameHeader)
        frameData.append(jpegData)
        frameData.append("\r\n".data(using: .utf8)!)
        
        connections.removeAll { connection in
            if connection.state == .cancelled {
                return true
            }
            connection.send(content: frameData, completion: .contentProcessed { _ in })
            return false
        }
    }
}
