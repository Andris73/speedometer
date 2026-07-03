import AVKit
import Combine
import CoreMedia
import SwiftUI
import UIKit

/// Drives a system Picture-in-Picture window showing the live speed.
/// Renders text into CMSampleBuffers fed to an AVSampleBufferDisplayLayer,
/// which AVPictureInPictureController treats as live video content.
final class SpeedPiPManager: NSObject, ObservableObject {
    @Published var isActive = false

    /// Called on the main thread when the user taps play/pause in the PiP
    /// window, with the desired "playing" state.
    var onSetPlaying: ((Bool) -> Void)?

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private let renderSize = CGSize(width: 480, height: 270)
    private var lastFrame: (speed: String, average: String, unit: String) = ("0", "0", "MPH")
    private var rawSpeed: Double = 0
    private var rawAverage: Double = 0
    private var isSessionRunning = false
    private var cancellables: Set<AnyCancellable> = []

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// Host view must be in the window hierarchy (alpha 0 is fine, hidden is not).
    func attach(to hostView: UIView) {
        guard controller == nil, isSupported else { return }

        // Audio session must be active before the controller is created,
        // otherwise PiP won't start. mixWithOthers keeps music/nav audio alive.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)

        displayLayer.frame = CGRect(origin: .zero, size: renderSize)
        displayLayer.videoGravity = .resizeAspect
        hostView.layer.addSublayer(displayLayer)

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        controller = pip

        renderFrame()
    }

    /// Subscribes to the tracker's publishers so PiP frames keep rendering in
    /// the background, independent of SwiftUI view updates. The running state
    /// drives the PiP window's play/pause button icon.
    func bind(
        speed: Published<Double>.Publisher,
        average: Published<Double>.Publisher,
        isRunning: Published<Bool>.Publisher
    ) {
        guard cancellables.isEmpty else { return }
        speed.combineLatest(average)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speed, average in
                self?.rawSpeed = speed
                self?.rawAverage = average
                self?.refresh()
            }
            .store(in: &cancellables)
        isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self, running != self.isSessionRunning else { return }
                self.isSessionRunning = running
                self.controller?.invalidatePlaybackState()
            }
            .store(in: &cancellables)
    }

    func toggle() {
        guard let pip = controller else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            start(pip)
        }
    }

    func refresh() {
        let metric = UserDefaults.standard.bool(forKey: "useMetric")
        let factor = metric ? 1.60934 : 1.0
        let unit = metric ? "KPH" : "MPH"
        lastFrame = (
            speedString(rawSpeed * factor),
            speedString(rawAverage * factor),
            unit
        )
        if isActive {
            renderFrame()
        }
    }

    private func speedString(_ value: Double) -> String {
        String(min(999, max(0, Int(value.rounded()))))
    }

    private func start(_ pip: AVPictureInPictureController) {
        renderFrame()
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
            return
        }
        // Flips true asynchronously after a frame is enqueued; one-shot observer.
        possibleObservation = pip.observe(
            \.isPictureInPicturePossible, options: [.new]
        ) { [weak self] ctrl, _ in
            guard ctrl.isPictureInPicturePossible else { return }
            DispatchQueue.main.async { ctrl.startPictureInPicture() }
            self?.possibleObservation = nil
        }
    }

    private func renderFrame() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.renderFrame() }
            return
        }
        if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
            displayLayer.flush()
        }
        guard let buffer = makeSampleBuffer() else { return }
        displayLayer.enqueue(buffer)
    }

    // MARK: - Frame rendering

    private func makeSampleBuffer() -> CMSampleBuffer? {
        let frame = lastFrame
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: renderSize, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: renderSize))
            let midX = renderSize.width / 2
            var nextY = drawCentered(
                frame.speed,
                font: .monospacedDigitSystemFont(ofSize: 128, weight: .semibold),
                color: .white, midX: midX, top: 18
            )
            nextY = drawCentered(
                frame.unit,
                font: .systemFont(ofSize: 30, weight: .medium),
                color: UIColor.white.withAlphaComponent(0.6), midX: midX, top: nextY - 2
            )
            drawCentered(
                "AVG \(frame.average) \(frame.unit)",
                font: .monospacedDigitSystemFont(ofSize: 24, weight: .regular),
                color: UIColor.white.withAlphaComponent(0.45), midX: midX, top: nextY + 8
            )
        }
        guard let cgImage = image.cgImage else { return nil }
        guard let pixelBuffer = makePixelBuffer(from: cgImage) else { return nil }

        var videoFormat: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &videoFormat
        ) == noErr, let fmt = videoFormat else { return nil }

        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 60)
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: now,
            decodeTimeStamp: now
        )
        guard let buffer = try? CMSampleBuffer(
            imageBuffer: pixelBuffer,
            formatDescription: fmt,
            sampleTiming: timing
        ) else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue!).toOpaque()
            )
        }
        return buffer
    }

    @discardableResult
    private func drawCentered(_ text: String, font: UIFont, color: UIColor, midX: CGFloat, top: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: midX - size.width / 2, y: top))
        return top + size.height
    }

    private func makePixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width), Int(renderSize.height),
            kCVPixelFormatType_32ARGB, attrs, &pixelBuffer
        ) == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(renderSize.width), height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: renderSize))
        return buffer
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension SpeedPiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in
            self?.isActive = true
            self?.renderFrame()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in self?.isActive = false }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        DispatchQueue.main.async { [weak self] in self?.isActive = false }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension SpeedPiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onSetPlaying?(playing)
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // 24h "live" range hides the scrubber; .positiveInfinity triggers an
        // AVKit timer work-queue CPU spin (see uakihir0/UIPiPView#17)
        CMTimeRange(start: .zero, duration: CMTime(value: 3600 * 24, timescale: 1))
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        !isSessionRunning
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        renderFrame()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - SwiftUI host

/// Invisible host that anchors the sample buffer layer in the window hierarchy.
struct PiPHostView: UIViewRepresentable {
    let manager: SpeedPiPManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // Near-zero alpha rather than 0/hidden: some iOS versions refuse to
        // start PiP from a fully invisible layer.
        view.alpha = 0.011
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        manager.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
