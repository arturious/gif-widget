import Cocoa
import UniformTypeIdentifiers

// Custom level for desktop background (sits just below normal windows, but above desktop icons
// so that our window can receive clicks when Cmd is held down)
extension NSWindow.Level {
    static let desktop = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
}

class DragImageView: NSImageView {
    weak var windowRef: NSWindow?
    
    var isLocked: Bool = false {
        didSet {
            UserDefaults.standard.set(isLocked, forKey: "isLocked")
            updateWindowProperties()
        }
    }
    
    func updateWindowProperties() {
        guard let window = windowRef else { return }
        if isLocked {
            window.level = .desktop
        } else {
            let savedLevelRaw = UserDefaults.standard.integer(forKey: "windowLevelRaw")
            if savedLevelRaw != 0 {
                window.level = NSWindow.Level(rawValue: savedLevelRaw)
            } else {
                window.level = .normal
            }
        }
    }
    
    override var mouseDownCanMoveWindow: Bool {
        // Only allow moving window directly if not locked
        return !isLocked
    }
    
    // Crucial: Override hitTest to pass clicks through the window when locked,
    // UNLESS the Command (Cmd) key is held down.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isLocked {
            if NSEvent.modifierFlags.contains(.command) {
                return super.hitTest(point)
            } else {
                return nil // Click passes through
            }
        } else {
            return super.hitTest(point)
        }
    }
    
    // Custom window dragging when locked but Command key is held down
    override func mouseDown(with event: NSEvent) {
        if isLocked && event.modifierFlags.contains(.command) {
            windowRef?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        
        // 1. Lock Widget Toggle
        let lockItem = NSMenuItem(title: "Lock Widget (Cmd+Click to unlock/drag)", action: #selector(toggleLock), keyEquivalent: "")
        lockItem.target = self
        lockItem.state = isLocked ? .on : .off
        menu.addItem(lockItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Choose File
        let chooseFileItem = NSMenuItem(title: "Choose Image/GIF...", action: #selector(chooseFile), keyEquivalent: "o")
        chooseFileItem.target = self
        menu.addItem(chooseFileItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Window Position Submenu (disabled if locked to avoid level conflicts)
        let levelMenu = NSMenu()
        
        let topItem = NSMenuItem(title: "Always on Top", action: #selector(setLevelTop), keyEquivalent: "")
        topItem.target = self
        
        let normalItem = NSMenuItem(title: "Normal Window", action: #selector(setLevelNormal), keyEquivalent: "")
        normalItem.target = self
        
        let desktopItem = NSMenuItem(title: "Below Windows (Desktop)", action: #selector(setLevelDesktopSelf), keyEquivalent: "")
        desktopItem.target = self
        
        if let level = windowRef?.level {
            if level == .floating {
                topItem.state = .on
            } else if level == .normal {
                normalItem.state = .on
            } else if level == .desktop {
                desktopItem.state = .on
            }
        }
        
        levelMenu.addItem(topItem)
        levelMenu.addItem(normalItem)
        levelMenu.addItem(desktopItem)
        
        let levelParent = NSMenuItem(title: "Window Position", action: nil, keyEquivalent: "")
        levelParent.submenu = levelMenu
        levelParent.isEnabled = !isLocked
        menu.addItem(levelParent)
        
        // 4. Opacity Submenu
        let opacityMenu = NSMenu()
        let opacities = [100, 90, 80, 70, 60, 50, 40, 30, 20]
        for percent in opacities {
            let opItem = NSMenuItem(title: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            opItem.target = self
            opItem.tag = percent
            if let window = windowRef {
                let currentPercent = Int(round(window.alphaValue * 100))
                if abs(currentPercent - percent) <= 2 {
                    opItem.state = .on
                }
            }
            opacityMenu.addItem(opItem)
        }
        
        let opacityParent = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityParent.submenu = opacityMenu
        menu.addItem(opacityParent)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Quit
        let quitItem = NSMenuItem(title: "Quit Widget", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc func toggleLock() {
        isLocked = !isLocked
    }
    
    @objc func chooseFile() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showOpenPanel()
        }
    }
    
    @objc func setLevelTop() {
        windowRef?.level = .floating
        UserDefaults.standard.set(NSWindow.Level.floating.rawValue, forKey: "windowLevelRaw")
    }
    
    @objc func setLevelNormal() {
        windowRef?.level = .normal
        UserDefaults.standard.set(NSWindow.Level.normal.rawValue, forKey: "windowLevelRaw")
    }
    
    @objc func setLevelDesktopSelf() {
        windowRef?.level = .desktop
        UserDefaults.standard.set(NSWindow.Level.desktop.rawValue, forKey: "windowLevelRaw")
    }
    
    @objc func setOpacity(_ sender: NSMenuItem) {
        let alpha = CGFloat(sender.tag) / 100.0
        windowRef?.alphaValue = alpha
        UserDefaults.standard.set(Double(alpha), forKey: "opacity")
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

class WidgetWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.level = .normal
        self.isMovableByWindowBackground = true
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: WidgetWindow?
    var imageView: DragImageView?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowWidth: CGFloat = 300
        let windowHeight: CGFloat = 300
        let rect = NSRect(
            x: screenFrame.origin.x + (screenFrame.width - windowWidth) / 2,
            y: screenFrame.origin.y + (screenFrame.height - windowHeight) / 2,
            width: windowWidth,
            height: windowHeight
        )
        
        let win = WidgetWindow(contentRect: rect)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        self.window = win
        
        let view = DragImageView(frame: win.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.windowRef = win
        win.contentView?.addSubview(view)
        self.imageView = view
        
        // Restore window frame if saved
        if let frameString = UserDefaults.standard.string(forKey: "windowFrame") {
            let frame = NSRectFromString(frameString)
            var isOnScreen = false
            for screen in NSScreen.screens {
                if screen.frame.intersects(frame) {
                    isOnScreen = true
                    break
                }
            }
            if isOnScreen {
                win.setFrame(frame, display: true)
            }
        }
        
        // Restore opacity if saved
        let savedOpacity = UserDefaults.standard.double(forKey: "opacity")
        if savedOpacity > 0 {
            win.alphaValue = CGFloat(savedOpacity)
        }
        
        // Restore lock state if saved
        let savedLock = UserDefaults.standard.bool(forKey: "isLocked")
        
        // Load image (either command line or saved or panel)
        let args = CommandLine.arguments
        if args.count > 1 {
            let path = args[1]
            loadImage(from: path)
            view.isLocked = savedLock // Apply lock state after loading
        } else if let savedPath = UserDefaults.standard.string(forKey: "imagePath") {
            loadImage(from: savedPath)
            view.isLocked = savedLock // Apply lock state after loading
        } else {
            DispatchQueue.main.async {
                self.showOpenPanel()
            }
        }
    }
    
    func loadImage(from path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        if let image = NSImage(contentsOfFile: expandedPath) {
            imageView?.image = image
            UserDefaults.standard.set(expandedPath, forKey: "imagePath")
            
            // Adjust size only if we don't have a saved frame
            if UserDefaults.standard.string(forKey: "windowFrame") == nil {
                adjustWindowSize(for: image)
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Failed to load image"
            alert.informativeText = "Could not read image file at:\n\(path)"
            alert.alertStyle = .warning
            alert.runModal()
            
            if imageView?.image == nil {
                showOpenPanel()
            }
        }
    }
    
    func adjustWindowSize(for image: NSImage) {
        guard let window = self.window else { return }
        let size = image.size
        if size.width > 0 && size.height > 0 {
            let aspectRatio = size.width / size.height
            let currentFrame = window.frame
            let targetWidth: CGFloat = 300
            let targetHeight = targetWidth / aspectRatio
            
            window.setFrame(
                NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y + (currentFrame.height - targetHeight),
                    width: targetWidth,
                    height: targetHeight
                ),
                display: true,
                animate: true
            )
        }
    }
    
    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.image]
        panel.level = .modalPanel
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.loadImage(from: url.path)
            } else if self.imageView?.image == nil {
                NSApp.terminate(nil)
            }
        }
    }
    
    // MARK: NSWindowDelegate methods to persist frame
    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }
    
    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
    }
    
    func saveWindowFrame() {
        if let frame = window?.frame {
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: "windowFrame")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
