import Flutter
import UIKit
import CoreMedia
import SceneKit
import AVFoundation
import ARGear
import Foundation

public class SwiftArgearFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
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
                self.argSession?.contents?.clear(.sticker)
                result("ok")
            }
            if call.method == "addFilter" {
              if let args = call.arguments as? [String: Any],
                  let cacheFilePath = args["cacheFilePath"] as? String,
                  let itemId = args["itemId"] as? String {
                  self.setContents(cacheFilePath: cacheFilePath, itemId: itemId)
              }
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
            if call.method == "downloadItem" {
                self.downloadItem()
                result("ok")
            }
						if call.method == "start" {
              self.argSession?.run()
              result("ok")
            }
            if call.method == "pause" {
              self.argSession?.pause()
              result("ok")
            }
            if call.method == "destroy" {
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
        
        argSession?.run()
        BeautyManager.shared.argSession = self.argSession
        BeautyManager.shared.start()
        self.channel.invokeMethod("onSetUpComplete", arguments: [])
    }

    private func downloadItem() {
      guard let session = self.argSession, let auth = session.auth
          else { return }

      let authCallback : ARGAuthCallback = {(url: String?, code: ARGStatusCode) in
          if (code.rawValue == ARGStatusCode.SUCCESS.rawValue) {
              guard let url = url else { return }

              let authUrl = URL(string: url)!
              let task = URLSession.shared.downloadTask(with: authUrl) { (downloadUrl, response, error) in
                  if error != nil {
                      return
                  }

                  guard
                      let httpResponse = response as? HTTPURLResponse,
                      let response = response,
                      let downloadUrl = downloadUrl
                      else { return }

                  if httpResponse.statusCode == 200 {
                      guard
                          var cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .allDomainsMask).first,
                          let suggestedFilename = response.suggestedFilename
                          else { return }
                      cachesDirectory.appendPathComponent(suggestedFilename)

                      let fileManager = FileManager.default
                      // remove
                      do {
                          try fileManager.removeItem(at: cachesDirectory)
                      } catch {
                      }
                      // copy
                      do {
                          try fileManager.copyItem(at: downloadUrl, to: cachesDirectory)
                      } catch {
                          return
                      }
                      self.channel.invokeMethod("onDownloadItemComplete", arguments: ["zipFileName": suggestedFilename])
                  }
              }
              task.resume()
          } else {
            return
          }
      }
      let zipUrl = "https://privatecontent.argear.io/contents/data/" + self.defaultFilterItemId + ".zip";

      auth.requestSignedUrl(withUrl: zipUrl, itemTitle: "faded", itemType: "filter", completion: authCallback)
  }
    
    private func setContents(cacheFilePath: String, itemId: String) {
        self.argSession?.contents?.setItemWith(.sticker, withItemFilePath: cacheFilePath, withItemID: itemId)
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

        cameraPreviewCALayer.contentsGravity = .resizeAspectFill
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
            previewY = (height43 - height11)/2 + CGFloat(32)
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
        arMedia.setVideoBitrate(._4M)
    }
    
    private func startVideoRecording() {
      var prevSec: CGFloat = 0.0
      self.arMedia.recordVideoStart { sec in
          if (prevSec == 0.0) {
              prevSec = 0.1
              self.channel.invokeMethod("onVideoRecording", arguments: ["sec": prevSec])
          }
          if (prevSec != sec.rounded(.down)) {
              prevSec = sec.rounded(.down)
              self.channel.invokeMethod("onVideoRecording", arguments: ["sec": prevSec])
          }
      }
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
