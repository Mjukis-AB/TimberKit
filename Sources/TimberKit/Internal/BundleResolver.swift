import Foundation

/// Resolves bundle identifiers from DSO handles or class types
enum BundleResolver {
    /// Cache for resolved bundle identifiers to avoid repeated dladdr calls
    private static var cache: [UnsafeRawPointer: String?] = [:]
    private static let lock = NSLock()

    /// Resolve bundle identifier from a DSO handle
    /// - Parameter dsoHandle: The `#dsohandle` value from the call site
    /// - Returns: Bundle identifier if resolvable, nil otherwise
    static func bundleIdentifier(from dsoHandle: UnsafeRawPointer) -> String? {
        lock.lock()
        defer { lock.unlock() }

        // Check cache first
        if let cached = cache[dsoHandle] {
            return cached
        }

        let result = resolveBundleIdentifier(from: dsoHandle)
        cache[dsoHandle] = result
        return result
    }

    private static func resolveBundleIdentifier(from dsoHandle: UnsafeRawPointer) -> String? {
        var info = Dl_info()
        guard dladdr(dsoHandle, &info) != 0,
              let pathPtr = info.dli_fname else {
            return nil
        }

        let path = String(cString: pathPtr)
        let url = URL(fileURLWithPath: path)

        // For frameworks: /path/to/Foo.framework/Foo -> go up to .framework
        // For apps: /path/to/App.app/App -> go up to .app
        var bundleURL = url.deletingLastPathComponent()

        // Check if we're in a framework or app bundle
        let possibleBundleExtensions = ["framework", "app", "appex", "bundle"]
        var foundBundle: Bundle?

        // Walk up the path looking for a bundle
        for _ in 0..<5 {  // Don't go too far up
            if possibleBundleExtensions.contains(bundleURL.pathExtension) {
                foundBundle = Bundle(url: bundleURL)
                break
            }
            let parent = bundleURL.deletingLastPathComponent()
            if parent == bundleURL { break }  // Reached root
            bundleURL = parent
        }

        return foundBundle?.bundleIdentifier
    }

    /// Resolve bundle identifier from a class type
    /// - Parameter type: Any class type from the target bundle
    /// - Returns: Bundle identifier
    static func bundleIdentifier(containing type: AnyClass) -> String? {
        return Bundle(for: type).bundleIdentifier
    }
}
