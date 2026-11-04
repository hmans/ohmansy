# Reference code

The compositor starts from Smithay's smallvil example at the `v0.7.0` tag:
https://github.com/Smithay/smithay/tree/v0.7.0/smallvil

The protocol handlers, pointer grabs, input handling, and event-loop plumbing
are adapted from that example. See `LICENSE-SMITHAY` for its MIT notice.
The ohmansy experiment adds scrolling columns and workspaces, fixed 2x rendering
preferences with separate display scaling, GPU buffer imports, popup and selection
support, isolated application launchers, private IPC, and native client trials.
