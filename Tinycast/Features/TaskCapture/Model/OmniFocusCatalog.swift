import Foundation

/// OmniFocus's projects and tags, read through the one JXA script below and parsed here.
/// Batched getters keep it to a handful of Apple events, so a 200-project database answers in
/// well under a second. See docs/features/task-capture.md#omnifocus.
enum OmniFocusCatalog {
    static let script = """
        const doc = Application("OmniFocus").defaultDocument;
        const names = doc.flattenedProjects.name();
        const statuses = doc.flattenedProjects.status();
        const folders = doc.flattenedProjects.folder.name();
        const projects = [];
        names.forEach((name, index) => {
          if (statuses[index] === "active status") {
            projects.push({ name: name, folder: folders[index] || null });
          }
        });
        const tagNames = doc.flattenedTags.name();
        const tagIDs = doc.flattenedTags.id();
        const parentIDs = doc.flattenedTags.container.id();
        const hidden = doc.flattenedTags.hidden();
        const byID = {};
        tagIDs.forEach((id, index) => { byID[id] = index; });
        const path = (index) => {
          const parent = byID[parentIDs[index]];
          return parent === undefined ? tagNames[index] : path(parent) + " : " + tagNames[index];
        };
        const tags = tagIDs.map((_, index) => hidden[index] ? null : path(index)).filter(Boolean);
        JSON.stringify({ projects: projects, tags: tags });
        """

    static func parse(_ data: Data) -> TaskCaptureCatalog? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return TaskCaptureCatalog(
            projects: reply.projects.map { TaskCaptureProject(name: $0.name, path: $0.name, folder: $0.folder) },
            tags: reply.tags)
    }

    private struct Reply: Decodable {
        struct Project: Decodable {
            let name: String
            let folder: String?
        }
        let projects: [Project]
        let tags: [String]
    }
}
