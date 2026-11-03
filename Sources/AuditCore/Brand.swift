import Foundation

/// Shared identity for native UI and offline reports. Original supplied artwork is preserved.
public enum Brand {
    public static let name = "Xtracsys"
    public static let rustHex = "#B24630"
    public static let warmWhiteHex = "#F7F6F2"
    public static var logoData: Data? {
        if let url = Bundle.main.url(forResource: "XtracsysLogo", withExtension: "png"), let data = try? Data(contentsOf: url) { return data }
        guard let url = Bundle.module.url(forResource: "XtracsysLogo", withExtension: "png") else { return nil }
        return try? Data(contentsOf: url)
    }
    public static var logoDataURL: String { logoData.map { "data:image/png;base64," + $0.base64EncodedString() } ?? "" }
}
