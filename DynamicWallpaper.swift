// DynamicWallpaper.swift
// macOS 动态壁纸工具：把 MP4 铺满桌面作为背景层播放
// 编译: xcrun swiftc -O DynamicWallpaper.swift -o DynamicWallpaper
//
// 用法:
//   DynamicWallpaper                    使用默认目录第一个 mp4
//   DynamicWallpaper /path/to/video.mp4  指定视频
//   DynamicWallpaper --dir /path         指定目录（配合 --shuffle 轮播）
//   DynamicWallpaper --shuffle           目录内视频随机轮播
//   DynamicWallpaper --no-autostart      不写入登录项

import Cocoa
import AVFoundation
import CoreMedia

// MARK: - 配置

enum Config {
    static let defaultDir = NSHomeDirectory() + "/Movies/动态壁纸"
    static let defaultsKey = "DynamicWallpaperConfig"
}

// MARK: - 背景层窗口

final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override var isFloatingPanel: Bool { true }

    init(screen: NSScreen) {
        let frame = screen.frame
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isMovable = false
        isMovableByWindowBackground = false
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        // 层级：桌面壁纸(-2147483623) < 视频窗口 < 桌面图标(-2147483603) < 普通窗口(0)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 10)
        setFrame(frame, display: true)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
}

// MARK: - 视频播放器视图

final class VideoView: NSView {
    var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var syncTimer: Timer?
    private var looper: AVPlayerLooper?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { teardown() }

    func load(url: URL) {
        teardown()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let p = AVQueuePlayer()
        p.isMuted = true
        p.actionAtItemEnd = .none
        player = p

        let l = AVPlayerLayer(player: p)
        l.videoGravity = .resizeAspectFill
        l.frame = bounds
        layer?.addSublayer(l)
        playerLayer = l

        looper = AVPlayerLooper(player: p, templateItem: item)
        p.play()

        // 定期同步 layer 尺寸（应对多屏/缩放/分辨率变化）
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.syncLayer()
        }
        if let t = syncTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func syncLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    func teardown() {
        player?.pause()
        player = nil
        looper = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        syncTimer?.invalidate()
        syncTimer = nil
    }
}

// MARK: - 应用主体

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [WallpaperWindow] = []
    private var views: [VideoView] = []
    private var statusItem: NSStatusItem?
    private var statusTitle: String = ""
    private var infoItem: NSMenuItem?
    private var videoMenu: NSMenu?
    private var pickItemRef: NSMenuItem?
    private var pauseItemRef: NSMenuItem?
    private var shuffleItemRef: NSMenuItem?
    private var autoItemRef: NSMenuItem?

    private var videoDir: String = Config.defaultDir
    private var playlist: [URL] = []
    private var currentIndex: Int = 0
    private var shuffle: Bool = false
    private var shuffleTimer: Timer?
    private var playing: Bool = true
    private var lastVideo: String = ""
    private var debugMode: Bool = false
    private var lockFD: Int32 = -1
    private var logHandle: FileHandle?

    // MARK: 单实例锁

    /// 用 flock 保证只有一个实例在跑；LaunchAgent 与手动启动不会冲突
    private func acquireSingleInstanceLock() -> Bool {
        let path = NSTemporaryDirectory() + "com.local.dynamicwallpaper.lock"
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        if fd < 0 { return true }   // 拿不到锁文件就不阻塞启动
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }

    // MARK: 日志

    /// 同时写到 stderr 和日志文件。用 `open -a` 启动时 stderr 不可见，
    /// 只有文件日志能反映启动失败原因。
    static var logPath: String {
        NSHomeDirectory() + "/Library/Logs/macos-video-wallpaper.log"
    }

    private func setupLog() {
        let path = Self.logPath
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: path, contents: nil)
        logHandle = FileHandle(forWritingAtPath: path)
    }

    private func log(_ s: String) {
        guard let data = (s + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
        logHandle?.write(data)
    }

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupLog()
        guard acquireSingleInstanceLock() else {
            log("已有实例在运行，退出")
            NSApp.terminate(nil)
            return
        }
        loadConfig()
        parseArgs()
        loadPlaylist()
        guard !playlist.isEmpty else {
            log("未找到视频文件，目录: \(videoDir)")
            NSApp.terminate(nil)
            return
        }
        log("启动: \(playlist.count) 个视频, 当前 \(playlist[currentIndex].lastPathComponent), shuffle=\(shuffle)")
        buildWindows()
        buildMenuBar()
        playCurrent()
        if shuffle { startShuffle() }
        if debugMode { startDebugMonitor() }
    }

    /// 输出播放状态，用于验证视频确实在推进
    private func startDebugMonitor() {
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let p = self.views.first?.player else { return }
            let cm = CMTimeGetSeconds(p.currentTime())
            let status = p.timeControlStatus == .playing ? "playing" :
                (p.timeControlStatus == .waitingToPlayAtSpecifiedRate ? "waiting" : "paused")
            self.log("[debug] t=\(String(format: "%.2f", cm))s status=\(status) rate=\(p.rate)")
        }
        RunLoop.main.add(t, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        views.forEach { $0.teardown() }
        shuffleTimer?.invalidate()
    }

    // MARK: 配置文件

    /// 配置文件路径。用于 `open -a` 启动时传递参数——
    /// macOS 26+ 的 `open --args` 会丢弃参数，只能靠文件传参。
    static var configPath: String {
        NSHomeDirectory() + "/Library/Application Support/macos-video-wallpaper/config.json"
    }

    private func loadConfig() {
        guard let data = FileManager.default.contents(atPath: Self.configPath),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        if let f = obj["file"] as? String, !f.isEmpty {
            let p = (f as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: p) {
                playlist = [URL(fileURLWithPath: p)]
                videoDir = (p as NSString).deletingLastPathComponent
            }
        }
        if let d = obj["dir"] as? String, !d.isEmpty {
            videoDir = (d as NSString).expandingTildeInPath
        }
        if let s = obj["shuffle"] as? Bool { shuffle = s }
        if let dbg = obj["debug"] as? Bool { debugMode = dbg }
    }

    // MARK: 命令行参数
    // 优先级：命令行 > 配置文件 > 默认值

    private func parseArgs() {
        let args = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--dir":
                if i + 1 < args.count { videoDir = args[i + 1]; i += 1 }
            case "--shuffle":
                shuffle = true
            case "--no-autostart":
                UserDefaults.standard.set(false, forKey: "DynamicWallpaperAutostart")
            case "--debug":
                debugMode = true
            default:
                // 裸路径参数视为单个视频
                let p = (a as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: p) {
                    playlist = [URL(fileURLWithPath: p)]
                    videoDir = (p as NSString).deletingLastPathComponent
                }
            }
            i += 1
        }
    }

    private func loadPlaylist() {
        if !playlist.isEmpty { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: videoDir) else { return }
        let mp4s = items
            .filter { $0.lowercased().hasSuffix(".mp4") || $0.lowercased().hasSuffix(".mov") || $0.lowercased().hasSuffix(".m4v") }
            .filter { !$0.hasPrefix("._") && !$0.hasPrefix(".") }
            .sorted()
        playlist = mp4s.map { URL(fileURLWithPath: videoDir).appendingPathComponent($0) }
    }

    // MARK: 窗口

    private func buildWindows() {
        for screen in NSScreen.screens {
            let win = WallpaperWindow(screen: screen)
            win.orderBack(nil)

            let v = VideoView(frame: screen.frame)
            v.autoresizingMask = [.width, .height]
            win.contentView = v

            windows.append(win)
            views.append(v)
        }
    }

    private func playCurrent() {
        guard playlist.indices.contains(currentIndex) else { return }
        let url = playlist[currentIndex]
        lastVideo = url.path
        views.forEach { $0.load(url: url) }
        refreshMenuStates()
    }

    private func nextVideo(manual: Bool = false) {
        guard !playlist.isEmpty else { return }
        if shuffle {
            var next = currentIndex
            while next == currentIndex && playlist.count > 1 {
                next = Int.random(in: 0..<playlist.count)
            }
            currentIndex = next
        } else {
            currentIndex = (currentIndex + 1) % playlist.count
        }
        playCurrent()
        if manual { stopShuffle() }
    }

    private func startShuffle() {
        stopShuffle()
        shuffleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.nextVideo()
        }
        if let t = shuffleTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func stopShuffle() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
    }

    // MARK: 菜单栏

    private func buildMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            btn.image = NSImage(systemSymbolName: "film.fill", accessibilityDescription: "动态壁纸")
            btn.image?.isTemplate = true
        }

        let menu = NSMenu()

        // 当前视频信息（不可点）
        let info = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        infoItem = info
        menu.addItem(.separator())

        // 切换视频（子菜单，内容动态刷新）
        videoMenu = NSMenu()
        let pickItem = NSMenuItem(title: "切换视频", action: nil, keyEquivalent: "")
        pickItem.submenu = videoMenu
        menu.addItem(pickItem)
        pickItemRef = pickItem

        let nextItem = NSMenuItem(title: "下一个视频", action: #selector(next), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)

        let browseItem = NSMenuItem(title: "浏览其他视频…", action: #selector(pickVideo), keyEquivalent: "")
        browseItem.target = self
        menu.addItem(browseItem)

        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: "暂停播放", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        pauseItemRef = pauseItem

        let shuffleItem = NSMenuItem(title: "每 30 秒随机切换", action: #selector(toggleShuffle), keyEquivalent: "")
        shuffleItem.target = self
        menu.addItem(shuffleItem)
        shuffleItemRef = shuffleItem

        let autoItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleAutostart), keyEquivalent: "")
        autoItem.target = self
        menu.addItem(autoItem)
        autoItemRef = autoItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "关闭动态壁纸", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item

        refreshVideoSubmenu()
        refreshMenuStates()
    }

    /// 只在播放列表变化时重建子菜单项
    private func refreshVideoSubmenu() {
        guard let videoMenu else { return }
        videoMenu.removeAllItems()
        for (i, url) in playlist.enumerated() {
            let it = NSMenuItem(title: url.lastPathComponent, action: #selector(selectVideo(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = (i == currentIndex) ? .on : .off
            videoMenu.addItem(it)
        }
        pickItemRef?.isEnabled = playlist.count > 1
    }

    /// 原地更新菜单状态，不重建菜单对象
    private func refreshMenuStates() {
        let name = playlist.indices.contains(currentIndex) ? playlist[currentIndex].lastPathComponent : ""
        statusTitle = name.isEmpty ? "动态壁纸" : "当前: \(name)"
        infoItem?.title = statusTitle
        statusItem?.button?.toolTip = statusTitle

        pauseItemRef?.title = playing ? "暂停播放" : "继续播放"
        shuffleItemRef?.state = shuffle ? .on : .off
        autoItemRef?.state = UserDefaults.standard.bool(forKey: "DynamicWallpaperAutostart") ? .on : .off

        // 同步子菜单勾选
        if let items = videoMenu?.items {
            for (i, it) in items.enumerated() {
                it.state = (i == currentIndex) ? .on : .off
            }
        }
    }

    // MARK: 动作

    @objc private func selectVideo(_ sender: NSMenuItem) {
        currentIndex = sender.tag
        playCurrent()
        stopShuffle()
    }

    @objc private func next() {
        nextVideo(manual: true)
    }

    @objc private func togglePause() {
        playing = !playing
        if playing {
            playCurrent()
        } else {
            views.forEach { $0.teardown() }
        }
        refreshMenuStates()
    }

    @objc private func toggleShuffle() {
        shuffle = !shuffle
        if shuffle { startShuffle() } else { stopShuffle() }
        refreshMenuStates()
    }

    @objc private func toggleAutostart() {
        let enabled = !UserDefaults.standard.bool(forKey: "DynamicWallpaperAutostart")
        UserDefaults.standard.set(enabled, forKey: "DynamicWallpaperAutostart")
        setAutoStart(enabled)
        refreshMenuStates()
    }

    @objc private func pickVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: videoDir)
        if panel.runModal() == .OK, let url = panel.url {
            if let idx = playlist.firstIndex(of: url) {
                currentIndex = idx
            } else {
                playlist.append(url)
                currentIndex = playlist.count - 1
            }
            playCurrent()
            refreshVideoSubmenu()
            stopShuffle()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: 开机启动

    private func setAutoStart(_ enable: Bool) {
        let label = "com.local.dynamicwallpaper.autostart"
        let appPath = "/Applications/DynamicWallpaper.app"

        if enable {
            // 通过 launchctl 直接启动 .app 的可执行文件
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(label)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appPath)/Contents/MacOS/DynamicWallpaper</string>
                    <string>--shuffle</string>
                </array>
                <key>RunAtLoad</key><true/>
                <key>LimitLoadToSessionType</key><string>Aqua</string>
            </dict>
            </plist>
            """
            let path = NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try? plist.write(toFile: path, atomically: true, encoding: .utf8)
            _ = run("/bin/launchctl", ["load", "-w", path])
        } else {
            let path = NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
            _ = run("/bin/launchctl", ["unload", "-w", path])
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @discardableResult
    private func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
