import ControllerDrivers
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

@Suite("Planificateur de LED")
struct LEDPlannerTests {
    private func grid() -> (PadGrid, sound: Pad, light: Pad) {
        var grid = PadGrid.empty(name: "G")
        let sound = Pad(title: "S", tint: .vert, ledIntensity: .half, content: .audio(clip: AudioClip(fileName: "a.wav")))
        let light = Pad(
            title: "L", tint: .ambre,
            content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 60))))
        grid.columns[0].slots[0] = sound
        grid.columns[6].slots[1] = light
        return (grid, sound, light)
    }

    @Test("Cases vides éteintes, pads allumés à leur teinte et leur intensité")
    func idle() {
        let (grid, sound, _) = grid()
        let states = LEDPlanner.states(for: grid, playback: [:])
        #expect(states.count == 64)
        #expect(states[GridPosition(column: 0, row: 0)] == .lit(.vert, .half))
        #expect(states[GridPosition(column: 6, row: 1)] == .lit(.ambre, .full))
        #expect(states[GridPosition(column: 3, row: 3)] == .off)
        _ = sound
    }

    @Test("Un son en lecture pulse, un son en pause est atténué")
    func playback() {
        let (grid, sound, _) = grid()
        let position = GridPosition(column: 0, row: 0)
        let playing = [sound.id: PlaybackEvent(pad: sound.id, state: .playing(startedAt: 0), duration: 3)]
        #expect(LEDPlanner.states(for: grid, playback: playing)[position] == .pulsing(.vert))
        let paused = [sound.id: PlaybackEvent(pad: sound.id, state: .paused(elapsed: 1), duration: 3)]
        #expect(LEDPlanner.states(for: grid, playback: paused)[position] == .lit(.vert, .quarter))
    }

    @Test("Seules les LED qui changent sont renvoyées")
    func changes() {
        let (grid, sound, _) = grid()
        let before = LEDPlanner.states(for: grid, playback: [:])
        let after = LEDPlanner.states(
            for: grid, playback: [sound.id: PlaybackEvent(pad: sound.id, state: .playing(startedAt: 0), duration: 1)])
        let diff = LEDPlanner.changes(from: before, to: after)
        #expect(diff == [GridPosition(column: 0, row: 0): .pulsing(.vert)])
        #expect(LEDPlanner.changes(from: after, to: after).isEmpty)
    }

    @Test("Sans état précédent, tout est envoyé")
    func fullRefresh() {
        let (grid, _, _) = grid()
        let states = LEDPlanner.states(for: grid, playback: [:])
        #expect(LEDPlanner.changes(from: [:], to: states).count == 64)
    }
}
