import Foundation

// Smooth intensity values per layer before rendering the keyboard. A
// time-based filter keeps its response consistent when render frames are skipped.
struct BandSmoothing {
    private var sceneID: UUID?
    private var ensembleTargets: [UUID: [Double]] = [:]
    private var previous: [UUID: [Double]] = [:]

    mutating func update(scene: LightingScene, audio: [UUID: AudioReading], delta: Double) -> [UUID: [Double]] {
        if sceneID != scene.id { previous.removeAll(); ensembleTargets.removeAll(); sceneID = scene.id }
        var current: [UUID: [Double]] = [:]
        var nextTargets: [UUID: [Double]] = [:]
        for layer in scene.layers where layer.effect.usesMix || (layer.effect.usesBands && layer.audio.smoothing > 0) {
            var target = audio[layer.id]?.levels ?? Array(repeating: 0.0, count: layer.effect == .towers ? FrequencyBand.towerBands.count : 4)
            let history = previous[layer.id] ?? []
            let old = history.count == target.count ? history : Array(repeating: 0, count: target.count)
            let duration = layer.effect.usesMix ? layer.mixSmoothing : layer.audio.smoothing
            var blend = 1 - exp(-max(0, delta) / duration)
            if layer.effect == .ensemble {
                // Two short easing stages lift a note into view without an
                // abrupt first frame, then carry it across slower USB frames.
                blend = 1 - exp(-max(0, delta) / (duration * 0.23))
                let prior = ensembleTargets[layer.id] ?? old
                target = zip(prior, target).map { $0 + ($1 - $0) * blend }
                nextTargets[layer.id] = target
            }
            current[layer.id] = zip(old, target).map { prior, goal in
                let value = prior + (goal - prior) * blend
                return abs(value - goal) < 0.0001 ? goal : value
            }
        }
        ensembleTargets = nextTargets
        previous = current
        return current
    }
}
