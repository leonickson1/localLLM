//
//  LinkPreviewService.swift
//  LocalLLM
//
//  Fetches Open Graph metadata for URLs so we can show inline link previews in journal entries.
//  Strictly on-demand: only runs when the user pastes a URL or explicitly asks for previews.
//

import Foundation

enum LinkPreviewService {

    /// Detect URLs in a body of text. Uses NSDataDetector so it handles both raw URLs
    /// and links typed without http:// prefix.
    static func detectURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.compactMap { $0.url }
    }

    /// Fetch og:title / og:image / og:description / og:site_name for a URL.
    /// Returns nil if the request fails or the page does not look like HTML.
    static func fetchPreview(for url: URL) async -> LinkPreview? {
        var request = URLRequest(url: url)
        // Pretend to be a normal browser so sites do not return mobile-app deep links or 403s
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 6

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            // Only parse HTML responses
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard contentType.contains("text/html") || contentType.contains("application/xhtml") else { return nil }

            // Use only the first 200KB to keep parsing fast on weak networks
            let html = String(data: data.prefix(200_000), encoding: .utf8)
                    ?? String(data: data.prefix(200_000), encoding: .isoLatin1)
                    ?? ""
            return parseOpenGraph(from: html, fallbackURL: url)
        } catch {
            return nil
        }
    }

    /// Lightweight HTML scrape for og: meta tags. Avoids pulling a full HTML parser dep.
    static func parseOpenGraph(from html: String, fallbackURL: URL) -> LinkPreview {
        let title       = extractMeta(html: html, properties: ["og:title", "twitter:title"]) ?? extractTitleTag(html: html)
        let description = extractMeta(html: html, properties: ["og:description", "twitter:description", "description"])
        let image       = extractMeta(html: html, properties: ["og:image", "twitter:image"])
        let siteName    = extractMeta(html: html, properties: ["og:site_name"]) ?? fallbackURL.host

        // Resolve relative image URLs against the page URL
        let resolvedImage: String? = {
            guard let img = image, !img.isEmpty else { return nil }
            if img.hasPrefix("http") { return img }
            if let resolved = URL(string: img, relativeTo: fallbackURL)?.absoluteURL.absoluteString {
                return resolved
            }
            return nil
        }()

        return LinkPreview(
            urlString: fallbackURL.absoluteString,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: resolvedImage,
            siteName: siteName
        )
    }

    /// Extract a `<meta property="X" content="...">` value. Tries multiple property names in order.
    private static func extractMeta(html: String, properties: [String]) -> String? {
        for property in properties {
            // Try both property= and name= attribute styles, with single or double quotes
            let patterns = [
                "<meta[^>]*property=[\"']\(property)[\"'][^>]*content=[\"']([^\"']+)[\"']",
                "<meta[^>]*name=[\"']\(property)[\"'][^>]*content=[\"']([^\"']+)[\"']",
                "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*property=[\"']\(property)[\"']",
                "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*name=[\"']\(property)[\"']"
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: html) {
                    return decodeHTMLEntities(String(html[range]))
                }
            }
        }
        return nil
    }

    /// Fallback to `<title>` tag if og:title is missing.
    private static func extractTitleTag(html: String) -> String? {
        let pattern = "<title[^>]*>([^<]+)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTMLEntities(String(html[range]))
    }

    /// Decode a small set of common HTML entities. Not exhaustive but covers what shows up in titles.
    private static func decodeHTMLEntities(_ string: String) -> String {
        var s = string
        let replacements: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&#x27;", "'"), ("&hellip;", "…"),
            ("&mdash;", "—"), ("&ndash;", "–")
        ]
        for (escaped, plain) in replacements {
            s = s.replacingOccurrences(of: escaped, with: plain)
        }
        return s
    }
}
