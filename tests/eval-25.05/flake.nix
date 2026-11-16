# Evaluation test: does claude-env still evaluate as a consumer on NixOS/home-manager 25.05?
# Run with: just test   (nix eval only; nothing is built or switched)
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-env = {
      url = "path:../..";
      inputs.claude-web-stack.follows = "web-stack";
    };
    web-stack = {
      url = "path:../web-stack-stub";
      flake = false;
    };
  };
  outputs =
    { nixpkgs, home-manager, claude-env, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      hm = extra: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ claude-env.homeManagerModules.default extra ];
      };
    in
    {
      # A base-tier friend on a fresh machine: no modes, no company connectors.
      homeConfigurations.base = hm {
        home.username = "kish"; home.homeDirectory = "/home/kish"; home.stateVersion = "25.05";
        claude-env.user.name = "Kish";
      };
      # Blitsol tier with everything switched on.
      homeConfigurations.blitsol = hm {
        home.username = "leon-new"; home.homeDirectory = "/home/leon-new"; home.stateVersion = "24.11";
        claude-env = {
          user.name = "Léon"; tier = "blitsol"; modes.enable = true;
          user.notes = "- Home directory: /home/leon-new";
        };
      };
      nixosConfigurations.guard = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ claude-env.nixosModules.default {
          fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
          boot.loader.grub.enable = false; system.stateVersion = "24.11";
        } ];
      };
    };
}
