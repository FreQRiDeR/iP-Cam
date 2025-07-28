import Foundation
import Network

class HTTPServerManager: ObservableObject {
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []
    private var streamingConnections: [NWConnection] = []
    private let streamer = SimpleStreamer()
    private var isServerRunning = false
    
    var localIPAddress: String {
        var address = "localhost"
        
        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }
        
        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                
                // Check interface name:
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" || name == "pdp_ip0" || name == "pdp_ip1" {
                    
                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        
        print("🌐 Local IP Address: \(address)")
        return address
    }
    
    func startServer() {
        print("🚀 HTTPServerManager.startServer() called")
        
        // If server is already running, stop it first
        if isServerRunning {
            stopServer()
            // Wait for complete shutdown before restarting
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.startActualServer()
            }
        } else {
            // Reset streamer state for fresh start
            streamer.stopStreaming()
            startActualServer()
        }
    }

    private func startActualServer() {
        print("🔧 Creating server parameters...")
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            print("🔧 Creating listener on port 8080...")
            listener = try NWListener(using: parameters, on: 8080)
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        print("✅ Server READY on port 8080")
                        print("🌐 Access at: http://\(self?.localIPAddress ?? "unknown"):8080")
                        self?.isServerRunning = true
                    case .failed(let error):
                        print("❌ Server FAILED: \(error)")
                        self?.isServerRunning = false
                    case .cancelled:
                        print("🛑 Server CANCELLED")
                        self?.isServerRunning = false
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
            isServerRunning = false
        }
    }
    
    func stopServer() {
        print("🛑 Stopping HTTP Server...")
        isServerRunning = false

        // Stop the streamer first
        streamer.stopStreaming()

        // Force close all connections immediately
        for connection in activeConnections {
            connection.forceCancel()
        }
        activeConnections.removeAll()
        streamingConnections.removeAll()

        // Cancel listener
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil

        print("✅ HTTP Server stopped completely")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            print("📡 Connection state: \(state)")
            if case .cancelled = state {
                self?.activeConnections.removeAll { $0 === connection }
                self?.streamingConnections.removeAll { $0 === connection }
                self?.streamer.removeConnection(connection)
            } else if case .failed(_) = state {
                self?.activeConnections.removeAll { $0 === connection }
                self?.streamingConnections.removeAll { $0 === connection }
                self?.streamer.removeConnection(connection)
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("❌ Receive error: \(error)")
                self?.activeConnections.removeAll { $0 === connection }
                if self?.streamingConnections.contains(where: { $0 === connection }) == true {
                    self?.streamingConnections.removeAll { $0 === connection }
                    self?.streamer.removeConnection(connection)
                }
                return
            }

            if let data = data, !data.isEmpty {
                print("📥 Received request: \(data.count) bytes")
                if let request = String(data: data, encoding: .utf8) {
                    print("📄 Request: \(request.prefix(200))")
                }
                self?.handleHTTPRequest(data: data, connection: connection)
            }

            // Only close connection if it's complete AND not a streaming connection
            if isComplete && !(self?.streamingConnections.contains { $0 === connection } ?? false) {
                connection.cancel()
                self?.activeConnections.removeAll { $0 === connection }
            }
        }
    }
    
    private func handleHTTPRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else { return }
        
        handleRequest(request, connection: connection)
    }

    private func handleRequest(_ request: String, connection: NWConnection) {
        print("📥 Request: \(request.prefix(100))")

        if request.contains("GET / ") {
            serveMainPage(connection)
        } else if request.contains("GET /stream") {
            handleMJPEGStream(connection)
        } else if request.contains("GET /health") {
            handleHealthCheck(connection)
        } else if request.contains("GET /status") {
            handleStatusRequest(connection)
        } else if request.contains("POST /settings/resolution") {
            handleResolutionChange(request, connection: connection)
        } else if request.contains("POST /settings/video") {
            handleVideoToggle(connection)
        } else if request.contains("POST /settings/audio") {
            handleAudioToggle(connection)
        } else if request.contains("POST /settings/recording") {
            handleRecordingToggle(connection)
        } else {
            send404(connection)
        }
    }

    private func handleMJPEGStream(_ connection: NWConnection) {
        print("📺 Starting MJPEG stream for connection")
        // Mark this connection as a streaming connection
        streamingConnections.append(connection)
        streamer.addConnection(connection)
    }

    private func handleHealthCheck(_ connection: NWConnection) {
        let healthData: [String: Any] = [
            "status": "ok",
            "activeConnections": activeConnections.count,
            "streamingConnections": streamingConnections.count,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendJSONResponse(healthData, connection: connection)
    }

    private func handleHLSRequest(_ request: String, connection: NWConnection) {
        let components = request.components(separatedBy: " ")
        guard components.count >= 2 else {
            send404(connection)
            return
        }
        
        let path = components[1]
        let fileName = String(path.dropFirst(5)) // Remove "/hls/"
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent("hls/\(fileName)")
        
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            send404(connection)
            return
        }
        
        do {
            let fileData = try Data(contentsOf: filePath)
            let contentType = fileName.hasSuffix(".m3u8") ? "application/x-mpegURL" : 
                             fileName.hasSuffix(".ts") ? "video/mp2t" : "video/mp4"
            
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: \(contentType)\r
            Content-Length: \(fileData.count)\r
            Access-Control-Allow-Origin: *\r
            Cache-Control: no-cache\r
            \r
            
            """.data(using: .utf8)!
            
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.send(content: fileData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            })
            
        } catch {
            send404(connection)
        }
    }

    private func send404(_ connection: NWConnection) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: response.data(using: .utf8)!, completion: .contentProcessed { _ in
            connection.cancel()
        })
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

    private func handleResolutionChange(_ request: String, connection: NWConnection) {
        if let body = extractRequestBody(request),
           let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let resolution = json["resolution"] {
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ChangeResolution"), 
                    object: resolution
                )
            }
        }
        sendJSONResponse(["status": "ok"], connection: connection)
    }

    private func handleVideoToggle(_ connection: NWConnection) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ToggleVideo"), object: nil)
        }
        sendJSONResponse(["status": "ok"], connection: connection)
    }

    private func handleAudioToggle(_ connection: NWConnection) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ToggleAudio"), object: nil)
        }
        sendJSONResponse(["status": "ok"], connection: connection)
    }

    private func handleRecordingToggle(_ connection: NWConnection) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ToggleRecording"), object: nil)
        }
        sendJSONResponse(["status": "ok"], connection: connection)
    }

    private func handleStatusRequest(_ connection: NWConnection) {
        // Return current app status as JSON
        let status: [String: Any] = [
            "videoEnabled": true, // Get from CameraManager
            "audioEnabled": true, // Get from CameraManager
            "resolution": "HD (720p)" // Get from CameraManager
        ]
        sendJSONResponse(status, connection: connection)
    }

    private func sendJSONResponse(_ data: [String: Any], connection: NWConnection) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(jsonData.count)\r\n\r\n"
            var responseData = response.data(using: .utf8)!
            responseData.append(jsonData)
            
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            send404(connection)
        }
    }

    private func serveMainPage(_ connection: NWConnection) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>iP-Cam</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background: #222;
                    color: white;
                    font-family: Arial, sans-serif;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    min-height: 100vh;
                }
                h1 { margin: 10px 0; color: white; font-size: 1.5em; }
                .video-container {
                    position: relative;
                    width: 90vw;
                    height: 70vh;
                    background: black;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    border-radius: 8px;
                    overflow: hidden;
                }
                #video {
                    max-width: 100%;
                    max-height: 100%;
                    width: auto;
                    height: auto;
                    object-fit: contain;
                    display: block;
                }
                
                /* Disable image caching */
                img {
                    image-rendering: -webkit-optimize-contrast;
                }
                
                /* Disable image caching */
                img {
                    image-rendering: -webkit-optimize-contrast;
                }
                .settings {
                    display: flex;
                    gap: 15px;
                    margin: 15px 0;
                    align-items: center;
                    flex-wrap: wrap;
                    justify-content: center;
                }
                .controls {
                    display: flex;
                    gap: 15px;
                    margin: 15px 0;
                    align-items: center;
                }
                .control-btn, select {
                    background: #444;
                    border: none;
                    color: white;
                    padding: 10px 15px;
                    border-radius: 5px;
                    cursor: pointer;
                    font-size: 14px;
                }
                .control-btn:hover, select:hover { background: #666; }
                .control-btn:active { background: #888; }
                .control-btn.active { background: #0a84ff; }
                .control-btn.inactive { background: #666; opacity: 0.6; }
                .control-btn.recording { background: #ff0000; }
                .status {
                    color: #0f0;
                    font-weight: bold;
                }
                .fullscreen-container {
                    position: relative;
                    cursor: pointer;
                }
                .fullscreen-container:hover {
                    opacity: 0.95;
                }
                .fullscreen-container:-webkit-full-screen {
                    background: black;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    width: 100vw;
                    height: 100vh;
                }
                .fullscreen-container:-webkit-full-screen .video-container {
                    width: 100vw !important;
                    height: 100vh !important;
                    max-width: none !important;
                    max-height: none !important;
                    border-radius: 0 !important;
                }
                .fullscreen-container:-webkit-full-screen #video,
                .fullscreen-container:-moz-full-screen #video,
                .fullscreen-container:fullscreen #video {
                    max-width: 100vw !important;
                    max-height: 100vh !important;
                    width: auto !important;
                    height: auto !important;
                    object-fit: contain !important;
                }
                .fullscreen-container:-moz-full-screen {
                    background: black;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    width: 100vw;
                    height: 100vh;
                }
                .fullscreen-container:-moz-full-screen .video-container {
                    width: 100vw !important;
                    height: 100vh !important;
                    max-width: none !important;
                    max-height: none !important;
                    border-radius: 0 !important;
                }
                .fullscreen-container:-moz-full-screen #video {
                    width: 100% !important;
                    height: 100% !important;
                    object-fit: contain !important;
                }
                .fullscreen-container:fullscreen {
                    background: black;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    width: 100vw;
                    height: 100vh;
                }
                .fullscreen-container:fullscreen .video-container {
                    width: 100vw !important;
                    height: 100vh !important;
                    max-width: none !important;
                    max-height: none !important;
                    border-radius: 0 !important;
                }
                .fullscreen-container:fullscreen #video {
                    width: 100% !important;
                    height: 100% !important;
                    object-fit: contain !important;
                }
            </style>
        </head>
        <body>
            <h1>iP-Cam Live Stream</h1>
            <div class="fullscreen-container" id="fullscreen-container" ondblclick="toggleFullscreen()" title="Double-click for fullscreen">
                <div class="video-container">
                    <img id="video" src="/stream" alt="Live Stream">
                </div>
            </div>
            
            <div class="settings">
                <select id="resolution" onchange="changeResolution()">
                    <option value="Low (480p)">480p</option>
                    <option value="Medium (720p)">720p</option>
                    <option value="HD (720p)" selected>HD 720p</option>
                    <option value="Full HD (1080p)">1080p</option>
                    <option value="4K (2160p)">4K</option>
                </select>
                <button class="control-btn active" onclick="toggleVideo()" id="videoBtn">Video</button>
                <button class="control-btn active" onclick="toggleAudio()" id="audioBtn">Audio ON</button>
                <button class="control-btn inactive" onclick="toggleRecording()" id="recordBtn">Record OFF</button>
            </div>
            
            <div class="controls">
                <button class="control-btn" onclick="refreshStream()">Refresh</button>
                <button class="control-btn" onclick="toggleFullscreen()" id="fullscreenBtn">Fullscreen</button>
                <span class="status" id="status">LIVE</span>
            </div>
            
            <script>
                let videoEnabled = true;
                let audioEnabled = true;
                let recordingEnabled = false;
                let videoPaused = false;
                let reconnectInterval;
                let isReconnecting = false;
                let reconnectAttempts = 0;
                
                const video = document.getElementById('video');
                const status = document.getElementById('status');
                const videoBtn = document.getElementById('videoBtn');
                const audioBtn = document.getElementById('audioBtn');
                const recordBtn = document.getElementById('recordBtn');
                
                function startReconnecting() {
                    if (isReconnecting || videoPaused) return;
                    isReconnecting = true;
                    reconnectAttempts = 0;

                    status.textContent = 'RECONNECTING...';
                    status.style.color = '#ff0';

                    reconnectInterval = setInterval(() => {
                        // Don't reconnect if video is paused
                        if (videoPaused) {
                            stopReconnecting();
                            status.textContent = 'PAUSED';
                            status.style.color = '#ff0';
                            return;
                        }

                        reconnectAttempts++;
                        console.log('Reconnect attempt:', reconnectAttempts);

                        // Clear the src first to force a new connection
                        video.src = '';

                        // Add a small delay before setting new src
                        setTimeout(() => {
                            video.src = '/stream?t=' + Date.now() + '&attempt=' + reconnectAttempts;
                        }, 100);

                        // Stop trying after 10 attempts
                        if (reconnectAttempts >= 10) {
                            stopReconnecting();
                            status.textContent = 'CONNECTION FAILED';
                            status.style.color = '#f00';
                        }
                    }, 2000);
                }
                
                function stopReconnecting() {
                    if (reconnectInterval) {
                        clearInterval(reconnectInterval);
                        reconnectInterval = null;
                    }
                    isReconnecting = false;
                    reconnectAttempts = 0;
                    status.textContent = 'LIVE';
                    status.style.color = '#0f0';
                }
                
                function changeResolution() {
                    const resolution = document.getElementById('resolution').value;
                    fetch('/settings/resolution', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({resolution: resolution})
                    }).then(() => {
                        setTimeout(() => refreshStream(), 500);
                    });
                }
                
                function toggleVideo() {
                    fetch('/settings/video', {method: 'POST'})
                    .then(() => {
                        videoEnabled = !videoEnabled;
                        videoBtn.textContent = videoEnabled ? 'Video' : 'Video OFF';
                        videoBtn.className = videoEnabled ? 'control-btn active' : 'control-btn inactive';
                    });
                }
                
                function toggleAudio() {
                    fetch('/settings/audio', {method: 'POST'})
                    .then(() => {
                        audioEnabled = !audioEnabled;
                        audioBtn.textContent = audioEnabled ? 'Audio ON' : 'Audio OFF';
                        audioBtn.className = audioEnabled ? 'control-btn active' : 'control-btn inactive';
                    });
                }
                
                function toggleRecording() {
                    fetch('/settings/recording', {method: 'POST'})
                    .then(() => {
                        recordingEnabled = !recordingEnabled;
                        recordBtn.textContent = recordingEnabled ? 'Record ON' : 'Record OFF';
                        recordBtn.className = recordingEnabled ? 'control-btn recording' : 'control-btn inactive';
                    });
                }
                
                function refreshStream() {
                    stopReconnecting();

                    // Don't refresh if video is paused
                    if (videoPaused) {
                        console.log('Video is paused, not refreshing stream');
                        return;
                    }

                    // Force cache bypass
                    video.src = '';
                    setTimeout(() => {
                        video.src = '/stream?t=' + Date.now() + '&refresh=1';
                    }, 100);
                }
                
                function toggleFullscreen() {
                    console.log('Fullscreen toggle requested');
                    const container = document.getElementById('fullscreen-container');

                    if (!container) {
                        console.error('Fullscreen container not found');
                        return;
                    }

                    // Check if already in fullscreen
                    const isFullscreen = !!(document.fullscreenElement ||
                                           document.webkitFullscreenElement ||
                                           document.mozFullScreenElement ||
                                           document.msFullscreenElement);

                    console.log('Currently in fullscreen:', isFullscreen);

                    if (!isFullscreen) {
                        // Enter fullscreen
                        let promise;
                        if (container.requestFullscreen) {
                            promise = container.requestFullscreen();
                        } else if (container.webkitRequestFullscreen) {
                            promise = container.webkitRequestFullscreen();
                        } else if (container.mozRequestFullScreen) {
                            promise = container.mozRequestFullScreen();
                        } else if (container.msRequestFullscreen) {
                            promise = container.msRequestFullscreen();
                        } else {
                            console.error('Fullscreen API not supported');
                            alert('Fullscreen is not supported in this browser');
                            return;
                        }

                        // Handle promise if returned
                        if (promise && promise.catch) {
                            promise.catch(err => {
                                console.error('Failed to enter fullscreen:', err);
                                alert('Failed to enter fullscreen: ' + err.message);
                            });
                        }
                    } else {
                        // Exit fullscreen
                        if (document.exitFullscreen) {
                            document.exitFullscreen().catch(err => {
                                console.error('Failed to exit fullscreen:', err);
                            });
                        } else if (document.webkitExitFullscreen) {
                            document.webkitExitFullscreen();
                        } else if (document.mozCancelFullScreen) {
                            document.mozCancelFullScreen();
                        } else if (document.msExitFullscreen) {
                            document.msExitFullscreen();
                        }
                    }
                }
                
                video.onerror = function(e) {
                    console.log('Video error:', e);
                    if (!isReconnecting) {
                        startReconnecting();
                    }
                };

                video.onload = function() {
                    console.log('Video loaded successfully');
                    stopReconnecting();
                };

                video.addEventListener('load', function() {
                    console.log('Video load event');
                    stopReconnecting();
                });

                // Add additional event listeners for better connection monitoring
                video.addEventListener('loadstart', function() {
                    console.log('Video load started');
                });

                video.addEventListener('loadeddata', function() {
                    console.log('Video data loaded');
                    stopReconnecting();
                });

                video.addEventListener('abort', function() {
                    console.log('Video load aborted');
                    if (!isReconnecting) {
                        startReconnecting();
                    }
                });
                
                // Check fullscreen support on load
                function checkFullscreenSupport() {
                    const container = document.getElementById('fullscreen-container');
                    const fullscreenBtn = document.getElementById('fullscreenBtn');

                    const isSupported = !!(container.requestFullscreen ||
                                          container.webkitRequestFullscreen ||
                                          container.mozRequestFullScreen ||
                                          container.msRequestFullscreen);

                    if (!isSupported) {
                        fullscreenBtn.textContent = 'Fullscreen (Not Supported)';
                        fullscreenBtn.disabled = true;
                        fullscreenBtn.style.opacity = '0.5';
                        console.warn('Fullscreen API not supported in this browser');
                    } else {
                        console.log('Fullscreen API supported');
                    }

                    return isSupported;
                }

                // Force initial load
                window.addEventListener('load', function() {
                    refreshStream();
                    checkFullscreenSupport();
                });

                // Fullscreen event listeners
                document.addEventListener('fullscreenchange', function() {
                    console.log('Fullscreen changed:', !!document.fullscreenElement);
                });

                document.addEventListener('webkitfullscreenchange', function() {
                    console.log('Webkit fullscreen changed:', !!document.webkitFullscreenElement);
                });

                document.addEventListener('mozfullscreenchange', function() {
                    console.log('Mozilla fullscreen changed:', !!document.mozFullScreenElement);
                });

                document.addEventListener('msfullscreenchange', function() {
                    console.log('MS fullscreen changed:', !!document.msFullscreenElement);
                });

                // Fullscreen error listeners
                document.addEventListener('fullscreenerror', function(e) {
                    console.error('Fullscreen error:', e);
                    alert('Fullscreen failed: ' + e.message);
                });

                document.addEventListener('webkitfullscreenerror', function(e) {
                    console.error('Webkit fullscreen error:', e);
                    alert('Fullscreen failed');
                });

                document.addEventListener('mozfullscreenerror', function(e) {
                    console.error('Mozilla fullscreen error:', e);
                    alert('Fullscreen failed');
                });

                document.addEventListener('msfullscreenerror', function(e) {
                    console.error('MS fullscreen error:', e);
                    alert('Fullscreen failed');
                });
                
                // Keyboard shortcuts
                document.addEventListener('keydown', function(e) {
                    if (e.key === 'f' || e.key === 'F') {
                        toggleFullscreen();
                    } else if (e.key === 'r' || e.key === 'R') {
                        refreshStream();
                    } else if (e.key === 'v' || e.key === 'V') {
                        toggleVideo();
                    } else if (e.key === 'a' || e.key === 'A') {
                        toggleAudio();
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
    }

    private func extractRequestBody(_ request: String) -> String? {
        let components = request.components(separatedBy: "\r\n\r\n")
        return components.count > 1 ? components[1] : nil
    }
}
