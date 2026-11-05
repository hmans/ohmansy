{ lib, stdenvNoCC, fetchurl, installShellFiles }:
let
  releases = {
    x86_64-linux = {
      platform = "linux-x64-musl";
      hash = "sha256-7YmG2glwj6e70V7iY2dfwkiMbAkhMs9T9FICN7Ydl54=";
    };
    aarch64-linux = {
      platform = "linux-arm64-musl";
      hash = "sha256-ql3njkbJAeW31ROank283AMBMCwRFnW/jhuHstJbRqw=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system};
in stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mise";
  version = "2026.11.0";

  src = fetchurl {
    url = "https://github.com/jdx/mise/releases/download/v${finalAttrs.version}/mise-v${finalAttrs.version}-${release.platform}.tar.xz";
    inherit (release) hash;
  };
  nativeBuildInputs = [ installShellFiles ];
  dontConfigure = true;
  dontBuild = true;
  # Preserve the static upstream executables.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/mise "$out/bin/mise"
    install -Dm755 bin/mise.d "$out/bin/mise.d"
    installManPage man/man1/mise.1
    mkdir -p "$out/lib/mise"
    touch "$out/lib/mise/.disable-self-update"
    runHook postInstall
  '';

  meta = {
    description = "Dev tools, environment variables, and tasks";
    homepage = "https://mise.jdx.dev";
    license = lib.licenses.mit;
    platforms = builtins.attrNames releases;
    mainProgram = "mise";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
