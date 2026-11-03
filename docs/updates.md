# Updating Ohmansy

An OS update creates a NixOS generation on the existing disk. It does not replace
the disk, recreate accounts, or reset home directories. The factory image is for
new installations; replacing an app's bundled factory is not a guest OS update.

## Configuration ownership

New installations create these files in `/etc/nixos`:

| File | Purpose |
| --- | --- |
| `flake.nix` | Ohmansy release reference and local module imports |
| `flake.lock` | Exact release and dependency versions |
| `configuration.nix` | Machine settings and installation `system.stateVersion` |
| `hardware-configuration.nix` | Boot and disk settings |
| `owner.nix` | Account declaration; the factory setup writes this file |
| `preferences.nix` | User package choices and overrides |

The physical installer currently writes its account declaration in
`configuration.nix` and leaves `owner.nix` available for later account settings.
Passwords remain in the system account database, not Nix files.

The initial release is a pinned store-path snapshot of the source used to build
the image. The installed system retains that source as a dependency. Future
releases come from `github:hmans/ohmansy`. Nixpkgs follows the release's own lock;
the updater does not independently advance Nixpkgs.

## Prepare and apply

Use a published release tag or a full 40-character commit ID. The tag below is
an example, not a claim that this release exists:

```sh
sudo ohmansy-update prepare v0.2.0
```

Preparation copies local configuration into a private working directory, changes
the release reference there, resolves the lock, and builds the combined system.
The current configuration, boot default, accounts, and session remain unchanged.
Nix downloads cached packages where available and builds missing packages locally.
This command requires network access for a new upstream release.
The managed configuration must use regular files. Symlink-managed configurations
can use `nixos-rebuild` directly; the updater rejects symlinks rather than risk
writing through them or building from mutable files outside its snapshot.

The command prints an update ID. Apply it using that ID:

```sh
sudo ohmansy-update apply update-EXAMPLE
```

Apply checks that neither local configuration nor the prepared copy changed. It
registers the exact built system as a generation and selects it for the next
boot. Only `flake.nix` and `flake.lock` are promoted into `/etc/nixos`; other local
modules stay in place. Restart when ready. There is no automatic restart or live
desktop activation.

If you edit local configuration after preparation, prepare again. If the build
fails, fix the reported configuration or dependency issue and prepare again.
On a boot-selection error, the updater attempts to restore the previous profile
and boot default and reports any recovery failure. A power cut during apply can
still require recovery; the command is not a filesystem transaction.

Prepared builds and prior pin files remain under `/var/lib/ohmansy/updates`.
These root-only directories can contain private configuration. Their `system`
links retain prepared builds against garbage collection. There is no automatic
retention cleanup yet; do not delete the recovery directory while diagnosing an
update failure.

## Rollback

Choose an older NixOS generation in the boot menu, or prepare the previous
generation from a working session:

```sh
sudo nixos-rebuild boot --rollback
```

Then restart. A generation rollback changes the OS, not the source files in
`/etc/nixos`. To make subsequent rebuilds use the earlier release, restore
`flake.nix` and `flake.lock` from that update's `previous` directory, after
checking for local edits made since the update. The `previous-system` file
records the preceding system path.

Rollback does not reverse application data migrations or restore deleted user
files. Keep backups separately. Do not routinely change `system.stateVersion`
when selecting a new release.

## Existing installations with copied modules

The updater deliberately rejects the older generated flake without an
`inputs.ohmansy.url` declaration. It does not guess how to rewrite a customized
machine. Migrate the configuration once; no disk reset is needed:

1. Back up `/etc/nixos` and record the current system generation.
2. Add `inputs.ohmansy.url = "github:hmans/ohmansy/FULL_COMMIT_ID";` to the
   flake, selecting a commit that includes the update module. Set
   `inputs.nixpkgs.follows = "ohmansy/nixpkgs";` instead of its old URL.
3. Add `ohmansy` to the outputs arguments. Replace the copied desktop/default
   module import with `ohmansy.nixosModules.default`. For the VM, also import
   `ohmansy.nixosModules.vm`.
4. Keep the existing disk and boot settings in a local hardware module. With the
   old `persistent-vm.nix`, copy its contents to that local module and remove
   only its `imports` of the copied default and VM modules. Keep its existing
   `system.stateVersion`, filesystem labels, resize settings, and boot settings.
5. Retain the owner module and every local preference or development module in
   the flake's module list. Add a local `preferences.nix` if needed. Include
   `{ system.extraDependencies = [ ohmansy.outPath ]; }` to retain release source.
6. Resolve the lock with `sudo nix flake lock path:/etc/nixos`. Build first with
   `sudo nixos-rebuild build --flake path:/etc/nixos#ohmansy`. Review any errors
   before selecting the new generation with `nixos-rebuild boot` and restarting.

After migration, normal releases use the prepare/apply commands above. Never
activate the factory or live-image configuration on an existing installation.

## Scope

This is a manual release update path, not an automatic release channel, graphical
updater, binary-cache service, or app self-updater. It uses ordinary NixOS boot
generations and leaves the ext4 disk layout unchanged. No impermanence is enabled.
