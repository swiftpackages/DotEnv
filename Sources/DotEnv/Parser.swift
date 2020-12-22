//
//  Parser.swift
//  
//
//  Created by Marz Rover on 12/6/20.
// A signficant portion of this code comes from [vapor/vapor](https://github.com/vapor/vapor).
//

import Foundation
import NIO

/// Internal  extension to help the `Parser` identify characters
internal extension UInt8 {
    /// Newline Character
    static var newLine: UInt8 {
        return 0xA
    }
    /// Space Character
    static var space: UInt8 {
        return 0x20
    }
    /// Octothorpe Character
    static var octothorpe: UInt8 {
        return 0x23
    }
    /// Equal Character
    static var equal: UInt8 {
        return 0x3D
    }
}

/// Internal  protocol to ensure a smooth read
internal protocol Parser {
    /// Enables adopters to define their own source type
    /// e.g. `String`, `[UInt8]`, etc.
    associatedtype SourceType
    /// Enables adopters to define their own input source type
    /// e.g. `String`, `[UInt8]`, etc.
    associatedtype InitSourceType
    /// The raw source to parse
    var source: SourceType { get set }
    /// Initializer accepting source
    init(source: InitSourceType)
    /// Parse the source
    mutating func parse() -> [Line]
}

/// Parse byte arrays, which are `[UInt8]`
internal struct ByteArrayParser: Parser {
    /// The source `[UInt8]` to parse
    var source: [UInt8]
    /// The type of encoding used
    /// - warning: Only tested with `.utf8` use other encodings at your own risk
    var encoding: String.Encoding
    /// Current reader index
    var readerIndex: Int = 0
    /// Initalize with source
    /// - parameters:
    ///     - source: The source to parse
    init(source: [UInt8]) {
        self.source = source
        self.encoding = .utf8
    }
    /// Initalize with source and encoding
    /// - parameters:
    ///     - source: The source to parse
    ///     - encoding: The encoding to use
    init(source: [UInt8], encoding: String.Encoding) {
        self.source = source
        self.encoding = encoding
    }
    /// Parse the source
    /// - returns: `[Line]`
    mutating func parse() -> [Line] {
        var lines: [Line] = []
        while let next = self.parseNext() {
            lines.append(next)
        }
        return lines
    }
    /// Determines how to parse the next line
    /// - returns: `Line?`
    private mutating func parseNext() -> Line? {
        self.skipSpaces()
        guard let peek = self.peek() else {
            return nil
        }
        switch peek {
            case .octothorpe:
                // comment following, skip it
                self.skipComment()
                // then parse next
                return self.parseNext()
            case .newLine:
                // empty line, skip
                self.pop() // \n
                // then parse next
                return self.parseNext()
            default:
                // this is a valid line, parse it
                return self.parseLine()
        }
    }
    /// Skip a comment line
    private mutating func skipComment() {
        guard let commentLength = self.countDistance(to: .newLine) else {
            return
        }
        self.readerIndex += commentLength + 1 // include newline
    }
    /// Parse the line
    /// - returns: `Line?`
    private mutating func parseLine() -> Line? {
        guard let keyLength = self.countDistance(to: .equal) else {
            return nil
        }
        guard let key = String(bytes: self.reader(length: keyLength)!,
                               encoding: self.encoding) else {
            return nil
        }
        self.pop() // =
        guard let value = self.parseLineValue() else {
            return nil
        }
        return Line(key: key, value: value)
    }
    /// Parse the `value` side of the `key=value` pair
    /// - returns: `String?`
    private mutating func parseLineValue() -> String? {
        let valueLength: Int
        if let toNewLine = self.countDistance(to: .newLine) {
            valueLength = toNewLine
        } else {
            valueLength = self.source.count - self.readerIndex
        }
        guard let valueBytes = (self.readerIndex + valueLength) <= self.source.count
                ? self.reader(length: valueLength)
                : nil
        else {
            return nil
        }

        let value = String(bytes: valueBytes, encoding: self.encoding)!
        guard let first = value.first, let last = value.last else {
            return value
        }

        // check for quoted strings
        switch (first, last) {
        case ("\"", "\""):
            // double quoted strings support escaped \n
            return value.dropFirst().dropLast()
                .replacingOccurrences(of: "\\n", with: "\n")
        case ("'", "'"):
            // single quoted strings just need quotes removed
            return value.dropFirst().dropLast() + ""
        default: return value
        }
    }
    /// Skip spaces until another character is found
    private mutating func skipSpaces() {
        scan: while let next = self.peek() {
            switch next {
                case .space:
                    self.pop()
                default:
                    break scan
            }
        }
    }
    /// Take a look at the next character to read without moving the readerIndex
    /// - returns: `UInt8?`
    private func peek() -> UInt8? {
        guard self.readerIndex < self.source.count  else {
            return nil
        }
        return self.source[self.readerIndex]
    }
    /// Read the next character
    /// - returns: `UInt8?`
    @discardableResult
    private mutating func pop() -> UInt8? {
        self.readerIndex += 1

        guard self.readerIndex - 1 < self.source.count else {
            return nil
        }
        return self.source[self.readerIndex - 1]
    }
    /// Count the distance to the next occurrence of `byte`
    /// - returns: `Int?`
    private func countDistance(to byte: UInt8) -> Int? {
        var index = self.readerIndex
        var found = false

        scan: while let next = index < self.source.count ? self.source[index] : nil {
            index += 1
            if next == byte {
                found = true
                break scan
            }
        }

        guard found else {
            return nil
        }

        let distance = index - self.readerIndex
        guard distance != 0 else {
            return nil
        }

        return distance - 1
    }
    /// Read the input length from source moving readerIndex
    private mutating func reader(length: Int) -> ArraySlice<UInt8>? {
        guard self.readerIndex + length <= self.source.count else {
            return nil
        }
        let out = self.source[self.readerIndex..<(self.readerIndex + length)]
        self.readerIndex += length
        return out
    }
}

/// String parser wrapper around `ByteArrayParser`
internal struct StringParser: Parser {
    /// The `ByteArrayParser` we are wrapping
    var source: ByteArrayParser
    /// Intialize with source `String`
    init(source: String) {
        self.source = ByteArrayParser(source: [UInt8](source.utf8))
    }
    /// Parse using our `ByteArrayParser`
    /// - returns: `[Line]`
    mutating func parse() -> [Line] {
        return self.source.parse()
    }
}
/// Parse `swift-nio`'s `ByteBuffer`
internal struct ByteBufferParser: Parser {
    /// The source `ByteBuffer` to parse
    var source: ByteBuffer
    /// Initalize with source
    /// - parameters:
    ///     - source: The source to parse
    init(source: ByteBuffer) {
        self.source = source
    }
    /// Parse the source
    /// - returns: `[Line]`
    mutating func parse() -> [Line] {
        var lines: [Line] = []
        while let next = self.parseNext() {
            lines.append(next)
        }
        return lines
    }
    /// Determines how to parse the next line
    /// - returns: `Line?`
    private mutating func parseNext() -> Line? {
        self.skipSpaces()
        guard let peek = self.peek() else {
            return nil
        }
        switch peek {
        case .octothorpe:
            // comment following, skip it
            self.skipComment()
            // then parse next
            return self.parseNext()
        case .newLine:
            // empty line, skip
            self.pop() // \n
            // then parse next
            return self.parseNext()
        default:
            // this is a valid line, parse it
            return self.parseLine()
        }
    }
    /// Skip a comment line
    private mutating func skipComment() {
        guard let commentLength = self.countDistance(to: .newLine) else {
            return
        }
        self.source.moveReaderIndex(forwardBy: commentLength + 1) // include newline
    }
    /// Parse the line
    /// - returns: `Line?`
    private mutating func parseLine() -> Line? {
        guard let keyLength = self.countDistance(to: .equal) else {
            return nil
        }
        guard let key = self.source.readString(length: keyLength) else {
            return nil
        }
        self.pop() // =
        guard let value = self.parseLineValue() else {
            return nil
        }
        return Line(key: key, value: value)
    }
    /// Parse the `value` side of the `key=value` pair
    /// - returns: `String?`
    private mutating func parseLineValue() -> String? {
        let valueLength: Int
        if let toNewLine = self.countDistance(to: .newLine) {
            valueLength = toNewLine
        } else {
            valueLength = self.source.readableBytes
        }
        guard let value = self.source.readString(length: valueLength) else {
            return nil
        }
        guard let first = value.first, let last = value.last else {
            return value
        }
        // check for quoted strings
        switch (first, last) {
        case ("\"", "\""):
            // double quoted strings support escaped \n
            return value.dropFirst().dropLast()
                .replacingOccurrences(of: "\\n", with: "\n")
        case ("'", "'"):
            // single quoted strings just need quotes removed
            return value.dropFirst().dropLast() + ""
        default: return value
        }
    }
    /// Skip spaces until another character is found
    private mutating func skipSpaces() {
        scan: while let next = self.peek() {
            switch next {
            case .space: self.pop()
            default: break scan
            }
        }
    }
    /// Take a look at the next character to read without moving the `ByteBuffer`.`readerIndex`
    /// - returns: `UInt8?`
    private func peek() -> UInt8? {
        return self.source.getInteger(at: self.source.readerIndex)
    }
    /// Read the next character
    /// - warning: Moves the `ByteBuffer`.`readIndex`
    /// - returns: `UInt8?`
    private mutating func pop() {
        self.source.moveReaderIndex(forwardBy: 1)
    }
    /// Count the distance to the next occurrence of `byte`
    /// - returns: `Int?`
    private func countDistance(to byte: UInt8) -> Int? {
        var copy = self.source
        var found = false
        scan: while let next = copy.readInteger(as: UInt8.self) {
            if next == byte {
                found = true
                break scan
            }
        }
        guard found else {
            return nil
        }
        let distance = copy.readerIndex - source.readerIndex
        guard distance != 0 else {
            return nil
        }
        return distance - 1
    }
}
