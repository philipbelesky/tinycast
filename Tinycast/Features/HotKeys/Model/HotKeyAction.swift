import Foundation

/// Everything in Tinycast a global shortcut can be bound to.
enum HotKeyAction: Hashable, Sendable {
    /// The one fixed action with no command row of its own.
    case togglePalette
    /// A second chord for the palette, so one synced settings envelope can suit two keyboards.
    case togglePaletteAlternate
    /// Parameterised over the catalog, so a new built-in command is bindable with no case here.
    case command(CommandID)
    /// The same second chord, for the commands in `alternateChordCommands`.
    case commandAlternate(CommandID)
    case app(bundleID: String)
    case settingsPane(bundleID: String)
    case customCommand(id: UUID)
    case systemAction(id: SystemAction.ID)
    case windowCommand(id: WindowCommand.ID)
    case quicklink(id: UUID)
    /// Keyed by `AppEntry.id`, which is what survives a reinstall of the extension.
    case extensionCommand(entryID: String)

    /// The UserDefaults key, and the `HotKeyCenter` registration id: one per action.
    var defaultsKey: String {
        switch self {
        case .togglePalette: "hotkey.togglePalette"
        case .togglePaletteAlternate: "hotkey.togglePalette.alternate"
        case .command(let id): "hotkey." + id.rawValue
        case .commandAlternate(let id): "hotkey." + id.rawValue + ".alternate"
        case .app(let bundleID): "hotkey.app." + bundleID
        case .settingsPane(let bundleID): "hotkey.pane." + bundleID
        case .customCommand(let id): "hotkey.customCommand." + id.uuidString.lowercased()
        case .systemAction(let id): "hotkey.systemAction." + id.rawValue
        case .windowCommand(let id): "hotkey.windowCommand." + id.rawValue
        case .quicklink(let id): "hotkey.quicklink." + id.uuidString.lowercased()
        case .extensionCommand(let entryID): "hotkey.extensionCommand." + entryID
        }
    }

    /// The fixed actions every install can bind; the per-item catalogs extend them at launch.
    static let builtInActions: [HotKeyAction] =
        [.togglePalette, .togglePaletteAlternate] + CommandID.allCases.compactMap(\.hotKeyAction)
        + alternateChordCommands.map(HotKeyAction.commandAlternate)

    /// Only the everyday one earns a second recorder in Settings — FORK.md divergence 16.
    static let alternateChordCommands: [CommandID] = [.clipboardHistory]
}
