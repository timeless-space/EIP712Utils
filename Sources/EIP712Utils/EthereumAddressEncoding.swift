// Copyright © 2017-2018 Trust.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

/// Ethereum address.
public struct EthereumAddressEncoding: Hashable {
    public static let size = 20

    /// Validates that the raw data is a valid address.
    static public func isValid(data: Data) -> Bool {
        return data.count == EthereumAddressEncoding.size
    }

    /// Validates that the string is a valid address.
    static public func isValid(string: String) -> Bool {
        guard let data = Data(hexString: string) else {
            return false
        }
        return EthereumAddressEncoding.isValid(data: data)
    }

    /// Raw address bytes, length 20.
    public let data: Data

    /// Creates an address with `Data`.
    ///
    /// - Precondition: data contains exactly 20 bytes
    public init?(data: Data) {
        if !EthereumAddressEncoding.isValid(data: data) {
            return nil
        }
        self.data = data
    }

    /// Creates an address with an hexadecimal string representation.
    public init?(string: String) {
        guard let data = Data(hexString: string), EthereumAddressEncoding.isValid(data: data) else {
            return nil
        }
        self.init(data: data)
    }

    public var hashValue: Int {
        return data.hashValue
    }

    public static func == (lhs: EthereumAddressEncoding, rhs: EthereumAddressEncoding) -> Bool {
        return lhs.data == rhs.data
    }
}
