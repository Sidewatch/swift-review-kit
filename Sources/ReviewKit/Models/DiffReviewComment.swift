import Foundation

/// One remark on one diff line — comment-driven review: pick a line in a rendered diff, say
/// what is wrong, repeat, then send the lot to the agent as ONE message.
public struct DiffReviewComment: Equatable, Sendable {
    public let path: String
    /// The line number in the NEW file for added/context lines, the OLD file for removed ones;
    /// nil for a comment on the file as a whole (the banner line).
    public let line: Int?
    /// "+", "-" or " " — which side the quoted line came from; "" for a file-level comment.
    public let side: String
    /// The diff line's text without its +/- marker, for the agent's orientation.
    public let quoted: String
    public let text: String

    public init(path: String, line: Int?, side: String, quoted: String, text: String) {
        self.path = path; self.line = line; self.side = side; self.quoted = quoted; self.text = text
    }

    /// "src/main.py:7" / "src/main.py" for the message and a label.
    public var reference: String { line.map { "\(path):\($0)" } ?? path }
}
