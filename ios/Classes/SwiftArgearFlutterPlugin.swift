import Flutter
import UIKit
import CoreMedia
import SceneKit
import AVFoundation
import ARGear
import Foundation

public class SwiftArgearFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        RealmManager.shared.checkAndMigration()
        registrar.register(ARGearViewFactory(messenger: registrar.messenger()), withId: "plugins.flutter.io/argear_flutter")
    }
}

class ARGearViewFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    public func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return ARGearView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger)
    }
    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class ARGearView: NSObject, FlutterPlatformView, ARGSessionDelegate {
    private var _view: UIView!
    
    let channel: FlutterMethodChannel
    var defaultFilterItemId: String
    var apiHost: String
    var apiKey: String
    var apiSecretKey: String
    var apiAuthKey: String
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        channel = FlutterMethodChannel(name: "plugins.flutter.io/argear_flutter/\(viewId)", binaryMessenger: messenger)
        _view = UIView(frame: CGRect(x: 0, y: 0, width: 375.0, height: 667.0))
        defaultFilterItemId = ""
        apiHost = ""
        apiKey = ""
        apiSecretKey = ""
        apiAuthKey = ""

        super.init()
        if let dict = args as? [String: Any] {
            defaultFilterItemId = (dict["defaultFilterItemId"] as? String ?? "")
            apiHost = (dict["apiHost"] as? String ?? "")
            apiKey = (dict["apiKey"] as? String ?? "")
            apiSecretKey = (dict["apiSecretKey"] as? String ?? "")
            apiAuthKey = (dict["apiAuthKey"] as? String ?? "")
        }

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            
						if call.method == "setUp" {
                self.setUp()
                result("ok")
            }
            if call.method == "clearFilter" {
                ContentManager.shared.clearContent()
                result("ok")
            }
            if call.method == "addFilter" {
                self.setContents(itemId: self.defaultFilterItemId)
                result("ok")
            }
            if call.method == "clearBeauty" {
                BeautyManager.shared.off()
                result("ok")
            }
            if call.method == "addBeauty" {
                BeautyManager.shared.setDefault()
                result("ok")
            }
            if call.method == "startVideoRecording" {
                self.startVideoRecording()
                result("ok")
            }
            if call.method == "stopVideoRecording" {
                self.stopVideoRecording()
                result("ok")
            }
            if call.method == "destroy" {
              print("session destroy")
              self.argSession?.destroy()
              result("ok")
            }
        }
    }

    func view() -> UIView {
        return _view
    }
    
    // MARK: - ARGearSDK properties
    private var argSession: ARGSession?
    private var argConfig: ARGConfig?
    private lazy var cameraPreviewCALayer = CALayer()
    private var currentFaceFrame: ARGFrame?
    private var nextFaceFrame: ARGFrame?
    private var preferences: ARGPreferences = ARGPreferences()
    
    // MARK: - Camera & Scene properties
    private let serialQueue = DispatchQueue(label: "serialQueue")
    private var arScene: ARGScene!
    private var arCamera: ARGCamera!
    private var arMedia: ARGMedia = ARGMedia()
    
		private func setUp() {
        setupARGearConfig()
        setupScene()
        setupCamera()
        setupUI()
        
        runARGSession()
        initHelpers()
        connectAPI()
				self.channel.invokeMethod("onSetUpComplete", arguments: [])
    }
    private func runARGSession() {
        argSession?.run()
    }

    private func initHelpers() {
        NetworkManager.shared.argSession = self.argSession
        NetworkManager.shared.apiHost = self.apiHost
        NetworkManager.shared.apiKey = self.apiKey
        BeautyManager.shared.argSession = self.argSession
        ContentManager.shared.argSession = self.argSession
        
        BeautyManager.shared.start()
    }

    // MARK: - connect argear API
    private func connectAPI() {
        NetworkManager.shared.connectAPI { (result: Result<[String: Any], APIError>) in
            switch result {
            case .success(let data):
                RealmManager.shared.setARGearData(data)
            default:
                break
            }
        }
    }
    
    private func setContents(itemId: String?) {
        if let item = RealmManager.shared.getCategories().first?.items.first(where: {$0.uuid == itemId}) {
            ContentManager.shared.setContent(item, successBlock: {}) {}
        } else {
          return
        }
    }
    
    // MARK: - ARGearSDK setupConfig
    private func setupARGearConfig() {
        do {
            let config = ARGConfig(
                apiURL: apiHost,
                apiKey: apiKey,
                secretKey: apiSecretKey,
                authKey: apiAuthKey
            )
            argSession = try ARGSession(argConfig: config, feature: [.faceLowTracking])
            argSession?.delegate = self

            let debugOption: ARGInferenceDebugOption = self.preferences.showLandmark ? .optionDebugFaceLandmark2D : .optionDebugNON
            argSession?.inferenceDebugOption = debugOption
        } catch let error as NSError {
            print("Failed to initialize ARGear Session with error: %@", error.description)
        } catch let exception as NSException {
            print("Exception to initialize ARGear Session with error: %@", exception.description)
        }
    }

    // MARK: - setupScene
    private func setupScene() {
        arScene = ARGScene(viewContainer: _view)

        arScene.sceneRenderUpdateAtTimeHandler = { [weak self] renderer, time in
            guard let self = self else { return }
            self.refreshARFrame()
        }

        arScene.sceneRenderDidRenderSceneHandler = { [weak self] renderer, scene, time in
            guard let _ = self else { return }
        }

        cameraPreviewCALayer.contentsGravity = .resizeAspect//.resizeAspectFill
        cameraPreviewCALayer.frame = CGRect(x: 0, y: 0, width: arScene.sceneView.frame.size.height, height: arScene.sceneView.frame.size.width)
        cameraPreviewCALayer.contentsScale = UIScreen.main.scale
        _view.layer.insertSublayer(cameraPreviewCALayer, at: 0)
    }
    
    // MARK: - ARGearSDK Handling
    private func refreshARFrame() {
        guard self.nextFaceFrame != nil && self.nextFaceFrame != self.currentFaceFrame else { return }
        self.currentFaceFrame = self.nextFaceFrame
    }
    
    private func getPreviewY() -> CGFloat {
        let height43: CGFloat = (self._view.frame.width * 4) / 3
        let height11: CGFloat = self._view.frame.width
        var previewY: CGFloat = 0
        if self.arCamera.ratio == ._1x1 {
            previewY = (height43 - height11)/2 + CGFloat(kRatioViewTopBottomAlign11/2)
        }
        
        if #available(iOS 11.0, *), self.arCamera.ratio != ._16x9 {
            if let topInset = UIApplication.shared.keyWindow?.rootViewController?.view.safeAreaInsets.top {
                if self.arCamera.ratio == ._1x1 {
                    previewY += topInset/2
                } else {
                    previewY += topInset
                }
            }
        }
        
        return previewY
    }
    
    private func pixelbufferToCGImage(_ pixelbuffer: CVPixelBuffer) -> CGImage? {
        let ciimage = CIImage(cvPixelBuffer: pixelbuffer)
        let context = CIContext()
        let cgimage = context.createCGImage(ciimage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelbuffer), height: CVPixelBufferGetHeight(pixelbuffer)))

        return cgimage
    }
    
    private func drawARCameraPreview() {
        guard
            let frame = self.currentFaceFrame,
            let pixelBuffer = frame.renderedPixelBuffer
        else { return }
            
        var flipTransform = CGAffineTransform(scaleX: -1, y: 1)
        if self.arCamera.currentCamera == .back {
            flipTransform = CGAffineTransform(scaleX: 1, y: 1)
        }

        DispatchQueue.main.async {
            CATransaction.flush()
            CATransaction.begin()
            CATransaction.setAnimationDuration(0)
            if #available(iOS 11.0, *) {
                self.cameraPreviewCALayer.contents = pixelBuffer
            } else {
                self.cameraPreviewCALayer.contents = self.pixelbufferToCGImage(pixelBuffer)
            }
            let angleTransform = CGAffineTransform(rotationAngle: .pi/2)
            let transform = angleTransform.concatenating(flipTransform)
            self.cameraPreviewCALayer.setAffineTransform(transform)
            self.cameraPreviewCALayer.frame = CGRect(x: 0, y: -self.getPreviewY(), width: self.cameraPreviewCALayer.frame.size.width, height: self.cameraPreviewCALayer.frame.size.height)
            self._view.backgroundColor = .blue
            CATransaction.commit()
        }
    }

    // MARK: - setupCamera
    private func setupCamera() {
        arCamera = ARGCamera()

        arCamera.sampleBufferHandler = { [weak self] output, sampleBuffer, connection in
            guard let self = self else { return }

            self.serialQueue.async {
                self.argSession?.update(sampleBuffer, from: connection)
            }
        }

        arCamera.metadataObjectsHandler = { [weak self] metadataObjects, connection in
            guard let self = self else { return }

            self.serialQueue.async {
                self.argSession?.update(metadataObjects, from: self.arCamera.cameraConnection!)
            }
        }

        self.arCamera.startCamera()
        self.setCameraInfo()
    }
    
    func setCameraInfo() {
        if let device = arCamera.cameraDevice, let connection = arCamera.cameraConnection {
            self.arMedia.setVideoDevice(device)
            self.arMedia.setVideoDeviceOrientation(connection.videoOrientation)
            self.arMedia.setVideoConnection(connection)
        }
        arMedia.setMediaRatio(arCamera.ratio)
        // arMedia.setVideoBitrate(ARGMediaVideoBitrate(rawValue: self.preferences.videoBitrate) ?? ._4M)
        arMedia.setVideoBitrate(._4M)
    }
    
    // MARK: - UI
    private func setupUI() {
        ARGLoading.prepare()
    }

    private func startVideoRecording() {
      self.arMedia.recordVideoStart { sec in }
    }

    private func stopVideoRecording() {
      self.arMedia.recordVideoStop({ videoInfo in
      }) { resultVideoInfo in
          if let info = resultVideoInfo as? Dictionary<String, Any> {
            let url = info["filePath"] as? NSURL;
            self.channel.invokeMethod("onVideoRecordingComplete", arguments: ["video": url?.absoluteString])
          }
      }
    }
    
    func didUpdate(_ arFrame: ARGFrame) {
        self.drawARCameraPreview()

        nextFaceFrame = arFrame
        
        if #available(iOS 11.0, *) {
        } else {
            self.arScene.sceneView.sceneTime += 1
        }
    }
}
