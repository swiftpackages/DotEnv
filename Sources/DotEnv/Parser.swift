//
//  Parser.swift
//  
//
//  Created by Marz Rover on 12/6/20.
// A signficant portion of this code comes from [vapor/vapor](https://github.com/vapor/vapor).
//

import Foundation
import NIO

protocol Parser {
    associatedtype sourceType
    associatedtype initSourceType
    
    var source: sourceType { get set }
    init(source: initSourceType)

    mutating func parse() -> [Line]
}

internal struct ByteArrayParser: Parser {
    var source: [UInt8]
    var encoding: String.Encoding
    var readerIndex: Int = 0

    init(source: [UInt8]) {
        self.source = source
        self.encoding = .utf8
    }

    init(source: [UInt8], encoding: String.Encoding) {
        self.source = source
        self.encoding = encoding
    }

    mutating func parse() -> [Line] {
        var lines: [Line] = []
        while let next = self.parseNext() {
            lines.append(next)
        }
        return lines
    }

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

    private mutating func skipComment() {
        guard let commentLength = self.countDistance(to: .newLine) else {
            return
        }
        self.readerIndex += commentLength + 1 // include newline
    }

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

    private mutating func parseLineValue() -> String? {
        let valueLength: Int
        if let toNewLine = self.countDistance(to: .newLine) {
            valueLength = toNewLine
        } else {
            valueLength = self.source.count
        }
        guard let valueBytes = (self.readerIndex + valueLength) < self.source.count
                ? self.reader(length: valueLength)!
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

    private func peek() -> UInt8? {
        guard self.readerIndex < self.source.count  else {
            return nil
        }
        return self.source[self.readerIndex]
    }

    @discardableResult
    private mutating func pop() -> UInt8? {
        self.readerIndex += 1

        guard self.readerIndex - 1 < self.source.count else {
            return nil
        }
        return self.source[self.readerIndex - 1]
    }

    private func countDistance(to byte: UInt8) -> Int? {
        var index = self.readerIndex
        var found = false

        scan: while let next = index < self.source.count ? self.source[index] : nil {
            if next == byte {
                found = true
                break scan
            }
            index += 1
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

    private mutating func reader(length: Int) -> ArraySlice<UInt8>? {
        guard self.readerIndex + length < self.source.count else {
            return nil
        }
        let out = self.source[self.readerIndex...(self.readerIndex + length)]
        self.readerIndex += length + 1
        return out
    }
}

internal struct StringParser: Parser {
    var source: ByteArrayParser

    init(source: String) {
        self.source = ByteArrayParser(source: [UInt8](source.utf8))
    }

    mutating func parse() -> [Line] {
        return self.source.parse()
    }
}

internal struct ByteBufferParser: Parser {
    var source: ByteBuffer

    init(source: ByteBuffer) {
        self.source = source
    }

    mutating func parse() -> [Line] {
        var lines: [Line] = []
        while let next = self.parseNext() {
            lines.append(next)
        }
        return lines
    }

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

    private mutating func skipComment() {
        guard let commentLength = self.countDistance(to: .newLine) else {
            return
        }
        self.source.moveReaderIndex(forwardBy: commentLength + 1) // include newline
    }

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

    private mutating func skipSpaces() {
        scan: while let next = self.peek() {
            switch next {
            case .space: self.pop()
            default: break scan
            }
        }
    }

    private func peek() -> UInt8? {
        return self.source.getInteger(at: self.source.readerIndex)
    }

    private mutating func pop() {
        self.source.moveReaderIndex(forwardBy: 1)
    }

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
