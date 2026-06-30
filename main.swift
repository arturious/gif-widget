import Cocoa
import UniformTypeIdentifiers

// Custom level for desktop background (sits below desktop icons and wallpaper background)
extension NSWindow.Level {
    static let desktop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
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
      -l, --lock           Start in locked mode (click-through, below windows & icons)
      -u, --unlock         Start in unlocked mode (draggable, normal window level)
      -x <value>           Initial X position of the widget (origin at bottom-left)
      -y <value>           Initial Y position of the widget (origin at bottom-left)
      -w, --width <value>  Initial width of the widget
      --reset              Clear saved settings and start fresh
    
    Managing Locked Widget:
      Hold Command (Cmd / ⌘) to temporarily raise locked widgets above desktop icons
      for dragging or right-clicking. Or use the Menu Bar menu.
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

class DragImageView: NSImageView {
    weak var windowRef: WidgetWindow?
    var widgetId: String = "default"
    
    var isLocked: Bool = false {
        didSet {
            UserDefaults.standard.set(isLocked, forKey: getPrefKey("isLocked"))
            updateWindowProperties()
            (NSApp.delegate as? AppDelegate)?.updateMenuBarMenu()
        }
    }
    
    func getPrefKey(_ key: String) -> String {
        return "\(key)_\(widgetId)"
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
            appDelegate.showOpenPanel(for: widgetId)
        }
    }
    
    @objc func createNewWidget() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.createNewWidgetWindow()
        }
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
        (NSApp.delegate as? AppDelegate)?.updateMenuBarMenu()
    }
    
    @objc func quitApp() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.closeWidgetWindow(id: widgetId)
        }
    }
    
    @objc func quitAllApp() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.closeAllWidgetWindows()
        }
    }
}

class WidgetWindow: NSWindow {
    var widgetId: String = ""
    
    init(contentRect: NSRect, widgetId: String) {
        self.widgetId = widgetId
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
    var widgetWindows: [String: WidgetWindow] = [:]
    var statusItem: NSStatusItem?
    var modifierTimer: Timer?
    
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
        
        setupMenuBar()
        startModifierTimer()
        
        // Load all active widgets
        let activeIds = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs") ?? ["default"]
        for id in activeIds {
            createWidgetWindow(id: id, isInitialLaunch: true)
        }
        
        updateMenuBarMenu()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "gifwidget")
            } else {
                button.title = "🖼️"
            }
        }
    }
    
    func startModifierTimer() {
        modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkModifierFlags()
        }
        RunLoop.main.add(modifierTimer!, forMode: .common)
    }
    
    func checkModifierFlags() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let isCmdPressed = flags.contains(.maskCommand)
        let isMouseDown = NSEvent.pressedMouseButtons != 0
        let isAppActive = NSApp.isActive
        
        let shouldBeRaised = isCmdPressed || isMouseDown || isAppActive
        let targetLevel = shouldBeRaised ? NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1) : .desktop
        
        for (_, win) in widgetWindows {
            guard let view = win.contentView?.subviews.first(where: { $0 is DragImageView }) as? DragImageView else {
                continue
            }
            
            if view.isLocked {
                if win.level != targetLevel {
                    win.level = targetLevel
                }
            }
        }
    }
    
    func updateMenuBarMenu() {
        let menu = NSMenu()
        
        let newItem = NSMenuItem(title: "New Widget", action: #selector(menuBarNewWidget), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let headerItem = NSMenuItem(title: "Active Widgets:", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        for (id, win) in widgetWindows {
            let view = win.contentView?.subviews.first(where: { $0 is DragImageView }) as? DragImageView
            let isLocked = view?.isLocked ?? false
            
            let widgetMenu = NSMenu()
            
            // Lock/Unlock
            let lockItem = NSMenuItem(title: isLocked ? "Unlock" : "Lock", action: #selector(menuBarToggleLock(_:)), keyEquivalent: "")
            lockItem.target = self
            lockItem.representedObject = id
            if #available(macOS 11.0, *) {
                lockItem.image = NSImage(systemSymbolName: isLocked ? "lock.open.fill" : "lock.fill", accessibilityDescription: nil)
            }
            widgetMenu.addItem(lockItem)
            
            // Choose image
            let chooseItem = NSMenuItem(title: "Choose image/GIF...", action: #selector(menuBarChooseFile(_:)), keyEquivalent: "")
            chooseItem.target = self
            chooseItem.representedObject = id
            widgetMenu.addItem(chooseItem)
            
            // Size Submenu
            let sizeMenu = NSMenu()
            let sizes = [
                ("Increase (+)", #selector(menuBarIncreaseSize(_:))),
                ("Decrease (-)", #selector(menuBarDecreaseSize(_:))),
                ("Reset Size", #selector(menuBarResetSize(_:)))
            ]
            for (title, action) in sizes {
                let sItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
                sItem.target = self
                sItem.representedObject = id
                if #available(macOS 11.0, *) {
                    let iconName = title.hasPrefix("Increase") ? "plus" : (title.hasPrefix("Decrease") ? "minus" : "arrow.counterclockwise")
                    sItem.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                }
                sizeMenu.addItem(sItem)
            }
            let sizeParent = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
            sizeParent.submenu = sizeMenu
            widgetMenu.addItem(sizeParent)
            
            // Opacity Submenu
            let opacityMenu = NSMenu()
            let opacities = [100, 90, 80, 70, 60, 50, 40, 30, 20]
            for percent in opacities {
                let opItem = NSMenuItem(title: "\(percent)%", action: #selector(menuBarSetOpacity(_:)), keyEquivalent: "")
                opItem.target = self
                opItem.tag = percent
                opItem.representedObject = id
                let currentPercent = Int(round(win.alphaValue * 100))
                if abs(currentPercent - percent) <= 2 {
                    opItem.state = .on
                }
                opacityMenu.addItem(opItem)
            }
            let opacityParent = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
            opacityParent.submenu = opacityMenu
            widgetMenu.addItem(opacityParent)
            
            widgetMenu.addItem(NSMenuItem.separator())
            
            // Close widget
            let closeItem = NSMenuItem(title: "Close Widget", action: #selector(menuBarCloseWidget(_:)), keyEquivalent: "")
            closeItem.target = self
            closeItem.representedObject = id
            widgetMenu.addItem(closeItem)
            
            // Retrieve image file name for menu title
            var displayName = "Widget (\(id))"
            if let imgPath = UserDefaults.standard.string(forKey: "imagePath_\(id)") {
                displayName = (imgPath as NSString).lastPathComponent
                if displayName.count > 22 {
                    displayName = String(displayName.prefix(19)) + "..."
                }
            }
            
            let widgetParent = NSMenuItem(title: displayName, action: nil, keyEquivalent: "")
            widgetParent.submenu = widgetMenu
            menu.addItem(widgetParent)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let quitAllItem = NSMenuItem(title: "Quit gifwidget", action: #selector(menuBarQuitAll), keyEquivalent: "q")
        quitAllItem.target = self
        menu.addItem(quitAllItem)
        
        statusItem?.menu = menu
    }
    
    // MARK: Menu Bar Actions
    @objc func menuBarNewWidget() {
        createNewWidgetWindow()
        updateMenuBarMenu()
    }
    
    @objc func menuBarToggleLock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let win = widgetWindows[id],
              let view = win.contentView?.subviews.first(where: { $0 is DragImageView }) as? DragImageView else {
            return
        }
        view.isLocked = !view.isLocked
        updateMenuBarMenu()
    }
    
    @objc func menuBarChooseFile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        showOpenPanel(for: id)
    }
    
    @objc func menuBarCloseWidget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        closeWidgetWindow(id: id)
        updateMenuBarMenu()
    }
    
    @objc func menuBarIncreaseSize(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let win = widgetWindows[id],
              let view = win.contentView?.subviews.first(where: { $0 is DragImageView }) as? DragImageView else {
            return
        }
        view.increaseSize()
    }
    
    @objc func menuBarDecreaseSize(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let win = widgetWindows[id],
              let view = win.contentView?.subviews.first(where: { $0 is DragImageView }) as? DragImageView else {
            return
        }
        view.decreaseSize()
    }
    
    @objc func menuBarResetSize(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let win = widgetWindows[id],
              let view = win.contentView?.subviews.first(where: { $0 is DragImageView }) as? DragImageView else {
            return
        }
        view.resetSize()
    }
    
    @objc func menuBarSetOpacity(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let win = widgetWindows[id] else {
            return
        }
        let alpha = CGFloat(sender.tag) / 100.0
        win.alphaValue = alpha
        UserDefaults.standard.set(Double(alpha), forKey: "opacity_\(id)")
        updateMenuBarMenu()
    }
    
    @objc func menuBarQuitAll() {
        closeAllWidgetWindows()
    }
    
    func createWidgetWindow(id: String, isInitialLaunch: Bool = false) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let defaultWidth: CGFloat = 300
        let defaultHeight: CGFloat = 300
        
        var rect = NSRect(
            x: screenFrame.origin.x + (screenFrame.width - defaultWidth) / 2,
            y: screenFrame.origin.y + (screenFrame.height - defaultHeight) / 2,
            width: defaultWidth,
            height: defaultHeight
        )
        
        let frameKey = "windowFrame_\(id)"
        if !globalConfig.shouldReset, let frameString = UserDefaults.standard.string(forKey: frameKey) {
            rect = NSRectFromString(frameString)
        }
        
        // Apply CLI overrides only to the default widget during initial launch
        if id == "default" && isInitialLaunch {
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
        
        let win = WidgetWindow(contentRect: rect, widgetId: id)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        widgetWindows[id] = win
        
        let view = DragImageView(frame: win.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.windowRef = win
        view.widgetId = id
        win.contentView?.addSubview(view)
        
        // Set opacity
        let opacityKey = "opacity_\(id)"
        if id == "default" && isInitialLaunch, let cliOpacity = globalConfig.opacity {
            win.alphaValue = CGFloat(cliOpacity)
            UserDefaults.standard.set(cliOpacity, forKey: opacityKey)
        } else {
            let savedOpacity = UserDefaults.standard.double(forKey: opacityKey)
            if savedOpacity > 0 {
                win.alphaValue = CGFloat(savedOpacity)
            }
        }
        
        // Set lock state
        let lockKey = "isLocked_\(id)"
        let savedLock = UserDefaults.standard.bool(forKey: lockKey)
        let targetLock = (id == "default" && isInitialLaunch) ? (globalConfig.isLocked ?? savedLock) : savedLock
        
        // Load image
        let imageKey = "imagePath_\(id)"
        if id == "default" && isInitialLaunch, let cliPath = globalConfig.imagePath {
            loadImage(for: win, view: view, from: cliPath)
            view.isLocked = targetLock
        } else if let savedPath = UserDefaults.standard.string(forKey: imageKey), !globalConfig.shouldReset {
            loadImage(for: win, view: view, from: savedPath)
            view.isLocked = targetLock
        } else {
            DispatchQueue.main.async {
                self.showOpenPanel(for: id)
                view.isLocked = targetLock
            }
        }
    }
    
    func createNewWidgetWindow() {
        let newId = String(Int(Date().timeIntervalSince1970))
        var activeIds = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs") ?? ["default"]
        if !activeIds.contains(newId) {
            activeIds.append(newId)
            UserDefaults.standard.set(activeIds, forKey: "activeWidgetIDs")
        }
        createWidgetWindow(id: newId)
    }
    
    func loadImage(for win: WidgetWindow, view: DragImageView, from path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        if let image = NSImage(contentsOfFile: expandedPath) {
            view.image = image
            let imageKey = "imagePath_\(win.widgetId)"
            UserDefaults.standard.set(expandedPath, forKey: imageKey)
            
            let frameKey = "windowFrame_\(win.widgetId)"
            if UserDefaults.standard.string(forKey: frameKey) == nil || (win.widgetId == "default" && globalConfig.width != nil) {
                adjustWindowSize(for: win, image: image)
            }
            updateMenuBarMenu()
        } else {
            let alert = NSAlert()
            alert.messageText = "Failed to load image"
            alert.informativeText = "Could not read image file at:\n\(path)"
            alert.alertStyle = .warning
            alert.runModal()
            
            if view.image == nil {
                showOpenPanel(for: win.widgetId)
            }
        }
    }
    
    func adjustWindowSize(for win: WidgetWindow, image: NSImage) {
        let size = image.size
        if size.width > 0 && size.height > 0 {
            let aspectRatio = size.width / size.height
            let currentFrame = win.frame
            let targetWidth = currentFrame.width
            let targetHeight = targetWidth / aspectRatio
            
            win.setFrame(
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
    
    func showOpenPanel(for id: String) {
        guard let win = widgetWindows[id],
              let view = win.contentView?.subviews.first(where: { $0 is DragImageView }) as? DragImageView else {
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.image]
        panel.level = .modalPanel
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.loadImage(for: win, view: view, from: url.path)
            } else if view.image == nil {
                self.closeWidgetWindow(id: id)
            }
        }
    }
    
    func closeWidgetWindow(id: String) {
        guard let win = widgetWindows[id] else { return }
        win.close()
        widgetWindows.removeValue(forKey: id)
        
        if id != "default" {
            var activeIds = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs") ?? ["default"]
            if let index = activeIds.firstIndex(of: id) {
                activeIds.remove(at: index)
                UserDefaults.standard.set(activeIds, forKey: "activeWidgetIDs")
            }
        }
        
        updateMenuBarMenu()
        
        // If no windows left, quit the app
        if widgetWindows.isEmpty {
            NSApp.terminate(nil)
        }
    }
    
    func closeAllWidgetWindows() {
        UserDefaults.standard.set(["default"], forKey: "activeWidgetIDs")
        for win in widgetWindows.values {
            win.close()
        }
        widgetWindows.removeAll()
        NSApp.terminate(nil)
    }
    
    // MARK: NSWindowDelegate methods to persist frame
    func windowDidMove(_ notification: Notification) {
        if let win = notification.object as? WidgetWindow {
            saveWindowFrame(for: win)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        if let win = notification.object as? WidgetWindow {
            saveWindowFrame(for: win)
        }
    }
    
    func saveWindowFrame(for win: WidgetWindow) {
        let frameKey = "windowFrame_\(win.widgetId)"
        UserDefaults.standard.set(NSStringFromRect(win.frame), forKey: frameKey)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
