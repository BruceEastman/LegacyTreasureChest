//
//  LiquidationJSONCoding.swift
//  LegacyTreasureChest
//
//  Helpers to encode/decode Liquidate DTOs into Data for SwiftData storage.
//

import Foundation

public enum LiquidationJSONCoding {
    // Use a stable encoder/decoder so your persisted payloads remain consistent.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys] // stable output (nice for debugging)
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Encode

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    // MARK: - Decode

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    // MARK: - Safe decode (non-throwing)

    public static func tryDecode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do { return try decoder.decode(type, from: data) }
        catch { return nil }
    }

    // MARK: - Pretty print (debug only)

    public static func prettyJSONString(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }
}
