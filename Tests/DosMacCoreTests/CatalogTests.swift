import Foundation
import Testing

@testable import DosMacCore

struct CatalogTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_CATALOG"] == "1"))
  func livePublicArchiveCatalog() async throws {
    let items = try await SoftwareSources().search("Microsoft Word", source: .internetArchive)
    #expect(!items.isEmpty)
    #expect(items.allSatisfy { $0.pageURL.host == "archive.org" && !$0.title.isEmpty })
  }
  @Test func winWorldSearchKeepsProductsAndRejectsExternalLinks() {
    let html =
      "<dt><a href='/product/microsoft-word'>Word &amp; tools</a><a href='/search?tags=DOS'>DOS</a></dt><dd><p>A classic editor.</p></dd><dt><a href='https://other.test/product/no'>Outside</a></dt><dd>No</dd>"
    let items = SoftwareSources.parseCatalogProducts(
      html: html, page: URL(string: "https://winworldpc.com/search?q=word")!)
    #expect(items.count == 1)
    #expect(items.first?.title == "Word & tools")
    #expect(items.first?.summary == "A classic editor.")
    #expect(items.first?.pageURL.path == "/product/microsoft-word")
    let fallback = SoftwareSources.parseCatalogProducts(
      html: "<h3><a href='/product/word'>Word</a></h3><a href='/product/word'>Word</a>",
      page: URL(string: "https://winworldpc.com/search")!)
    #expect(fallback.count == 1)
  }
  @Test func archiveSearchAndDownloadsUseBoundedPublicFiles() throws {
    let results = Data(
      #"{"response":{"docs":[{"identifier":"word-6","title":"Word 6"},{"identifier":"../bad","title":"Bad"}]}}"#
        .utf8)
    #expect(try SoftwareSources.parseArchiveSearch(data: results).map(\.title) == ["Word 6"])
    let metadata = Data(
      #"{"files":[{"name":"Word 6.zip","size":"2048","sha1":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"name":"private.zip","size":"1","private":true},{"name":"../escape.zip","size":"1"},{"name":"huge.zip","size":"999999999"},{"name":"disk.iso","size":"2048"}]}"#
        .utf8)
    let files = try SoftwareSources.parseArchiveReleases(
      data: metadata, page: URL(string: "https://archive.org/details/word-6")!)
    #expect(files.count == 1)
    #expect(files[0].downloadURL?.path == "/download/word-6/Word 6.zip")
    #expect(files[0].sha1?.count == 40)
  }
  @Test func searchQueriesAreEncodedAsQueryParameters() {
    let query = "word & tools #6"
    let url = CatalogSource.winWorld.searchURL(query)
    #expect(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == query)
    #expect(url.fragment == nil)
  }
}
