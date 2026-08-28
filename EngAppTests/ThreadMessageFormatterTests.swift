import Testing

@testable import Eng

struct ThreadMessageFormatterTests {
  @Test func parsesConversationMarkdownIntoDisplayBlocks() {
    let source = """
      # Result

      A **formatted** response with [a link](https://example.com).

      - First item
      2. Second item
      > A useful note

      ```swift
      let answer = 42
      ```
      """

    #expect(
      ThreadMessageFormatter.blocks(from: source)
        == [
          .heading(level: 1, text: "Result"),
          .paragraph("A **formatted** response with [a link](https://example.com)."),
          .bullet("First item"),
          .numbered(marker: "2.", text: "Second item"),
          .quote("A useful note"),
          .code(language: "swift", body: "let answer = 42"),
        ])
  }

  @Test func preservesUnclosedCodeFenceAsCode() {
    #expect(
      ThreadMessageFormatter.blocks(from: "```\ncommand output")
        == [.code(language: nil, body: "command output")])
  }
}
