# Redistributing an ISO

Building and testing an ISO locally is separate from publishing it. The offline
installer bundles binary dependencies in its Nix store; those packages retain
their individual licenses. Nixpkgs's own license does not cover all their contents.

Before public binary distribution:

- Inventory the exact ISO store closure, including the live environment, installed
  system, firmware, fonts, and applications. Record package versions, source
  revisions, license texts, notices, and any package-specific conditions.
- Provide corresponding source as required by each license, including patches
  and build scripts. Check the chosen distribution method against the actual
  license version. A project source archive or links to upstream repositories
  alone do not establish compliance for all bundled binaries.
- Check redistribution permissions for firmware and any unfree packages.
  `allowUnfree` is an evaluation setting, not permission to redistribute.
- Review branding and trademark conditions independently of copyright licenses.
  Keep the resulting source/notices bundle tied to the exact binary checksums.

`tools/release/package-iso.py` currently creates `ohmansy-source.tar.gz` from the
Ohmansy build configuration. It is **not** a complete corresponding-source bundle
for the ISO's dependencies. No full dependency license audit or source bundle is
provided by the offline installer implementation. Public release needs that work.

The generic installer excludes the separate proprietary NVIDIA userspace profile
and disables the speech daemon and voice collection. It still includes firmware;
do not infer that every included dependency has the same redistribution terms.

References: [Nixpkgs license metadata](https://nixos.org/manual/nixpkgs/unstable/#sec-meta-license),
[GNU GPL FAQ on private changes](https://www.gnu.org/licenses/gpl-faq.en.html#GPLRequireSourcePostedPublic),
and [corresponding source distribution](https://www.gnu.org/licenses/gpl-faq.en.html#DistributingSourceIsInconvenient).
