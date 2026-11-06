{ config, lib, ... }:
let
  skills = {
    ohmansy-maintenance = ../../skills/ohmansy-maintenance;
  };
  # Agent Skills defines the content format; discovery paths belong to clients.
  locations = [
    "ohmansy/skills"
    "codex/skills"
    "claude-code/.claude/skills"
  ];
in
{
  options.ohmansy.agentSkills.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Install shared ohmansy maintenance skills for local agents.";
  };

  config = lib.mkIf config.ohmansy.agentSkills.enable {
    environment.etc = lib.listToAttrs (lib.concatMap (location:
      lib.mapAttrsToList (name: source: {
        name = "${location}/${name}";
        value = { inherit source; };
      }) skills
    ) locations);
  };
}
