import Cocoa
import UniformTypeIdentifiers

// Custom level for desktop background (sits just below normal windows, but above desktop icons
// so that our window can receive clicks when Cmd is held down)
extension NSWindow.Level {
    static let desktop = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
}

struct Config {
    var imagePath: String?
    var opacity: Double?
    var isLocked: Bool?
    var x: CGFloat?
    var y: CGFloat?
    var width: CGFloat?
    var shouldReset = false
    var widgetId: String?
}

// Global variables
var globalConfig = Config()
var widgetId: String = "default"

func getPrefKey(_ key: String) -> String {
    return "\(key)_\(widgetId)"
}

func printHelp() {
    print("""
    gifwidget - Lightweight desktop GIF and image widget for macOS
    
    Usage:
      gifwidget [options] [image_path]
    
    Options:
      -h, --help           Show this help message and exit
      -p, --path <path>    Path to the GIF or image file
      -o, --opacity <val>  Opacity level (0.2 to 1.0, e.g. 0.8)
      -l, --lock           Start in locked mode (click-through, below windows)
      -u, --unlock         Start in unlocked mode (draggable, normal window level)
      -x <value>           Initial X position of the widget (origin at bottom-left)
      -y <value>           Initial Y position of the widget (origin at bottom-left)
      -w, --width <value>  Initial width of the widget
      --id <id>            Start widget with a specific ID (for running multiple widgets)
      --reset              Clear saved settings and start fresh
    
    Interacting with Locked Widget:
      Hold the Command (Cmd / ⌘) key while dragging or right-clicking to move/unlock.
    """)
}

func parseArguments() -> Config {
    let args = CommandLine.arguments
    var config = Config()
    
    var idx = 1
    while idx < args.count {
        let arg = args[idx]
        switch arg {
        case "-h", "--help":
            printHelp()
            exit(0)
        case "-p", "--path":
            if idx + 1 < args.count {
                config.imagePath = args[idx + 1]
                idx += 2
            } else {
                print("Error: Missing path after \(arg)")
                exit(1)
            }
        case "-o", "--opacity":
            if idx + 1 < args.count, let val = Double(args[idx + 1]), val >= 0.2, val <= 1.0 {
                config.opacity = val
                idx += 2
            } else {
                print("Error: Opacity must be a number between 0.2 and 1.0")
                exit(1)
            }
        case "-l", "--lock":
            config.isLocked = true
            idx += 1
        case "-u", "--unlock":
            config.isLocked = false
            idx += 1
        case "-x":
            if idx + 1 < args.count, let val = Double(args[idx + 1]) {
                config.x = CGFloat(val)
                idx += 2
            } else {
                print("Error: Missing or invalid value for -x")
                exit(1)
            }
        case "-y":
            if idx + 1 < args.count, let val = Double(args[idx + 1]) {
                config.y = CGFloat(val)
                idx += 2
            } else {
                print("Error: Missing or invalid value for -y")
                exit(1)
            }
        case "-w", "--width":
            if idx + 1 < args.count, let val = Double(args[idx + 1]), val > 0 {
                config.width = CGFloat(val)
                idx += 2
            } else {
                print("Error: Missing or invalid value for --width")
                exit(1)
            }
        case "--id":
            if idx + 1 < args.count {
                config.widgetId = args[idx + 1]
                idx += 2
            } else {
                print("Error: Missing value after --id")
                exit(1)
            }
        case "--reset":
            config.shouldReset = true
            idx += 1
        default:
            if !arg.hasPrefix("-") {
                config.imagePath = arg
                idx += 1
            } else {
                print("Error: Unknown argument \(arg)")
                printHelp()
                exit(1)
            }
        }
    }
    return config
}

globalConfig = parseArguments()
if let id = globalConfig.widgetId {
    widgetId = id
}

class DragImageView: NSImageView {
    weak var windowRef: NSWindow?
    
    var isLocked: Bool = false {
        didSet {
            UserDefaults.standard.set(isLocked, forKey: getPrefKey("isLocked"))
            updateWindowProperties()
        }
    }
    
    func updateWindowProperties() {
        guard let window = windowRef else { return }
        window.level = isLocked ? .desktop : .normal
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return !isLocked
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isLocked {
            if NSEvent.modifierFlags.contains(.command) {
                return super.hitTest(point)
            } else {
                return nil
            }
        } else {
            return super.hitTest(point)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if isLocked && event.modifierFlags.contains(.command) {
            windowRef?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        
        // 1. Lock / Unlock Toggle
        let lockItem = NSMenuItem(title: isLocked ? "Unlock" : "Lock", action: #selector(toggleLock), keyEquivalent: "")
        lockItem.target = self
        if #available(macOS 11.0, *) {
            lockItem.image = NSImage(systemSymbolName: isLocked ? "lock.open.fill" : "lock.fill", accessibilityDescription: nil)
        }
        menu.addItem(lockItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Choose Image/GIF
        let chooseFileItem = NSMenuItem(title: "Choose image/GIF...", action: #selector(chooseFile), keyEquivalent: "o")
        chooseFileItem.target = self
        menu.addItem(chooseFileItem)
        
        // New Widget
        let newWidgetItem = NSMenuItem(title: "New Widget", action: #selector(createNewWidget), keyEquivalent: "n")
        newWidgetItem.keyEquivalentModifierMask = .command
        newWidgetItem.target = self
        if #available(macOS 11.0, *) {
            newWidgetItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        }
        menu.addItem(newWidgetItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Size Submenu (Increase/Decrease/Reset)
        let sizeMenu = NSMenu()
        
        let increaseItem = NSMenuItem(title: "Increase (+)", action: #selector(increaseSize), keyEquivalent: "=")
        increaseItem.keyEquivalentModifierMask = .command
        increaseItem.target = self
        
        let decreaseItem = NSMenuItem(title: "Decrease (-)", action: #selector(decreaseSize), keyEquivalent: "-")
        decreaseItem.keyEquivalentModifierMask = .command
        decreaseItem.target = self
        
        let resetSizeItem = NSMenuItem(title: "Reset Size", action: #selector(resetSize), keyEquivalent: "0")
        resetSizeItem.keyEquivalentModifierMask = .command
        resetSizeItem.target = self
        
        if #available(macOS 11.0, *) {
            increaseItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            decreaseItem.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)
            resetSizeItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        }
        
        sizeMenu.addItem(increaseItem)
        sizeMenu.addItem(decreaseItem)
        sizeMenu.addItem(resetSizeItem)
        
        let sizeParent = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeParent.submenu = sizeMenu
        menu.addItem(sizeParent)
        
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
        
        // 5. Quit & Quit All
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        let quitAllItem = NSMenuItem(title: "Quit All", action: #selector(quitAllApp), keyEquivalent: "q")
        quitAllItem.keyEquivalentModifierMask = [.command, .shift]
        quitAllItem.target = self
        menu.addItem(quitAllItem)
        
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
    
    @objc func createNewWidget() {
        let newId = String(Int(Date().timeIntervalSince1970))
        let exePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        
        // Add newId to active widget IDs list
        var activeIds = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs") ?? ["default"]
        if !activeIds.contains(newId) {
            activeIds.append(newId)
            UserDefaults.standard.set(activeIds, forKey: "activeWidgetIDs")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = ["--id", newId]
        
        try? process.run()
    }
    
    @objc func increaseSize() {
        guard let window = windowRef else { return }
        let currentFrame = window.frame
        let newWidth = currentFrame.width * 1.1
        let newHeight = currentFrame.height * 1.1
        
        let dx = (currentFrame.width - newWidth) / 2
        let dy = (currentFrame.height - newHeight) / 2
        
        let newFrame = NSRect(
            x: currentFrame.origin.x + dx,
            y: currentFrame.origin.y + dy,
            width: newWidth,
            height: newHeight
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    @objc func decreaseSize() {
        guard let window = windowRef else { return }
        let currentFrame = window.frame
        let newWidth = max(50, currentFrame.width * 0.9)
        let newHeight = max(50, currentFrame.height * 0.9)
        
        let dx = (currentFrame.width - newWidth) / 2
        let dy = (currentFrame.height - newHeight) / 2
        
        let newFrame = NSRect(
            x: currentFrame.origin.x + dx,
            y: currentFrame.origin.y + dy,
            width: newWidth,
            height: newHeight
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    @objc func resetSize() {
        guard let image = self.image else { return }
        let size = image.size
        if size.width > 0 && size.height > 0 {
            let aspectRatio = size.width / size.height
            guard let window = windowRef else { return }
            let currentFrame = window.frame
            let targetWidth: CGFloat = 300
            let targetHeight = targetWidth / aspectRatio
            
            let dx = (currentFrame.width - targetWidth) / 2
            let dy = (currentFrame.height - targetHeight) / 2
            
            let newFrame = NSRect(
                x: currentFrame.origin.x + dx,
                y: currentFrame.origin.y + dy,
                width: targetWidth,
                height: targetHeight
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }
    
    @objc func setOpacity(_ sender: NSMenuItem) {
        let alpha = CGFloat(sender.tag) / 100.0
        windowRef?.alphaValue = alpha
        UserDefaults.standard.set(Double(alpha), forKey: getPrefKey("opacity"))
    }
    
    @objc func quitApp() {
        // Remove this widget from active IDs list if not default
        if widgetId != "default" {
            var activeIds = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs") ?? ["default"]
            if let index = activeIds.firstIndex(of: widgetId) {
                activeIds.remove(at: index)
                UserDefaults.standard.set(activeIds, forKey: "activeWidgetIDs")
            }
        }
        NSApp.terminate(nil)
    }
    
    @objc func quitAllApp() {
        // Reset active IDs list to just default
        UserDefaults.standard.set(["default"], forKey: "activeWidgetIDs")
        
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if app.bundleIdentifier == Bundle.main.bundleIdentifier || app.localizedName == "gifwidget" {
                if app.processIdentifier != currentPid {
                    app.terminate()
                }
            }
        }
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
        
        // Handle --reset flag
        if globalConfig.shouldReset {
            let activeIds = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs") ?? ["default"]
            for id in activeIds {
                let keys = ["imagePath_\(id)", "isLocked_\(id)", "opacity_\(id)", "windowFrame_\(id)"]
                for key in keys {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            UserDefaults.standard.set(["default"], forKey: "activeWidgetIDs")
        }
        
        // In default instance, launch other saved instances
        if widgetId == "default" && !globalConfig.shouldReset {
            let activeIds = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs") ?? ["default"]
            let exePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
            for id in activeIds {
                if id != "default" {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: exePath)
                    process.arguments = ["--id", id]
                    try? process.run()
                }
            }
        }
        
        // Determine initial frame
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let defaultWidth: CGFloat = 300
        let defaultHeight: CGFloat = 300
        
        var rect = NSRect(
            x: screenFrame.origin.x + (screenFrame.width - defaultWidth) / 2,
            y: screenFrame.origin.y + (screenFrame.height - defaultHeight) / 2,
            width: defaultWidth,
            height: defaultHeight
        )
        
        // Load saved frame (unless --reset was requested)
        if !globalConfig.shouldReset, let frameString = UserDefaults.standard.string(forKey: getPrefKey("windowFrame")) {
            rect = NSRectFromString(frameString)
        }
        
        // Override with command-line coordinates/size if specified
        if let w = globalConfig.width {
            rect.size.width = w
            rect.size.height = w
        }
        if let x = globalConfig.x {
            rect.origin.x = x
        }
        if let y = globalConfig.y {
            rect.origin.y = y
        }
        
        // Validate coordinates are on screen
        var isOnScreen = false
        for screen in NSScreen.screens {
            if screen.frame.intersects(rect) {
                isOnScreen = true
                break
            }
        }
        if !isOnScreen {
            rect.origin.x = screenFrame.origin.x + (screenFrame.width - rect.width) / 2
            rect.origin.y = screenFrame.origin.y + (screenFrame.height - rect.height) / 2
        }
        
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
        
        // Restore/Set opacity
        if let cliOpacity = globalConfig.opacity {
            win.alphaValue = CGFloat(cliOpacity)
            UserDefaults.standard.set(cliOpacity, forKey: getPrefKey("opacity"))
        } else {
            let savedOpacity = UserDefaults.standard.double(forKey: getPrefKey("opacity"))
            if savedOpacity > 0 {
                win.alphaValue = CGFloat(savedOpacity)
            }
        }
        
        // Restore/Set lock state
        let savedLock = UserDefaults.standard.bool(forKey: getPrefKey("isLocked"))
        let targetLock = globalConfig.isLocked ?? savedLock
        
        // Load image
        if let cliPath = globalConfig.imagePath {
            loadImage(from: cliPath)
            view.isLocked = targetLock
        } else if let savedPath = UserDefaults.standard.string(forKey: getPrefKey("imagePath")), !globalConfig.shouldReset {
            loadImage(from: savedPath)
            view.isLocked = targetLock
        } else {
            DispatchQueue.main.async {
                self.showOpenPanel()
                view.isLocked = targetLock
            }
        }
    }
    
    func loadImage(from path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        if let image = NSImage(contentsOfFile: expandedPath) {
            imageView?.image = image
            UserDefaults.standard.set(expandedPath, forKey: getPrefKey("imagePath"))
            
            if UserDefaults.standard.string(forKey: getPrefKey("windowFrame")) == nil || globalConfig.width != nil {
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
            let targetWidth = currentFrame.width
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
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: getPrefKey("windowFrame"))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
