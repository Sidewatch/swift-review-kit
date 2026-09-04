import Foundation

/// The dictionary key a repository is filed under in the per-repo stores. One definition, so
/// `ReviewSession` and `TurnCheckpointStore` can never disagree about which repo a URL is.
enum RepoKey {
    /// The repository's path, or "" for no repository.
    static func of(_ root: URL?) -> String { root?.path ?? "" }
}
