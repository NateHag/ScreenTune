import Foundation

/// Minimal reader/writer for matrix/TRC ICC display profiles.
enum ICC {
    struct Tag {
        var sig: String
        var data: Data
    }

    static func parse(_ d: Data) -> (header: Data, tags: [Tag])? {
        guard d.count >= 132 else { return nil }
        let count = Int(u32(d, 128))
        guard d.count >= 132 + count * 12 else { return nil }
        var tags: [Tag] = []
        for i in 0..<count {
            let o = 132 + i * 12
            let sig = String(bytes: d[o..<o + 4], encoding: .ascii) ?? "????"
            let off = Int(u32(d, o + 4)), len = Int(u32(d, o + 8))
            guard off + len <= d.count else { return nil }
            tags.append(Tag(sig: sig, data: d.subdata(in: off..<off + len)))
        }
        return (d.subdata(in: 0..<128), tags)
    }

    static func build(header: Data, tags: [Tag]) -> Data {
        var table = Data(), body = Data()
        var offsets: [Data: Int] = [:]  // identical tag data is shared, as in the original
        let dataStart = 132 + tags.count * 12
        for tag in tags {
            let off: Int
            if let shared = offsets[tag.data] {
                off = shared
            } else {
                off = dataStart + body.count
                offsets[tag.data] = off
                body.append(tag.data)
                while body.count % 4 != 0 { body.append(0) }
            }
            table.append(Data(tag.sig.utf8.prefix(4)))
            table.append(be32(UInt32(off)))
            table.append(be32(UInt32(tag.data.count)))
        }
        var out = header
        out.append(be32(UInt32(tags.count)))
        out.append(table)
        out.append(body)
        out.replaceSubrange(0..<4, with: be32(UInt32(out.count)))
        out.replaceSubrange(84..<100, with: Data(count: 16))  // profile ID (MD5) = not computed
        return out
    }

    /// Returns a copy of `profile` whose primaries are changed so that ColorSync
    /// shows colors with saturation scaled by `s` (1 = unchanged).
    static func saturated(_ profile: Data, _ s: Double, name: String) -> Data? {
        guard let (header, tags) = parse(profile),
              let r = xyz(tags, "rXYZ"), let g = xyz(tags, "gXYZ"), let b = xyz(tags, "bXYZ")
        else { return nil }

        // Displayed = M * Sat(s) * M⁻¹, so the claimed matrix is M * Sat(1/s).
        // Sat(a) = L + a(I - L), where every row of L is the luminance weights w.
        let cols = [r, g, b]
        let ySum = r[1] + g[1] + b[1]
        let w = cols.map { $0[1] / ySum }
        let a = 1 / s
        var newCols: [[Double]] = []
        for j in 0..<3 {
            var c = [0.0, 0.0, 0.0]
            for k in 0..<3 {
                let sat = w[j] + a * ((k == j ? 1 : 0) - w[j])
                for row in 0..<3 { c[row] += cols[k][row] * sat }
            }
            newCols.append(c)
        }

        let version = header[8]
        var out: [Tag] = []
        for tag in tags {
            switch tag.sig {
            case "rXYZ": out.append(Tag(sig: tag.sig, data: xyzData(newCols[0])))
            case "gXYZ": out.append(Tag(sig: tag.sig, data: xyzData(newCols[1])))
            case "bXYZ": out.append(Tag(sig: tag.sig, data: xyzData(newCols[2])))
            case "desc": out.append(Tag(sig: "desc", data: version >= 4 ? mluc(name) : descV2(name)))
            case "dscm", "A2B0", "A2B1", "A2B2", "B2A0", "B2A1", "B2A2", "D2B0", "B2D0":
                continue  // drop: they would override our matrix or our name
            default: out.append(tag)
            }
        }
        return build(header: header, tags: out)
    }

    static func description(_ profile: Data) -> String? {
        guard let (_, tags) = parse(profile), let d = tags.first(where: { $0.sig == "desc" })?.data,
              d.count > 12 else { return nil }
        let type = String(bytes: d[0..<4], encoding: .ascii)
        if type == "desc" {
            let n = Int(u32(d, 8))
            guard d.count >= 12 + n else { return nil }
            return String(bytes: d[12..<12 + max(n - 1, 0)], encoding: .ascii)
        }
        if type == "mluc", d.count >= 28 {
            let len = Int(u32(d, 20)), off = Int(u32(d, 24))
            guard d.count >= off + len else { return nil }
            return String(data: d[off..<off + len], encoding: .utf16BigEndian)
        }
        return nil
    }

    // MARK: - Encoding helpers

    private static func xyz(_ tags: [Tag], _ sig: String) -> [Double]? {
        guard let d = tags.first(where: { $0.sig == sig })?.data, d.count >= 20 else { return nil }
        return (0..<3).map { Double(Int32(bitPattern: u32(d, 8 + $0 * 4))) / 65536 }
    }

    private static func xyzData(_ v: [Double]) -> Data {
        var d = Data("XYZ ".utf8) + Data(count: 4)
        for x in v { d.append(be32(UInt32(bitPattern: Int32((x * 65536).rounded())))) }
        return d
    }

    private static func descV2(_ s: String) -> Data {
        let ascii = Data(s.utf8.filter { $0 < 128 }) + Data([0])
        var d = Data("desc".utf8) + Data(count: 4)
        d.append(be32(UInt32(ascii.count)))
        d.append(ascii)
        d.append(Data(count: 4 + 4 + 2 + 1 + 67))  // empty Unicode + ScriptCode parts
        return d
    }

    private static func mluc(_ s: String) -> Data {
        let text = s.data(using: .utf16BigEndian) ?? Data()
        var d = Data("mluc".utf8) + Data(count: 4)
        d.append(be32(1))
        d.append(be32(12))
        d.append(Data("enUS".utf8))
        d.append(be32(UInt32(text.count)))
        d.append(be32(28))
        d.append(text)
        return d
    }

    private static func u32(_ d: Data, _ o: Int) -> UInt32 {
        d[d.startIndex + o..<d.startIndex + o + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func be32(_ v: UInt32) -> Data {
        withUnsafeBytes(of: v.bigEndian) { Data($0) }
    }
}
