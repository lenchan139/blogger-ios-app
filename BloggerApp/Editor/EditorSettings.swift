import Foundation

/// Toggles between the new block editor and the legacy Aztec editor.
/// Defaults to the block editor.
enum EditorSettings {
    private static let key = "use.block-editor"

    static var useBlockEditor: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}