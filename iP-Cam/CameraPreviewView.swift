import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.updatePreviewLayer()
    }
}

class PreviewView: UIView {
    var session: AVCaptureSession? {
        didSet {
            previewLayer.session = session
        }
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupPreviewLayer()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPreviewLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPreviewLayer()
    }
    
    private func setupPreviewLayer() {
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewLayer()
    }
    
    func updatePreviewLayer() {
        previewLayer.frame = bounds
        updateOrientation()
    }
    
    @objc private func orientationChanged() {
        DispatchQueue.main.async {
            self.updatePreviewLayer()
        }
    }
    
    private func updateOrientation() {
        guard let connection = previewLayer.connection else { return }
        
        let deviceOrientation = UIDevice.current.orientation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch deviceOrientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeRight
        case .landscapeRight:
            videoOrientation = .landscapeLeft
        default:
            videoOrientation = .portrait
        }
        
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
