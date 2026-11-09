{
  description = "PLaMo 3 Translate 0.8B server";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkServer =
        pkgs: llama-cpp:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "plamo-server";
          version = "0.1.0";
          src = pkgs.lib.fileset.toSource {
            root = ./server;
            fileset = pkgs.lib.fileset.unions [
              ./server/serve.sh
              ./server/fetch-model.sh
              ./server/model.env
              ./server/config.example.env
            ];
          };
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 -t $out/libexec/plamo-server serve.sh fetch-model.sh
            install -Dm644 -t $out/libexec/plamo-server model.env
            install -Dm644 -t $out/share/plamo-server config.example.env
            makeWrapper $out/libexec/plamo-server/serve.sh $out/bin/plamo-server \
              --prefix PATH : ${
                pkgs.lib.makeBinPath [
                  llama-cpp
                  pkgs.coreutils
                  pkgs.curl
                ]
              }
            runHook postInstall
          '';
          meta = {
            description = "Serves PLaMo 3 Translate 0.8B over an OpenAI-compatible API";
            mainProgram = "plamo-server";
            platforms = systems;
          };
        };
    in
    {
      packages = forAllSystems (pkgs: {
        default = mkServer pkgs pkgs.llama-cpp;
        vulkan = mkServer pkgs pkgs.llama-cpp-vulkan;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
