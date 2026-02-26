{
  description = "Home Assistant Kubernetes deployment with kubenix";

  inputs = {
    kubenix.url = "github:hall/kubenix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, kubenix, nixpkgs, ...}: let
      # Generate manifests for each system
      mkManifests = system: (kubenix.evalModules.${system} {
        module = { ... }: {
          imports = [ ./home-assistant.nix ];
        };
      }).config.kubernetes.result;

      # Support common systems
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

in {
      packages = forAllSystems (system: {
        default = mkManifests system;
        manifests = mkManifests system;
      });
    };
}

