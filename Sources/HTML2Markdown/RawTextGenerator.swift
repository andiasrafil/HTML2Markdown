//
//  RawTextGenerator.swift
//  HTML2Markdown
//
//  Created by David Walter on 30.01.23.
//

import Foundation
import SwiftSoup

public enum RawTextGenerator {
    public struct Options: OptionSet {
        public let rawValue: Int
        
        /// Copy link text instead of URL
        public static let keepLinkText = Options(rawValue: 1 << 0)
        /// Try to respect Mastodon classes
        public static let mastodon = Options(rawValue: 1 << 2)
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

extension Node {
    /// Extract the raw text from the parsed HTML
    ///
    /// - Parameter options: Options to customize the formatted text
    func rawText(options: RawTextGenerator.Options = []) -> String {
        return rawTextRoot(options: options, context: [], childIndex: 0)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func rawTextRoot(
        options: RawTextGenerator.Options,
        context: OutputContext,
        childIndex: Int,
        prefixPostfixBlock: ((String, String) -> Void)? = nil
    ) -> String {
        var result = ""
        let childrenWithContent = self.getChildNodes().filter { $0.shouldRender() }
        
        for (index, child) in childrenWithContent.enumerated() {
            var context: OutputContext = []
            if childrenWithContent.count == 1 {
                context.insert(.isSingleChildInRoot)
            }
            if index == 0 {
                context.insert(.isFirstChild)
            }
            if index == childrenWithContent.count - 1 {
                context.insert(.isFinalChild)
            }
            result += child.rawText(options: options, context: context, childIndex: index)
        }
        
        return result
    }
    
    private func rawText(
        options: RawTextGenerator.Options,
        context: OutputContext,
        childIndex: Int,
        prefixPostfixBlock: ((String, String) -> Void)? = nil
    ) -> String {
        var result = ""
        let children = getChildNodes()
        
        switch self.nodeName() {
        case "span":
            if let classes = getAttributes()?.get(key: "class").split(separator: " ") {
                if options.contains(.mastodon) {
                    if classes.contains("invisible") {
                        break
                    }
                    
                    result += output(children, options: options)
                    
                    if classes.contains("ellipsis") {
                        result += "…"
                    }
                } else {
                    result += output(children, options: options)
                }
            } else {
                result += output(children, options: options)
            }
        case "p":
            if !context.contains(.isSingleChildInRoot),
               !context.contains(.isFirstChild) {
                result += "\n"
            }
            
            result += output(children, options: options).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !context.contains(.isSingleChildInRoot),
               !context.contains(.isFinalChild) {
                result += "\n"
            }
        case "br":
            if !context.contains(.isFinalChild) {
                result += "\n"
            }
            // TODO: strip whitespace on the next line of text, immediately after this linebreak
        case "em":
            var prefix = ""
            var postfix = ""
            
            let blockToPass: (String, String) -> Void = {
                prefix = $0
                postfix = $1
            }
            
            let text = output(children, options: options, prefixPostfixBlock: blockToPass)
            
            // I'd rather use _ here, but cmark-gfm has better behaviour with *
            result += "\(prefix)*" + text + "*\(postfix)"
        case "strong":
            var prefix = ""
            var postfix = ""
            
            let blockToPass: (String, String) -> Void = {
                prefix = $0
                postfix = $1
            }
            
            let text = output(children, options: options, prefixPostfixBlock: blockToPass)
            
            result += "\(prefix)**" + text + "**\(postfix)"
        case "a":
            if let destination = getAttributes()?.get(key: "href") {
                if options.contains(.keepLinkText) {
                    result += output(children, options: options)
                } else {
                    result += destination
                }
            } else {
                result += output(children, options: options)
            }
        case "ul":
            if !context.contains(.isFirstChild) {
                result += "\n\n"
            }
            result += output(children, options: options, context: .isUnorderedList)
            
            if !context.contains(.isFinalChild) {
                result += "\n\n"
            }
        case "ol":
            if !context.contains(.isFirstChild) {
                result += "\n\n"
            }
            result += output(children, options: options, context: .isOrderedList)
            
            if !context.contains(.isFinalChild) {
                result += "\n\n"
            }
        case "li":
            if context.contains(.isUnorderedList) {
                result += "• \(output(children, options: options))"
            }
            if context.contains(.isOrderedList) {
                result += "\(childIndex + 1). \(output(children, options: options))"
            }
            if !context.contains(.isFinalChild) {
                result += "\n"
            }
        case "#text":
            result += description.stringByDecodingHTMLEntities
        default:
            result += output(children, options: options)
        }
        
        return result
    }
    
    private func output(
        _ children: [Node],
        options: RawTextGenerator.Options,
        context: OutputContext = [],
        prefixPostfixBlock: ((String, String) -> Void)? = nil
    ) -> String {
        var result = ""
        let childrenWithContent = children.filter { $0.shouldRender() }
        
        for (index, child) in childrenWithContent.enumerated() {
            var context = context
            if index == 0 {
                context.insert(.isFirstChild)
            }
            if index == childrenWithContent.count - 1 {
                context.insert(.isFinalChild)
            }
            result += child.rawText(options: options, context: context, childIndex: index, prefixPostfixBlock: prefixPostfixBlock)
        }
        
        if let prefixPostfixBlock = prefixPostfixBlock {
            if result.hasPrefix(" "), result.hasSuffix(" ") {
                prefixPostfixBlock(" ", " ")
                result = result.trimmingCharacters(in: .whitespaces)
            } else if result.hasPrefix(" ") {
                prefixPostfixBlock(" ", "")
                result = result.trimmingCharacters(in: .whitespaces)
            } else if result.hasSuffix(" ") {
                prefixPostfixBlock("", " ")
                result = result.trimmingCharacters(in: .whitespaces)
            }
        }
        
        return result.stringByDecodingHTMLEntities
    }
    
    private func shouldRender() -> Bool {
        if let element = self as? Element {
            switch element.nodeName() {
            case "br":
                return true
            default:
                do {
                    let text = try element.html()
                    return !text.isEmpty
                } catch {
                    return !element.description.isEmpty
                }
            }
        }
        
        switch nodeName() {
        case "br":
            return true
        default:
            return !description.isEmpty
        }
    }
}
