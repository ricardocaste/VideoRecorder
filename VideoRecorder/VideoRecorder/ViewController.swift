//
//  ViewController.swift
//  VideoRecorder
//
//  Created by Ricardo Castellanos Herreros on 4/7/18.
//  Copyright © 2018 Ricardo Castellanos Herreros. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation
import Photos

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var camPreview: UIView!
    
    let cameraButton = UIView()
    let captureSession = AVCaptureSession()
    
    lazy var lastSampleTime: CMTime = {
        let lastSampleTime = kCMTimeZero
        return lastSampleTime
    }()
    
    var uiImages = [UIImage]()
    
    
    //Output
    let videoDataOutput = AVCaptureVideoDataOutput()
    
    var previewLayer: AVCaptureVideoPreviewLayer!
    var videoConnection: AVCaptureConnection!
    var activeInput: AVCaptureDeviceInput!
    var outputURL: URL!
    
    var startTime:CMTime? = nil
    var assetWriter:AVAssetWriter? = nil
    var assetWriterVideoInput:AVAssetWriterInput? = nil
    
    var isRecording = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if setupSession() {
            setupPreview()
            startSession()
        }
        
        cameraButton.isUserInteractionEnabled = true
        let cameraButtonRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.startCapture))
        cameraButton.addGestureRecognizer(cameraButtonRecognizer)
        cameraButton.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        cameraButton.backgroundColor = UIColor.red
        camPreview.addSubview(cameraButton)
        
        do{
            try createWriter(assetURL: documentsURL()!)
        }catch {
            print("ERROR createWriter")
        }
    }
    
    private func createWriter(assetURL: URL) throws {
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: (documentsURL()?.absoluteString)!) {
            print("WARN:::The file: \((documentsURL()?.absoluteString)!) exists, will delete the existing file")
            do {
                try fileManager.removeItem(at: documentsURL()!)
            } catch let error as NSError {
                print("WARN:::Cannot delete existing file: \((documentsURL()?.absoluteString)!), error: \(error.debugDescription)")
            }
        } else {
            print("DEBUG:::The file \((documentsURL()?.absoluteString)!) not exists")
        }
        
        // AVVideoAverageBitRateKey is for pecifying a key to access the average bit rate (as bits per second) used in encoding.
        // This video shoule be video size * a float number, and here 10.1 is equal to AVCaptureSessionPresetHigh.
        let videoCompressionPropertys = [
            AVVideoAverageBitRateKey: camPreview.bounds.width * camPreview.bounds.height * 10.1
        ]
        
        let videoSettings: [String: AnyObject] = [
            AVVideoCodecKey: AVVideoCodecType.h264 as AnyObject,
            AVVideoWidthKey: camPreview.bounds.width as AnyObject,
            AVVideoHeightKey: camPreview.bounds.height as AnyObject,
            AVVideoCompressionPropertiesKey:videoCompressionPropertys as AnyObject
        ]
        
        assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings)
        assetWriterVideoInput!.expectsMediaDataInRealTime = true
        
        do {
            assetWriter = try AVAssetWriter(url:assetURL, fileType:AVFileTypeMPEG4)
        } catch let error as NSError {
            print("ERROR:::::>>>>>>>>>>>>>Cannot init videoWriter, error:\(error.localizedDescription)")
        }
        
        // Set this to make sure that a functional movie is produced, even if the recording is cut off mid-stream. Only the last second should be lost in that case.
        assetWriter?.movieFragmentInterval = CMTimeMakeWithSeconds(1.0, 1000)
        
        if (assetWriter?.canAdd(assetWriterVideoInput!))! {
            assetWriter?.add(assetWriterVideoInput!)
        } else {
            print("ERROR:::Cannot add videoWriterInput into videoWriter")
        }
    }
    
    func setupPreview() {
        // Configure previewLayer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = camPreview.bounds
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        camPreview.layer.addSublayer(previewLayer)
    }
    
    
    //MARK:- Setup Camera
    
    func setupSession() -> Bool {
        
        captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        // Setup Camera
        let camera = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        do {
            let input = try AVCaptureDeviceInput(device: camera!)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                activeInput = input
            }
        } catch {
            print("Error setting device video input: \(error)")
            return false
        }
        
        //Output
        if captureSession.canAddOutput(videoDataOutput){
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String: NSNumber(value: kCVPixelFormatType_32BGRA)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            let queue = DispatchQueue(label: "videosamplequeue")
            videoDataOutput.setSampleBufferDelegate(self, queue: queue)
            guard captureSession.canAddOutput(videoDataOutput) else {
                fatalError()
            }
            
            captureSession.addOutput(videoDataOutput)
            
            videoConnection = videoDataOutput.connection(withMediaType:AVMediaTypeVideo)
        }
        
        
        return true
    }
    
    func setupCaptureMode(_ mode: Int) {
        // Video Mode
        
    }
    
    //MARK:- Camera Session
    func startSession() {
        
        
        if !captureSession.isRunning {
            videoQueue().async {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        if captureSession.isRunning {
            videoQueue().async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func videoQueue() -> DispatchQueue {
        return DispatchQueue.main
    }
    
    
    @objc func startCapture() {
        
        startRecording()
        
    }
    
    func documentsURL() -> URL?
    {
        let directory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        
        if directory != "" {
            let path = directory.appendingPathComponent("video.mp4")
            return URL(fileURLWithPath: path)
        }
        
        return nil
    }
    
    
    
    func startRecording()
    {
        if(!self.isRecording)
        {
            if assetWriter!.status != AVAssetWriterStatus.writing {
                
                print("DEBUG::::::::::::::::The videoWriter status is not writing, and will start writing the video.")
                
                let hasStartedWriting = assetWriter!.startWriting()
                if hasStartedWriting {
                    assetWriter!.startSession(atSourceTime: self.lastSampleTime)
                    self.isRecording = true
                    print("DEBUG:::Have started writting on videoWriter, session at source time: \(self.lastSampleTime)")
                } else {
                    print("WARN:::Fail to start writing on videoWriter")
                }
            } else {
                print("WARN:::The videoWriter.status is writting now, so cannot start writing action on videoWriter")
            }
            
        }
        else
        {
            stopRecording()
        }
        
    }
    
    func stopRecording()
    {
        self.isRecording = false
        
        self.assetWriterVideoInput?.markAsFinished()
        assetWriter!.finishWriting {
            
            if self.assetWriter!.status == AVAssetWriterStatus.completed {
                print("DEBUG:::The videoWriter status is completed")
                
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath:(self.documentsURL()?.absoluteString)!) {
                    print("DEBUG:::The file: \((self.documentsURL()?.absoluteString)!) has been save into documents folder, and is ready to be moved to camera roll")
                    
                    
                    PHPhotoLibrary.requestAuthorization { status in
                        guard status == .authorized else { return }
                        
                        PHPhotoLibrary.shared().performChanges({
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.documentsURL()!)
                        }) { completed, error in
                            if completed {
                                print("Video \((self.documentsURL()?.absoluteString)!) has been moved to camera roll")
                            }
                            
                            if error != nil {
                                print ("ERROR:::Cannot move the video \((self.documentsURL()?.absoluteString)!) to camera roll, error: \(error!.localizedDescription)")
                            }
                        }
                    }
                } else {
                    print("ERROR:::The file: \((self.documentsURL()?.absoluteString)!) not exists, so cannot move this file camera roll")
                }
            } else {
                print("WARN:::The videoWriter status is not completed, stauts: \(self.assetWriter!.status)")
            }
        }
        
        let settings = CXEImagesToVideo.videoSettings(codec: AVVideoCodecType.h264.rawValue, width: (Int(uiImages[0].size.width)), height: (Int(uiImages[0].size.height)))
        let movieMaker = CXEImagesToVideo(videoSettings: settings, url: documentsURL()!)
        
        
        movieMaker.createMovieFrom(images: uiImages){ (fileURL:URL) in
            let video = AVAsset(url: fileURL)
            
            if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fileURL.absoluteString) {
                UISaveVideoAtPathToSavedPhotosAlbum(fileURL.absoluteString, nil, nil, nil)
                print("Video \((self.documentsURL()?.absoluteString)!) has been moved to camera roll")
            }
        }
    }
    
    //Use this function to convert CIImage to UIImage
    func toUIImage(image: CIImage) -> UIImage {
        
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(image, from: image.extent)!
        let newimage:UIImage = UIImage.init(cgImage: cgImage)
        return newimage
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
        //Save
        guard isRecording else { return }
        
        
        if (assetWriterVideoInput?.isReadyForMoreMediaData)! {
            
            if assetWriter!.status == AVAssetWriterStatus.writing {
                let whetherAppendSampleBuffer = assetWriterVideoInput!.append(sampleBuffer)
                
                if whetherAppendSampleBuffer {
                    print("DEBUG::: Append sample buffer successfully")
                } else {
                    print("WARN::: Append sample buffer failed")
                }
            } else {
                print("WARN:::The videoWriter status is not writing")
            }
            
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer!)
        uiImages.append(toUIImage(image: ciImage))
    }
}
