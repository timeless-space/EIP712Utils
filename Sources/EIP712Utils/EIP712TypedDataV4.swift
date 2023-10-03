// Copyright © 2017-2018 Trust.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

/// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md
import Foundation
import BigInt
import web3swift

/// A struct represents EIP712 TypedDataV4
public struct EIP712TypedDataV4: Codable {
    public let types: [String: [EIP712Type]]
    public let primaryType: String
    public let domain: JSON
    public let message: JSON
}

extension EIP712TypedDataV4 {
    /// Type hash for the primaryType of an `EIP712TypedData`
    public var typeHash: Data {
        let data = encodeType(primaryType: primaryType)
        return data.sha3(.keccak256)
    }

    /// Sign-able hash for an `EIP712TypedData`
    public var signHash: Data {
        let prefix = Data([0x19, 0x01])
        let domainHash = encodeData(data: domain, type: "EIP712Domain").sha3(.keccak256)
        let messageHash = encodeData(data: message, type: primaryType).sha3(.keccak256)
        let data = prefix + domainHash + messageHash

        return data.sha3(.keccak256)
    }

    /// Recursively finds all the dependencies of a type
    func findDependencies(primaryType: String, dependencies: Set<String> = Set<String>()) -> Set<String> {
        var found = dependencies
        guard !found.contains(primaryType),
              let primaryTypes = types[primaryType] else {
            return found
        }
        found.insert(primaryType)
        for type in primaryTypes {
            findDependencies(primaryType: type.type, dependencies: found)
                .forEach { found.insert($0) }
        }
        return found
    }

    /// Encode a type of struct
    public func encodeType(primaryType: String) -> Data {
        var depSet = findDependencies(primaryType: primaryType)
        depSet.remove(primaryType)
        let sorted = [primaryType] + Array(depSet).sorted()
        let encoded = sorted.map { type in
            let param = types[type]!.map { "\($0.type) \($0.name)" }.joined(separator: ",")
            return "\(type)(\(param))"
        }.joined()
        return encoded.data(using: .utf8) ?? Data()
    }

    /// Encode an instance of struct
    ///
    /// Implemented with `ABIEncoder` and `ABIValue`
    public func encodeData(data: JSON, type: String) -> Data {
        let encoder = ABIEncoder()
        var values: [ABIValue] = []
        do {
            let typeHash = encodeType(primaryType: type).sha3(.keccak256)
            let typeHashValue = try ABIValue(typeHash, type: .bytes(32))
            values.append(typeHashValue)
            if let valueTypes = types[type] {
                try valueTypes.forEach { field in
                    if let _ = types[field.type],
                       let json = data[field.name] {
                        let nestEncoded = encodeData(data: json, type: field.type)
                        values.append(try ABIValue(nestEncoded.sha3(.keccak256), type: .bytes(32)))
                    } else if let value = makeABIValue(name: field.name, data: data[field.name], type: field.type) {
                        values.append(value)
                    }
                }
            }
            try encoder.encode(tuple: values)
        } catch let error {
            print(error)
        }
        return encoder.data
    }

    /// Helper func for `encodeData`
    private func makeABIValue(name: String, data: JSON?, type: String) -> ABIValue? {
        if (type == "string"), let value = data?.stringValue, let valueData = value.data(using: .utf8) {
            return try? ABIValue(valueData.sha3(.keccak256), type: .bytes(32))
        }
        else if (type == "bytes"), let value = data?.stringValue {
            let valueData = Data(hex: value)
            return try? ABIValue(valueData.sha3(.keccak256), type: .bytes(32))
        }
        else if type == "bool", let value = data?.boolValue {
            return try? ABIValue(value, type: .bool)
        }
        else if type == "address", let value = data?.stringValue, let address = EthereumAddressEncoding(string: value) {
            return try? ABIValue(address, type: .address)
        }
        else if type.starts(with: "uint") {
            let size = parseIntSize(type: type, prefix: "uint")
            guard size > 0 else { return nil }
            if let value = data?.doubleValue {
                return try? ABIValue(Int(value), type: .uint(bits: size))
            } else if let value = data?.stringValue,
                      let bigInt = BigUInt(value: value) {
                return try? ABIValue(bigInt, type: .uint(bits: size))
            }
        } else if type.starts(with: "int") {
            let size = parseIntSize(type: type, prefix: "int")
            guard size > 0 else { return nil }
            if let value = data?.doubleValue {
                return try? ABIValue(Int(value), type: .int(bits: size))
            } else if let value = data?.stringValue,
                      let bigInt = BigInt(value: value) {
                return try? ABIValue(bigInt, type: .int(bits: size))
            }
        } else if type.starts(with: "bytes") {
            if let length = Int(type.dropFirst("bytes".count)),
               let value = data?.stringValue {
                if value.starts(with: "0x"),
                   let hex = Data(hexString: value) {
                    return try? ABIValue(hex, type: .bytes(length))
                } else {
                    return try? ABIValue(Data(Array(value.utf8)), type: .bytes(length))
                }
            }
        }

        // Array
        let components = type.components(separatedBy: CharacterSet(charactersIn: "[]"))
        if components.count == 3 {
            let components = type.components(separatedBy: CharacterSet(charactersIn: "[]"))
            if case let .array(jsons) = data {
                if components[1].isEmpty {
                    let rawType = components[0]
                    let encoder = ABIEncoder()
                    let values = jsons.compactMap {
                        try? encodeField(name: name, rawType: rawType, value: $0)
                    }
                    try? encoder.encode(tuple: values)
                    return try? ABIValue(encoder.data.sha3(.keccak256), type: .bytes(32))
                } else if !components[1].isEmpty {
                    let num = String(components[1].filter { "0"..."9" ~= $0 })
                    guard Int(num) != nil else { return nil }
                    let rawType = components[0]
                    let encoder = ABIEncoder()
                    let values = jsons.compactMap {
                        try? encodeField(name: name, rawType: rawType, value: $0)
                    }
                    try? encoder.encode(tuple: values)
                    return try? ABIValue(encoder.data.sha3(.keccak256), type: .bytes(32))
                } else {
                    return nil
                }
            }
        }
        return nil
    }

    /// Helper func for encoding uint / int types
    private func parseIntSize(type: String, prefix: String) -> Int {
        guard type.starts(with: prefix),
              let size = Int(type.dropFirst(prefix.count)) else {
            return -1
        }

        if size < 8 || size > 256 || size % 8 != 0 {
            return -1
        }
        return size
    }

    private func encodeField(
        name: String,
        rawType: String,
        value: JSON
    ) throws -> ABIValue? {
        // Arrays
        let components = rawType.components(separatedBy: CharacterSet(charactersIn: "[]"))
        if case let .array(jsons) = value {
            if components.count == 3 && components[1].isEmpty {
                let rawType = components[0]
                let encoder = ABIEncoder()
                let values = jsons.compactMap {
                    try? encodeField(name: name, rawType: rawType, value: $0)
                }
                try? encoder.encode(tuple: values)
                return try? ABIValue(encoder.data.sha3(.keccak256), type: .bytes(32))
            } else if components.count == 3 && !components[1].isEmpty {
                let num = String(components[1].filter { "0"..."9" ~= $0 })
                guard Int(num) != nil else { return nil }
                let rawType = components[0]
                let encoder = ABIEncoder()
                let values = jsons.compactMap {
                    try? encodeField(name: name, rawType: rawType, value: $0)
                }
                try? encoder.encode(tuple: values)
                return try? ABIValue(encoder.data.sha3(.keccak256), type: .bytes(32))
            } else {
                throw ABIError.invalidArgumentType
            }
        }

        return makeABIValue(
            name: name,
            data: value,
            type: rawType)
    }
}

private extension BigInt {
    init?(value: String) {
        if value.starts(with: "0x") {
            self.init(String(value.dropFirst(2)), radix: 16)
        } else {
            self.init(value)
        }
    }
}

private extension BigUInt {
    init?(value: String) {
        if value.starts(with: "0x") {
            self.init(String(value.dropFirst(2)), radix: 16)
        } else {
            self.init(value)
        }
    }
}
