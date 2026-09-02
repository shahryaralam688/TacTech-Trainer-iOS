import AVFoundation
import Combine
import SwiftUI
import Vision

struct PoseFeedback {
    var cue: String
    var score: Int
    var repCount: Int
    var joints: [CGPoint]
}

final class PoseAnalyzer: NSObject, ObservableObject {
    @Published var feedback = PoseFeedback(cue: "Step into frame", score: 0, repCount: 0, joints: [])
    @Published var cameraAuthorized = false
    @Published var sessionRunning = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "tactech.pose")
    private var lastHipY: CGFloat = 0.5
    private var goingDown = false
    private var reps = 0
    private var scores: [Int] = []
    var exerciseId: String = "ex-squat"

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            configureIfNeeded()
            queue.async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.async { self?.sessionRunning = true }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraAuthorized = granted
                    if granted { self?.start() }
                }
            }
        default:
            cameraAuthorized = false
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.sessionRunning = false }
        }
    }

    func snapshotReport() -> (score: Int, cues: [String], reps: Int) {
        let score = scores.isEmpty ? feedback.score : scores.reduce(0, +) / scores.count
        return (score, [feedback.cue], reps)
    }

    private var configured = false
    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        output.connection(with: .video)?.isVideoMirrored = true
        session.commitConfiguration()
    }
}

extension PoseAnalyzer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
        guard let observation = request.results?.first else {
            publish(PoseFeedback(cue: "I can’t see you yet", score: 0, repCount: reps, joints: []))
            return
        }
        analyze(observation)
    }

    private func analyze(_ observation: VNHumanBodyPoseObservation) {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let recognized = try? observation.recognizedPoint(joint), recognized.confidence > 0.3 else { return nil }
            return CGPoint(x: recognized.location.x, y: 1 - recognized.location.y)
        }

        let joints = [
            point(.leftShoulder), point(.rightShoulder),
            point(.leftHip), point(.rightHip),
            point(.leftKnee), point(.rightKnee),
            point(.leftAnkle), point(.rightAnkle)
        ].compactMap { $0 }

        guard
            let leftHip = try? observation.recognizedPoint(.leftHip),
            let leftKnee = try? observation.recognizedPoint(.leftKnee),
            let leftAnkle = try? observation.recognizedPoint(.leftAnkle),
            let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
            leftHip.confidence > 0.3, leftKnee.confidence > 0.3
        else {
            publish(PoseFeedback(cue: "Show your full body", score: 40, repCount: reps, joints: joints))
            return
        }

        let kneeAngle = angle(leftHip.location, leftKnee.location, leftAnkle.location)
        let hipY = CGFloat(leftHip.location.y)
        let torsoLean = abs(leftShoulder.location.x - leftHip.location.x)

        var cue = "Good form"
        var score = 90

        switch exerciseId {
        case "ex-squat", "ex-lunge":
            if kneeAngle > 150 {
                cue = "Sit the hips back"
                score = 70
            } else if kneeAngle > 100 {
                cue = "Go deeper"
                score = 78
            } else if torsoLean > 0.12 {
                cue = "Keep your back straight"
                score = 72
            } else {
                cue = "Good depth"
                score = 92
            }
            countRep(currentY: hipY, downThreshold: 0.08)
        case "ex-pushup", "ex-plank":
            if torsoLean > 0.16 {
                cue = "Keep your back straight"
                score = 68
            } else if kneeAngle < 150 {
                cue = "Straighten the legs"
                score = 74
            } else {
                cue = "Strong lockout"
                score = 90
            }
        default:
            if torsoLean > 0.14 {
                cue = "Stay stacked"
                score = 76
            } else {
                cue = "Nice control"
                score = 88
            }
        }

        scores.append(score)
        if scores.count > 40 { scores.removeFirst() }
        publish(PoseFeedback(cue: cue, score: score, repCount: reps, joints: joints))
    }

    private func countRep(currentY: CGFloat, downThreshold: CGFloat) {
        if !goingDown && lastHipY - currentY > downThreshold {
            goingDown = true
        } else if goingDown && currentY - lastHipY > downThreshold {
            goingDown = false
            reps += 1
        }
        lastHipY = currentY
    }

    private func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag = sqrt(v1.dx * v1.dx + v1.dy * v1.dy) * sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        guard mag > 0 else { return 180 }
        return acos(max(min(dot / mag, 1), -1)) * 180 / .pi
    }

    private func publish(_ value: PoseFeedback) {
        DispatchQueue.main.async { self.feedback = value }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
