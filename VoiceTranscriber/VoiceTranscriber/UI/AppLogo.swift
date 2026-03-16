import SwiftUI

/// Displays the Verbalize logo with the correct variant for the current color scheme.
/// Uses the transparent logo from bundle resources, falling back to the app icon.
struct AppLogo: View {
    let size: CGFloat
    let colorScheme: ColorScheme

    private var logoResourceName: String {
        colorScheme == .dark ? "logo-transparent-dark" : "logo-transparent-light"
    }

    var body: some View {
        if let logoURL = Bundle.main.url(forResource: logoResourceName, withExtension: "png"),
           let logoImage = NSImage(contentsOf: logoURL) {
            Image(nsImage: logoImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else if let appIcon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: size * 0.7))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
        }
    }
}
