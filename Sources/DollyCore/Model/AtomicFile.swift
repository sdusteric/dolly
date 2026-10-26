import Foundation

/// Atomic file writes: a temp file in the same directory, then `rename(2)` over the target, so a
/// reader never sees a half-written file (spec section 8).
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appending(
            path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))",
            directoryHint: .notDirectory
        )
        try data.write(to: temp)
        let status = rename(temp.path(percentEncoded: false), url.path(percentEncoded: false))
        if status != 0 {
            let code = errno
            do {
                try FileManager.default.removeItem(at: temp)
            } catch {
                // The rename failure below is the useful error; a stray temp file is harmless.
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Writes `data` under the first name in `names` that is free and returns its URL. The name is
    /// claimed with `renamex_np(RENAME_EXCL)` from a temp file, so an existing file is never
    /// replaced and two writers racing for one name both keep their file.
    public static func writeNew(_ data: Data, in directory: URL, names: some Sequence<String>) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appending(path: ".dolly-new.tmp-\(UUID().uuidString)", directoryHint: .notDirectory)
        try data.write(to: temp)
        var failure = POSIXErrorCode.EEXIST
        for name in names {
            let target = directory.appending(path: name, directoryHint: .notDirectory)
            if renamex_np(temp.path(percentEncoded: false), target.path(percentEncoded: false), UInt32(RENAME_EXCL)) == 0 {
                return target
            }
            let code = errno
            if code != EEXIST {
                failure = POSIXErrorCode(rawValue: code) ?? .EIO
                break
            }
        }
        do {
            try FileManager.default.removeItem(at: temp)
        } catch {
            // The claim failure below is the useful error; a stray temp file is harmless.
        }
        throw POSIXError(failure)
    }
}
