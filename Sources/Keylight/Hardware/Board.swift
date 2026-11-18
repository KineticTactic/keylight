import Foundation

struct Key: Identifiable {
    let id: Int
    let label: String
    let x, y, width: Double

    init(_ id: Int, _ label: String, _ x: Double, _ y: Double, _ width: Double) {
        self.id = id
        self.label = label
        self.x = x
        self.y = y
        self.width = width
    }
}

// Physical positions from the wired URX VIA layout. The encoder LED is index 81.
enum Board {
    static let width = 16.0
    static let height = 6.25
    static let numberRow = Set(15...24) // 1 through 0 on the wired layout.
    static let perimeter = Set(keys.filter { key in
        key.y == 0 || key.y + 1 == height || key.x == 0 || key.x + key.width == width
    }.map(\.id))
    static let interior = Set(keys.map(\.id)).subtracting(perimeter)

    static let keys: [Key] = [
        Key(0, "Esc", 0, 0, 1),
        Key(1, "F1", 1.25, 0, 1),
        Key(2, "F2", 2.25, 0, 1),
        Key(3, "F3", 3.25, 0, 1),
        Key(4, "F4", 4.25, 0, 1),
        Key(5, "F5", 5.5, 0, 1),
        Key(6, "F6", 6.5, 0, 1),
        Key(7, "F7", 7.5, 0, 1),
        Key(8, "F8", 8.5, 0, 1),
        Key(9, "F9", 9.75, 0, 1),
        Key(10, "F10", 10.75, 0, 1),
        Key(11, "F11", 11.75, 0, 1),
        Key(12, "F12", 12.75, 0, 1),
        Key(13, "Del", 14, 0, 1),
        Key(81, "Knob", 15, 0, 1),
        Key(14, "`", 0, 1.25, 1),
        Key(15, "1", 1, 1.25, 1),
        Key(16, "2", 2, 1.25, 1),
        Key(17, "3", 3, 1.25, 1),
        Key(18, "4", 4, 1.25, 1),
        Key(19, "5", 5, 1.25, 1),
        Key(20, "6", 6, 1.25, 1),
        Key(21, "7", 7, 1.25, 1),
        Key(22, "8", 8, 1.25, 1),
        Key(23, "9", 9, 1.25, 1),
        Key(24, "0", 10, 1.25, 1),
        Key(25, "-", 11, 1.25, 1),
        Key(26, "=", 12, 1.25, 1),
        Key(27, "⌫", 13, 1.25, 2),
        Key(28, "Home", 15, 1.25, 1),
        Key(29, "Tab", 0, 2.25, 1.5),
        Key(30, "Q", 1.5, 2.25, 1),
        Key(31, "W", 2.5, 2.25, 1),
        Key(32, "E", 3.5, 2.25, 1),
        Key(33, "R", 4.5, 2.25, 1),
        Key(34, "T", 5.5, 2.25, 1),
        Key(35, "Y", 6.5, 2.25, 1),
        Key(36, "U", 7.5, 2.25, 1),
        Key(37, "I", 8.5, 2.25, 1),
        Key(38, "O", 9.5, 2.25, 1),
        Key(39, "P", 10.5, 2.25, 1),
        Key(40, "[", 11.5, 2.25, 1),
        Key(41, "]", 12.5, 2.25, 1),
        Key(42, "\\", 13.5, 2.25, 1.5),
        Key(43, "End", 15, 2.25, 1),
        Key(44, "Caps", 0, 3.25, 1.75),
        Key(45, "A", 1.75, 3.25, 1),
        Key(46, "S", 2.75, 3.25, 1),
        Key(47, "D", 3.75, 3.25, 1),
        Key(48, "F", 4.75, 3.25, 1),
        Key(49, "G", 5.75, 3.25, 1),
        Key(50, "H", 6.75, 3.25, 1),
        Key(51, "J", 7.75, 3.25, 1),
        Key(52, "K", 8.75, 3.25, 1),
        Key(53, "L", 9.75, 3.25, 1),
        Key(54, ";", 10.75, 3.25, 1),
        Key(55, "'", 11.75, 3.25, 1),
        Key(56, "Return", 12.75, 3.25, 2.25),
        Key(57, "PgUp", 15, 3.25, 1),
        Key(58, "Shift", 0, 4.25, 2.25),
        Key(59, "Z", 2.25, 4.25, 1),
        Key(60, "X", 3.25, 4.25, 1),
        Key(61, "C", 4.25, 4.25, 1),
        Key(62, "V", 5.25, 4.25, 1),
        Key(63, "B", 6.25, 4.25, 1),
        Key(64, "N", 7.25, 4.25, 1),
        Key(65, "M", 8.25, 4.25, 1),
        Key(66, ",", 9.25, 4.25, 1),
        Key(67, ".", 10.25, 4.25, 1),
        Key(68, "/", 11.25, 4.25, 1),
        Key(69, "Shift", 12.25, 4.25, 1.75),
        Key(70, "↑", 14, 4.25, 1),
        Key(71, "PgDn", 15, 4.25, 1),
        Key(72, "Ctrl", 0, 5.25, 1.25),
        Key(73, "Opt", 1.25, 5.25, 1.25),
        Key(74, "Cmd", 2.5, 5.25, 1.25),
        Key(75, "Space", 3.75, 5.25, 6.25),
        Key(76, "Cmd", 10, 5.25, 1.25),
        Key(77, "Fn", 11.25, 5.25, 1.25),
        Key(78, "←", 13, 5.25, 1),
        Key(79, "↓", 14, 5.25, 1),
        Key(80, "→", 15, 5.25, 1),
    ].sorted { $0.id < $1.id }
}
