import CryptoKit
import Foundation
import ZIPFoundation

enum ContentInstaller {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let block = try file.read(upToCount: 256 * 1024), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func safePath(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !value.isEmpty && value.utf8.count <= 300 && parts.count <= 20 && parts.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0") &&
            $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
        }
    }

    static func validate(_ pack: ContentPack) throws {
        guard pack.bytes > 0, pack.bytes <= 64 * 1024 * 1024,
              pack.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              !pack.files.isEmpty, pack.files.count <= 10_000,
              pack.files.allSatisfy({ safePath($0.path) && $0.bytes >= 0 && $0.bytes <= 32 * 1024 * 1024 && $0.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }),
              pack.files.reduce(0, { $0 + $1.bytes }) <= 160 * 1024 * 1024,
              Set(pack.files.map { $0.path.precomposedStringWithCanonicalMapping.lowercased() }).count == pack.files.count else {
            throw ContentFailure.invalid("The download catalog has an invalid file inventory.")
        }
    }

    static func installed(_ pack: ContentPack, root: URL) -> URL? {
        let target = root.appending(path: pack.sha256, directoryHint: .isDirectory)
        guard let receipt = try? String(contentsOf: target.appending(path: ".verified"), encoding: .utf8), receipt == pack.sha256 else { return nil }
        for file in pack.files {
            let url = target.appending(path: file.path)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == file.bytes else { return nil }
        }
        return target
    }

    static func install(_ archiveURL: URL, pack: ContentPack, root: URL) throws -> URL {
        try validate(pack)
        if let existing = installed(pack, root: root) { return existing }
        let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue == pack.bytes,
              try hashFile(archiveURL) == pack.sha256 else { throw ContentFailure.invalid("The download checksum did not match. Please retry.") }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        if pack.format == "raw" {
            guard pack.files.count == 1 else { throw ContentFailure.invalid("The asset inventory is invalid.") }
            let destination = staging.appending(path: pack.files[0].path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: archiveURL, to: destination)
        } else {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            let inventory = Dictionary(uniqueKeysWithValues: pack.files.map { ($0.path, $0) })
            var seen = Set<String>()
            for entry in archive {
                try Task.checkCancellation()
                guard entry.type == .file, safePath(entry.path), seen.insert(entry.path).inserted,
                      let expected = inventory[entry.path], entry.uncompressedSize == UInt64(expected.bytes) else {
                    throw ContentFailure.invalid("The archive contains an unexpected file.")
                }
                let destination = staging.appending(path: entry.path)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: destination.path, contents: nil)
                let output = try FileHandle(forWritingTo: destination)
                var bytes = 0
                do {
                    _ = try archive.extract(entry, bufferSize: 64 * 1024) { block in
                        bytes += block.count
                        guard bytes <= expected.bytes else { throw ContentFailure.invalid("The archive exceeds its declared size.") }
                        try output.write(contentsOf: block)
                    }
                    try output.close()
                } catch { try? output.close(); throw error }
                guard bytes == expected.bytes, try hashFile(destination) == expected.sha256 else { throw ContentFailure.invalid("An unpacked file checksum did not match.") }
            }
            guard seen == Set(inventory.keys) else { throw ContentFailure.invalid("The archive is missing files.") }
        }
        for file in pack.files {
            guard try hashFile(staging.appending(path: file.path)) == file.sha256 else { throw ContentFailure.invalid("An installed file checksum did not match.") }
        }
        try Data(pack.sha256.utf8).write(to: staging.appending(path: ".verified"), options: .atomic)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var stagingURL = staging; try stagingURL.setResourceValues(values)
        let destination = root.appending(path: pack.sha256, directoryHint: .isDirectory)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging, to: destination)
        return destination
    }
}
