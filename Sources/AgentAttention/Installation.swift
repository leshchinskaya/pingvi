import Foundation

/// Persistent hooks must never point into an ejectable or translocated app.
enum Installation {
    static func needsMove(bundle: URL = Bundle.main.bundleURL) -> Bool {
        let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        return readOnly || bundle.path.contains("/AppTranslocation/")
    }
    static let message = "Перетащите Pingvi в папку «Программы», извлеките DMG и откройте установленное приложение. После этого подключите агентов."
}
