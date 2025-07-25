# iP-Cam - iOS Network Camera Broadcasting App

<div align="center">
      <img src="(https://github.com/FreQRiDeR/iP-Cam/blob/main/iP-Cam.png)" width="300" />             
      <h1>iP-Cam APP</h1>
</div>
A Swift-based iOS application that turns your iPhone into a network camera, broadcasting audio and video over your local network with browser-based viewing capabilities.

## Features

- **Real-time Video Broadcasting**: Stream camera feed over local network
- **Audio Support**: Broadcast microphone audio alongside video
- **Individual Controls**: Toggle video and audio independently
- **Web Browser Access**: View stream in any modern web browser
- **Protocols**: MJPEG
- **Modern UI**: Clean, intuitive SwiftUI interface
- **Network Discovery**: Automatic local IP address detection

## Protocol

### MJPEG
- Low latency (< 100ms)
- Native browser support
- Best for real-time applications
- No special software required

The app consists of several key components:

1. **CameraManager**: Handles camera setup, permissions, and video/audio capture
2. **BroadcastManager**: Coordinates broadcasting services
3. **HTTPServerManager**: Serves web interface for browser access

## Usage

### Setup
1. Build and run the app on your iOS device
2. Grant camera and microphone permissions when prompted
3. Tap the broadcast button to start streaming
4. Note the displayed URL (e.g., `http://192.168.1.100:8080`)

### Viewing the Stream
1. Open any web browser on a device connected to the same network
2. Navigate to the broadcast URL shown in the app
3. Click "Connect" to establish connection
4. View the live camera feed

### Controls
- **Video Toggle**: Enable/disable video broadcasting
- **Audio Toggle**: Enable/disable audio broadcasting
- **Broadcast Toggle**: Start/stop the broadcast server
- **Settings**: Configure protocol, port, and quality settings

## Technical Details

### Network Ports
- **Port 8080**: HTTP server for web interface

### Permissions Required
- Camera access for video capture
- Microphone access for audio capture
- Local network access for broadcasting

### Browser Compatibility
- Chrome (recommended)
- Firefox
- Safari
- Edge
- Any browser with WebRTC support

## Development

### Requirements
- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+
- HLS.framework

### Building
1. Open `iP-Cam.xcodeproj` in Xcode
2. Select your iOS device as the target
3. Build and run the project

## Security Considerations

- The app only broadcasts on your local network
- Consider firewall settings for production use

## Troubleshooting

### Common Issues
1. **Can't see the stream**: Ensure both devices are on the same network
2. **Permission denied**: Check camera/microphone permissions in Settings
3. **Connection failed**: Verify firewall settings and port availability
4. **Poor quality**: Adjust quality settings in the app

### Network Configuration
- Ensure your router allows local network communication
- Check that ports 8080 is not blocked

## Future Enhancements

- [ ] Multiple camera support
- [ ] Recording capabilities
- [ ] Motion detection
- [ ] Push notifications
- [ ] Cloud storage integration
- [ ] Multi-client support
- [ ] Quality adjustment based on network conditions
- [ ] Authentication system

## License

This project is provided as-is for educational and personal use.

## Contributing

Feel free to submit issues and enhancement requests! 
