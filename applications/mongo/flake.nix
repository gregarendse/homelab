{
  description = "MongoDB backing store for UniFi Controller";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    kubenix = {
      url = "github:hall/kubenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, kubenix }: let
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

    mkManifests = system: (kubenix.evalModules.${system} {
      module = { ... }: {
        imports = [ ./mongo.nix ];
      };
    }).config.kubernetes.result;
  in {
    packages = nixpkgs.lib.genAttrs systems (system: {
      default = mkManifests system;
      manifests = mkManifests system;
    });
  };
}
