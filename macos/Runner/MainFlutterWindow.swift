import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var scopedUrl: URL?
  private var menuChannel: FlutterMethodChannel?
  private var recentProjects: [(id: String, name: String)] = []
  private var recentSubmenu: NSMenu?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "nodeql/security_scope",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "start":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "BAD_ARGS", message: "Missing path", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        let ok = url.startAccessingSecurityScopedResource()
        if ok { self.scopedUrl = url }
        result(ok)
      case "stop":
        self.scopedUrl?.stopAccessingSecurityScopedResource()
        self.scopedUrl = nil
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let menuChannel = FlutterMethodChannel(
      name: "nodeql/menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.menuChannel = menuChannel
    menuChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "setRecentProjects":
        guard let args = call.arguments as? [String: Any],
              let items = args["items"] as? [[String: Any]] else {
          result(false)
          return
        }
        self.recentProjects = items.compactMap { item in
          guard let id = item["id"] as? String,
                let name = item["name"] as? String else { return nil }
          return (id: id, name: name)
        }
        self.rebuildRecentMenu()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    installProjectMenu()

    super.awakeFromNib()
  }

  private func installProjectMenu() {
    guard let mainMenu = NSApp.mainMenu else { return }
    let topItem = NSMenuItem(title: "Project", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "Project")

    let newItem = NSMenuItem(title: "New Project", action: #selector(handleNewProject), keyEquivalent: "n")
    newItem.keyEquivalentModifierMask = [.command, .shift]
    newItem.target = self
    submenu.addItem(newItem)

    let openItem = NSMenuItem(title: "Open Project…", action: #selector(handleOpenProject), keyEquivalent: "o")
    openItem.keyEquivalentModifierMask = [.command, .shift]
    openItem.target = self
    submenu.addItem(openItem)

    let saveItem = NSMenuItem(title: "Save Project", action: #selector(handleSaveProject), keyEquivalent: "s")
    saveItem.keyEquivalentModifierMask = [.command]
    saveItem.target = self
    submenu.addItem(saveItem)

    let saveAsItem = NSMenuItem(title: "Save Project As…", action: #selector(handleSaveAsProject), keyEquivalent: "s")
    saveAsItem.keyEquivalentModifierMask = [.command, .shift]
    saveAsItem.target = self
    submenu.addItem(saveAsItem)

    submenu.addItem(NSMenuItem.separator())
    let recentParent = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
    let recentSubmenu = NSMenu(title: "Recent Projects")
    recentParent.submenu = recentSubmenu
    self.recentSubmenu = recentSubmenu
    submenu.addItem(recentParent)

    topItem.submenu = submenu
    let insertionIndex = min(1, mainMenu.items.count)
    mainMenu.insertItem(topItem, at: insertionIndex)
  }

  private func rebuildRecentMenu() {
    guard let recentSubmenu = self.recentSubmenu else { return }
    recentSubmenu.removeAllItems()
    if recentProjects.isEmpty {
      let empty = NSMenuItem(title: "No recent projects", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      recentSubmenu.addItem(empty)
      return
    }

    for (index, project) in recentProjects.prefix(12).enumerated() {
      let item = NSMenuItem(title: project.name, action: #selector(handleRecentProject(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      recentSubmenu.addItem(item)
    }
  }

  @objc private func handleNewProject() {
    menuChannel?.invokeMethod("newProject", arguments: nil)
  }

  @objc private func handleOpenProject() {
    menuChannel?.invokeMethod("openProject", arguments: nil)
  }

  @objc private func handleSaveProject() {
    menuChannel?.invokeMethod("saveProject", arguments: nil)
  }

  @objc private func handleSaveAsProject() {
    menuChannel?.invokeMethod("saveProjectAs", arguments: nil)
  }

  @objc private func handleRecentProject(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < recentProjects.count else { return }
    let project = recentProjects[sender.tag]
    menuChannel?.invokeMethod("recentProject", arguments: ["id": project.id])
  }
}
