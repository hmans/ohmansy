{ config, lib, pkgs, ... }:
let
  segment = background: {
    style = lib.mkDefault "fg:#f5f5f5 bg:${background}";
  };
  languageSegments = [
    "c" "cpp" "elixir" "elm" "golang" "gradle" "haskell" "java"
    "julia" "maven" "nodejs" "bun" "nim" "rust" "scala"
  ];
in {
  options.ohmansy.fishStyle.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Use the Starship Pastel Powerline prompt with its required font.";
  };
  config = lib.mkIf (config.programs.fish.enable && config.ohmansy.fishStyle.enable) {
    fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
    programs.starship = {
      enable = lib.mkDefault true;
      presets = lib.mkDefault [ "pastel-powerline" ];
      # The preset specifies only backgrounds, so light terminals otherwise
      # replace its white lettering with their dark default foreground.
      settings = lib.mkIf (config.programs.starship.presets == [ "pastel-powerline" ]) (
        lib.genAttrs languageSegments (_: segment "#86BBD8") // {
          username = {
            style_user = lib.mkDefault "fg:#f5f5f5 bg:#9A348E";
            style_root = lib.mkDefault "fg:#f5f5f5 bg:#9A348E";
          };
          os = segment "#9A348E";
          directory = segment "#DA627D";
          git_branch = segment "#FCA17D";
          git_status = segment "#FCA17D";
          docker_context = segment "#06969A";
          time = segment "#33658A";
        }
      );
    };
  };
}
