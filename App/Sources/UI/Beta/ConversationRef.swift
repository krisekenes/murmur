import SwiftUI
import UniformTypeIdentifiers
import MurmurCore

extension UTType {
    /// Declared in project.yml under UTExportedTypeDeclarations.
    static let murmurConversation = UTType(exportedAs: "com.murmur.conversation")
    static let murmurFolder = UTType(exportedAs: "com.murmur.folder")
}

struct FolderRef: Codable, Transferable, Sendable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .murmurFolder)
    }
}

/// One drop receiver accepts either kind of tile, without overlapping drop targets.
enum FolderDrop: Transferable, Sendable {
    case conversation(ConversationRef)
    case folder(FolderRef)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (ref: ConversationRef) in FolderDrop.conversation(ref) })
        ProxyRepresentation(importing: { (ref: FolderRef) in FolderDrop.folder(ref) })
    }
}

/// Drag payload for springboard tiles. Carrying the text as well as the id means a
/// tile dragged out of Murmur pastes the transcript instead of a bare UUID.
struct ConversationRef: Codable, Transferable, Sendable {
    let id: UUID
    let text: String

    init(entry: HistoryEntry) {
        id = entry.id
        text = entry.polished.isEmpty ? entry.raw : entry.polished
    }

    static var transferRepresentation: some TransferRepresentation {
        // First representation wins for in-app drops; the proxy serves other apps.
        CodableRepresentation(contentType: .murmurConversation)
        ProxyRepresentation(exporting: \.text)
    }
}
