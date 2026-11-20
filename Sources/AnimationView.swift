import AppKit
import AVFoundation

final class AnimationView: NSView {
    private let skin: Skin
    let skip = SkipButton(action: {})
    var onIntroEnded: (() -> Void)?
    private(set) var hasMovie = false
    private let poster = CALayer()
    private let video = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var paused = true
    private var inBackground = false
    private var introRate: Float = 1
    private var reducedMotion: Bool

    init(frame: NSRect, skin: Skin, reducedMotion: Bool, duration: Double? = nil, fullPreview: Bool = false) {
        self.skin = skin
        self.reducedMotion = reducedMotion
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.cornerRadius = 12
        if let url = Bundle.main.url(forResource: "poster", withExtension: "jpg", subdirectory: skin.rawValue),
           let image = NSImage(contentsOf: url) {
            poster.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        poster.contentsGravity = .resizeAspectFill
        layer?.addSublayer(poster)
        video.videoGravity = .resizeAspect
        video.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(video)
        video.isHidden = true
        addSubview(skip)
        if !reducedMotion, let url = Bundle.main.url(forResource: fullPreview ? "full_preview" : "intro", withExtension: "mp4", subdirectory: skin.rawValue) {
            let item = AVPlayerItem(url: url)
            player.actionAtItemEnd = .pause
            player.volume = 0.55
            player.replaceCurrentItem(with: item)
            video.player = player
            video.isHidden = false
            hasMovie = true
            introRate = fullPreview ? 1 : Float(skin.filmDuration / min(skin.filmDuration, max(2, duration ?? skin.filmDuration)))
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                object: item, queue: .main) { [weak self] _ in
                    self?.onIntroEnded?()
                }
            failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item, queue: .main) { [weak self] _ in
                    self?.hasMovie = false
                    self?.video.isHidden = true
                    self?.onIntroEnded?()
                }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        poster.frame = bounds
        video.frame = bounds
        CATransaction.commit()
        skip.frame = NSRect(x: bounds.width - 105, y: bounds.height - 44, width: 88, height: 26)
    }

    func pause(_ pause: Bool) {
        paused = pause
        if pause { player.pause() }
        else if hasMovie { player.playImmediately(atRate: inBackground ? 1 : introRate) }
    }

    func replay() {
        guard hasMovie, !inBackground else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.pause(self?.window?.isVisible != true) }
        }
    }

    func enterBackground() {
        skip.isHidden = true
        inBackground = true
        player.isMuted = true
        guard !reducedMotion, let url = Bundle.main.url(forResource: "loop", withExtension: "mp4", subdirectory: skin.rawValue) else { return }
        player.removeAllItems()
        player.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        // Fill the panel during the translucent ambient loop.
        video.videoGravity = .resizeAspectFill
        pause(paused)
    }

    func silence() { player.isMuted = true }

    deinit {
        player.pause()
        looper?.disableLooping()
        for token in [endObserver, failureObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
