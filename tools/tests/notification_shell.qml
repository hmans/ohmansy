//@ pragma Env QS_NO_RELOAD_POPUP=1
import Quickshell
import Ohmansy.Notifications

ShellRoot {
    NotificationService { focusedOutput: Quickshell.screens[0]?.name || "" }
}
