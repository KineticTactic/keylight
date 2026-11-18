import Combine
import Foundation

// Updating an open status menu during pointer tracking can dismiss its submenu.
// Subscribe only to the values that change the actual menu items.
@MainActor
final class StatusMenuState: ObservableObject {
    struct Mode: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    @Published private(set) var modes: [Mode] = []
    @Published private(set) var selected: UUID
    @Published private(set) var paused = false

    init(studio: Studio) {
        selected = studio.selected
        studio.$scenes
            .map { scenes in scenes.map { Mode(id: $0.id, name: $0.name) } }
            .removeDuplicates()
            .assign(to: &$modes)
        studio.$selected.removeDuplicates().assign(to: &$selected)
        studio.$paused.removeDuplicates().assign(to: &$paused)
    }
}
