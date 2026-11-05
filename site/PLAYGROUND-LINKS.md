# Playground links

The Playground opens two kinds of links. Both keep everything after `#`, which browsers
never send to a server.

| Link | Holds | Lifetime | Made by |
| --- | --- | --- | --- |
| Code link `…/playground/#code=…` | a copy of the files | forever (it is the data) | Share → Link to this code |
| Room link `…/playground/room/<id>/#key=…` | a key to a live, encrypted room on the relay | until the room closes (1–24 h) | Share → Start a live room |

Code: `site/lib/playground-share-link.ts` (encode, decode, parse). Tests:
`site/tests/playground-share-link.test.mjs`, which also decodes links with Node's own zlib
to prove the format needs nothing but standard raw DEFLATE.

## Code links, version 1

```
https://pythilo.com/playground/#code=<payload>
pythilo://playground/#code=<payload>
```

- The web form also opens without the trailing slash (`/playground#code=…`).
- The fragment is `&`-separated `key=value` pairs. `code` is the only key in version 1;
  readers ignore keys they do not know, so later versions can add some (for example a file
  to open first) without breaking old readers.

### Payload

```
payload = base64url( deflateRaw( utf8( json ) ) )
```

1. **JSON**, UTF-8, written with keys in this order (readers must not depend on it):

   ```json
   {"v":1,"name":"hello-pythilo","main":"main.py","files":{"main.py":"print(\"hi\")\n","pkg/util.py":"X = 1\n"}}
   ```

   | Key | Type | Meaning |
   | --- | --- | --- |
   | `v` | number | Format version, `1`. |
   | `name` | string | Project name, 1–80 characters, no control characters. Optional; a missing or blank name becomes `shared-project`. |
   | `main` | string | The file Run starts, a `.py` path in `files`. Optional; when missing or not in `files`, `main.py` if present, else the first `.py` path in sorted order. |
   | `files` | object | Relative path → full text of the file. Writers sort the paths, so equal projects give equal links. |

2. **DEFLATE, raw** (RFC 1951): no zlib header and no gzip header. The web writes it with
   fflate at level 9; any level and any encoder is fine for readers.
3. **base64url** (RFC 4648 §5, `-` and `_`) without `=` padding. Readers should also accept
   padding, the standard alphabet (`+` `/`) and line breaks, which some mail apps insert.

### Rules for the files

The same rules as every Playground project (`validatePlaygroundDocument` in
`site/lib/playground-document.ts`); a reader refuses the whole link if any fails:

- 1–16 files; each file at most 64 KiB of UTF-8; all files together at most 128 KiB.
- Paths are relative, `/`-separated, at most 180 characters and 32 parts; no empty, `.` or
  `..` part; no `\`, `:`, control characters, or leading `/`; no part named `__pycache__`,
  `.venv`, `venv`, `.git`, `.pythilo`, `site-packages`, `node_modules`, `.mypy_cache`,
  `.pytest_cache` (any case), `__proto__`, `constructor` or `prototype`.
- Extensions: `.py .pyi .txt .md .rst .csv .tsv .json .toml .cfg .ini .yaml .yml .html .css .js .sql`
  (any case), or exactly `requirements.txt`, `LICENSE`, `NOTICE`, `README`, `.gitignore` at the root.
- Two paths may not differ only in case (after Unicode NFC), and a file may not have the
  same path as a folder.
- Text has no NUL character and no unpaired UTF-16 surrogate.
- The main file is a `.py` file in `files`. A link with no `.py` file is refused.

### Limits

| | Value | Why |
| --- | --- | --- |
| Payload length | at most 100,000 characters | Writers refuse longer ones and offer a room or a ZIP instead; readers refuse above 110,000. |
| Comfortable length | 8,000 characters | Above it the web warns that some chat and mail apps cut long links. |
| Inflated JSON | at most 1 MiB | Readers stop inflating there, so a tiny link cannot expand into a huge one. |

The starter project gives a link of about 200 characters; typical small projects stay
well under 2,000.

### Versioning

- `v` is an integer. A reader opens every version up to its own and refuses a higher one
  with "This link was made by a newer Pythilo. Update the app or reload the page."
- A new version is only for a change old readers would misread. Adding an optional JSON key
  or fragment key does not need one: readers ignore keys they do not know.

### Opening

- A link opens as a **new local copy**: it never replaces or merges into anything the
  person already has open without asking, and it never runs code.
- The web keeps `#code=…` in the address bar until the first edit, so a reload before
  editing shows the shared code again; after an edit the address becomes `/playground/`.
- A damaged link shows the reason and opens an empty Playground.
- More options → **Open a link…** opens a pasted code link or room link.

### Decoding in Swift

```swift
import Foundation
import Compression

struct SharedProject: Decodable { let v: Int; let name: String?; let main: String?; let files: [String: String] }

/// `url` is https://pythilo.com/playground/#code=… or pythilo://playground/#code=…
func sharedProject(from url: URL) throws -> SharedProject? {
    guard let fragment = url.fragment(percentEncoded: true),
          let pair = fragment.split(separator: "&").first(where: { $0.hasPrefix("code=") }) else { return nil }
    var text = String(pair.dropFirst(5)).filter { !$0.isWhitespace }
        .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    guard text.count <= 110_000 else { throw LinkError.tooLarge }
    text = text.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    text += String(repeating: "=", count: (4 - text.count % 4) % 4)
    guard let compressed = Data(base64Encoded: text) else { throw LinkError.damaged }
    let json = try inflateRaw(compressed, limit: 1 << 20)
    let project = try JSONDecoder().decode(SharedProject.self, from: json)
    guard project.v >= 1 else { throw LinkError.damaged }
    guard project.v <= 1 else { throw LinkError.newerVersion }
    return project   // then apply "Rules for the files" before showing it
}

/// Apple's COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), the format these links use.
func inflateRaw(_ data: Data, limit: Int) throws -> Data {
    let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    defer { stream.deallocate() }
    guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { throw LinkError.damaged }
    defer { compression_stream_destroy(stream) }
    var output = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
    return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Data in
        stream.pointee.src_ptr = input.bindMemory(to: UInt8.self).baseAddress!
        stream.pointee.src_size = input.count
        while true {
            let status = buffer.withUnsafeMutableBufferPointer { out -> compression_status in
                stream.pointee.dst_ptr = out.baseAddress!; stream.pointee.dst_size = out.count
                return compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            }
            output.append(contentsOf: buffer[0 ..< buffer.count - stream.pointee.dst_size])
            if output.count > limit { throw LinkError.tooLarge }
            if status == COMPRESSION_STATUS_END { return output }
            if status != COMPRESSION_STATUS_OK { throw LinkError.damaged }
        }
    }
}
```

`(data as NSData).decompressed(using: .zlib)` also reads the payload, but it has no size
limit; prefer the stream above. To write a link from the app, encode the JSON (sorted paths),
compress with `COMPRESSION_ZLIB` (`(json as NSData).compressed(using: .zlib)`), base64-encode,
replace `+` `/` with `-` `_` and drop the `=` padding.

### In the app today

`RootView.onOpenURL` sends every `pythilo://` URL to the room join field. Code links need
their own branch: `pythilo://playground/` with a `code=` fragment (host `playground`, path
`/` or empty) is a code link; `pythilo://playground/room/<id>/` stays a room link. For
`https://pythilo.com/playground/#code=…` to open the app directly, the site must
serve an `apple-app-site-association` file listing `/playground/` and the app needs the
Associated Domains entitlement (neither exists yet); without them the
web Playground opens, and its Share sheet offers "Open in the Pythilo app" with the
`pythilo://` form.

## Room links

Unchanged by this work; parsed by `parsePlaygroundLink` in `site/lib/playground-session.ts`
and `PlaygroundLink.parse` in the app:

```
https://pythilo.com/playground/room/<id>/#key=<k>&access=<a>&expires=<ms>&mode=edit|view
pythilo://playground/room/<id>/#key=<k>&access=<a>&expires=<ms>&mode=edit|view
```

`<id>` is 24 base64url characters, `key` and `access` 43 each, `expires` milliseconds since
1970. The relay keeps only ciphertext, and rooms live in its memory until they close.
