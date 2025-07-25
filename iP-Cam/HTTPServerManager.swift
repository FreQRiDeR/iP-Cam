import Foundation
import Network

class HTTPServerManager: ObservableObject {
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var streamer = SimpleStreamer()
    private var activeConnections: [NWConnection] = []
    
    deinit {
        stopServer()
    }
    
    var localIPAddress: String {
        let ip = getLocalIPAddress() ?? "localhost"
        print("🌐 Local IP Address: \(ip)")
        return ip
    }
    
    func startServer() {
        stopServer() // Ensure clean start
        
        // Trigger local network permission prompt FIRST
        triggerLocalNetworkPermission()
        
        // Add a small delay to let permission prompt appear
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.startActualServer()
        }
    }

    private func startActualServer() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: 8080)
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        print("✅ Server READY on port 8080")
                        print("🌐 Access at: http://\(self?.localIPAddress ?? "unknown"):8080")
                    case .failed(let error):
                        print("❌ Server FAILED: \(error)")
                    case .cancelled:
                        print("🛑 Server CANCELLED")
                    default:
                        print("📡 Server state: \(state)")
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("🔗 NEW CONNECTION from \(connection.endpoint)")
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
            print("🚀 Starting HTTP server on port 8080...")
            
        } catch {
            print("❌ Failed to create listener: \(error)")
        }
    }
    
    func stopServer() {
        // Close all active connections first
        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        
        // Stop the streamer
        streamer.stopStreaming()
        
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        print("HTTP Server stopped")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            print("📡 Connection state: \(state)")
            if case .cancelled = state {
                self?.activeConnections.removeAll { $0 === connection }
            } else if case .failed(_) = state {
                self?.activeConnections.removeAll { $0 === connection }
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("❌ Receive error: \(error)")
                self?.activeConnections.removeAll { $0 === connection }
                return
            }
            
            if let data = data, !data.isEmpty {
                print("📥 Received request: \(data.count) bytes")
                if let request = String(data: data, encoding: .utf8) {
                    print("📄 Request: \(request.prefix(200))")
                }
                self?.handleHTTPRequest(data: data, connection: connection)
            }
            
            if isComplete {
                connection.cancel()
                self?.activeConnections.removeAll { $0 === connection }
            }
        }
    }
    
    private func handleHTTPRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else { return }
        
        if request.contains("GET / ") {
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>iP-Cam</title>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes, minimum-scale=0.5, maximum-scale=3.0">
                <style>
                    body {
                        margin: 0;
                        padding: 20px;
                        background: #555;
                        color: white;
                        font-family: Arial, sans-serif;
                        display: flex;
                        flex-direction: column;
                        align-items: center;
                        justify-content: center;
                        min-height: 100vh;
                        zoom: 1;
                    }
                    h1 {
                        margin-bottom: 20px;
                        color: white;
                    }
                    .video-container {
                        position: relative;
                        width: 90%;
                        max-width: 90vw;
                        max-height: 80vh;
                        display: inline-block;
                    }
                    #stream {
                        width: 100%;
                        height: auto;
                        max-height: 80vh;
                        border: 2px solid #333;
                        border-radius: 8px;
                        cursor: pointer;
                        transform: rotate(0deg);
                        object-fit: contain;
                    }
                    #stream.fullscreen {
                        position: fixed;
                        top: 0;
                        left: 0;
                        width: 100vw;
                        height: 100vh;
                        object-fit: contain;
                        z-index: 9999;
                        border: none;
                        border-radius: 0;
                        transform: none;
                    }
                    .fullscreen-btn {
                        position: absolute;
                        bottom: 10px;
                        right: 10px;
                        background: rgba(0, 0, 0, 0.7);
                        color: white;
                        border: none;
                        padding: 8px 10px;
                        border-radius: 4px;
                        cursor: pointer;
                        font-size: 14px;
                        z-index: 10;
                        font-family: monospace;
                    }
                    .fullscreen-btn:hover {
                        background: rgba(0, 0, 0, 0.9);
                    }
                    .fullscreen-btn.in-fullscreen {
                        position: fixed;
                        bottom: 20px;
                        right: 20px;
                        z-index: 10000;
                    }
                </style>
            </head>
            <body>
                <h1>iP-Cam</h1>
                <div class="video-container">
                    <img id="stream" src="/stream" onclick="toggleFullscreen()">
                    <button class="fullscreen-btn" id="fullscreenBtn" onclick="toggleFullscreen()">⛶</button>
                </div>
                
                <script>
                    function toggleFullscreen() {
                        const img = document.getElementById('stream');
                        const btn = document.getElementById('fullscreenBtn');
                        
                        if (img.classList.contains('fullscreen')) {
                            img.classList.remove('fullscreen');
                            btn.classList.remove('in-fullscreen');
                            btn.innerHTML = '⛶';
                            document.exitFullscreen?.();
                        } else {
                            img.classList.add('fullscreen');
                            btn.classList.add('in-fullscreen');
                            btn.innerHTML = '⛷';
                            img.requestFullscreen?.();
                        }
                    }

                    document.addEventListener('keydown', function(e) {
                        if (e.key === 'Escape') {
                            const img = document.getElementById('stream');
                            const btn = document.getElementById('fullscreenBtn');
                            img.classList.remove('fullscreen');
                            btn.classList.remove('in-fullscreen');
                            btn.innerHTML = '⛶';
                        }
                    });
                </script>
            </body>
            </html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.count)\r\n\r\n\(html)"
            connection.send(content: response.data(using: .utf8)!, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else if request.contains("GET /stream") {
            streamer.addConnection(connection)
        } else {
            let response = "HTTP/1.1 404 Not Found\r\n\r\n"
            connection.send(content: response.data(using: .utf8)!, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
    
    private func triggerLocalNetworkPermission() {
        // Method 1: Try to bind to a multicast address
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        
        do {
            let listener = try NWListener(using: parameters, on: 8081)
            listener.start(queue: .global())
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                listener.cancel()
            }
        } catch {
            print("Failed to create UDP listener for permission: \(error)")
        }
        
        // Method 2: Bonjour browser
        let browserParameters = NWParameters()
        browserParameters.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: browserParameters)
        browser?.browseResultsChangedHandler = { _, _ in }
        browser?.start(queue: .global())
        
        // Stop after a short delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            self.browser?.cancel()
            self.browser = nil
        }
    }
}
