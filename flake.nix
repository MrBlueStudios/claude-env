{
  description = "claude-env — one Claude Code environment for four NixOS laptops (modules only; you bring nixpkgs and home-manager)";

  inputs = {
    # The web-design playbook lives in its own repo; pinned here so every laptop gets the same revision.
    claude-web-stack = {
      url = "git+ssh://git@github.com/MrBlueStudios/claude-web-stack?ref=main";
      flake = false;
    };
  };

  outputs =
    { self, claude-web-stack, ... }:
    {
      # home-manager: imports ./modules/home and points the playbook skill at the pinned checkout.
      # Set claude-env.user.name, pick claude-env.tier, and (Kitty users) claude-env.modes.enable.
      homeManagerModules.default =
        { ... }:
        {
          imports = [ ./modules/home ];
          claude-env.webDesignPlaybook = claude-web-stack;
        };
      homeManagerModules.claude-env = self.homeManagerModules.default;

      # NixOS: the managed-settings guard (PreToolUse hook + deny rules). Needs no options.
      nixosModules.default = ./modules/system/guard.nix;
      nixosModules.guard = self.nixosModules.default;
    };
}
