import AVFoundation
import UIKit
import Network

class SimpleStreamer: ObservableObject {
    private var connections: [NWConnection] = []
    private let boundary = "myboundary"
    private var isObservingFrames = false
    
    func stopStreaming() {
        // Remove notification observer first
        if isObservingFrames {
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("NewSampleBuffer"), object: nil)
            isObservingFrames = false
        }

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
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r

        """.data(using: .utf8)!

        connection.send(content: initialHeader, completion: .contentProcessed { error in
            if let error = error {
                print("❌ Failed to send initial header: \(error)")
            } else {
                print("✅ Initial header sent successfully")
            }
        })

        // Always restart frame observation when adding connections
        if !isObservingFrames {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFrame(_:)),
                name: NSNotification.Name("NewSampleBuffer"),
                object: nil
            )
            isObservingFrames = true
            print("🔄 Restarted frame observation")
        }

        print("📺 Added streaming connection (total: \(connections.count))")
    }

    func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        print("📺 Removed streaming connection (total: \(connections.count))")

        // If no more connections, stop observing frames
        if connections.isEmpty && isObservingFrames {
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("NewSampleBuffer"), object: nil)
            isObservingFrames = false
            print("🛑 Stopped observing frames - no active connections")
        }
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
                print("🗑️ Removing dead connection (state: \(connection.state))")
                return true
            }
            if case .failed(_) = connection.state {
                print("🗑️ Removing dead connection (state: \(connection.state))")
                return true
            }
            
            connection.send(content: frameData, completion: .contentProcessed { error in
                if let error = error {
                    print("❌ Failed to send frame: \(error)")
                }
            })
            return false
        }
    }
}
