import Foundation

/// Turns a tag into a folder display name. Shared so that dragging two
/// conversations together and Smart organize never disagree on what to call
/// the same topic.
public enum FolderNaming {
    static let topicNames = ["interview": "Interviews", "meetings": "Meetings", "tasks": "Tasks",
                             "ideas": "Ideas", "work": "Work", "travel": "Travel", "learning": "Learning",
                             "engineering": "Engineering", "personal": "Personal"]

    public static func displayName(for tag: String) -> String {
        let tag = NoteTagger.normalize(tag)
        return topicNames[tag] ?? tag.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
