{
  description = "NixOS module for the NinjaOne remote access client (ncplayer)";

  outputs =
    { self, nixpkgs }:
    {
      nixosModules.default = import ./module.nix;
    };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
  };
}
