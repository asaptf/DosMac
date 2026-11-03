import Foundation

public enum CatalogSource: String, CaseIterable, Sendable {
  case winWorld, internetArchive
  public var title: String { self == .winWorld ? "WinWorld" : "Internet Archive" }
  public func searchURL(_ query: String) -> URL {
    var url = URLComponents(
      string: self == .winWorld
        ? "https://winworldpc.com/search" : "https://archive.org/advancedsearch.php")!
    url.queryItems =
      self == .winWorld
      ? [URLQueryItem(name: "q", value: query)]
      : [
        URLQueryItem(
          name: "q",
          value:
            "mediatype:software AND title:(\"\(query.replacingOccurrences(of: "\"", with: " ").replacingOccurrences(of: "\\", with: " "))\")"
        ), URLQueryItem(name: "output", value: "json"), URLQueryItem(name: "rows", value: "24"),
        URLQueryItem(name: "sort[]", value: "downloads desc"),
        URLQueryItem(name: "fl[]", value: "identifier"), URLQueryItem(name: "fl[]", value: "title"),
      ]
    return url.url!
  }
}

public struct CatalogItem: Identifiable, Sendable {
  public var id: String { pageURL.absoluteString }
  public let title: String
  public let summary: String
  public let pageURL: URL
  public let source: CatalogSource
  public init(title: String, summary: String, pageURL: URL, source: CatalogSource) {
    self.title = String(title.prefix(180))
    self.summary = String(summary.prefix(320))
    self.pageURL = pageURL
    self.source = source
  }
}
