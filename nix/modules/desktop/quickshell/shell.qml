//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
import Quickshell

ShellRoot {
    NiriState { id: niri }
    AudioState { id: audioState }
    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
            niriState: niri
            audio: audioState
        }
    }
}
