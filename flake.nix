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
        pkgs: runtime:
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
              ./server/vllm
            ];
          };
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 -t $out/libexec/plamo-server serve.sh fetch-model.sh
            install -Dm644 -t $out/libexec/plamo-server model.env
            install -Dm644 -t $out/share/plamo-server config.example.env
            cp -r vllm $out/libexec/plamo-server/vllm
            makeWrapper $out/libexec/plamo-server/serve.sh $out/bin/plamo-server \
              --prefix PATH : ${
                pkgs.lib.makeBinPath (
                  runtime
                  ++ [
                    pkgs.coreutils
                    pkgs.curl
                  ]
                )
              }
            runHook postInstall
          '';
          meta = {
            description = "Serves PLaMo 3 Translate 0.8B over an OpenAI-compatible API";
            mainProgram = "plamo-server";
            platforms = systems;
          };
        };

      mkVllmServer =
        pkgs:
        pkgs.buildFHSEnv {
          name = "plamo-server";
          targetPkgs = p: [
            p.bash
            p.coreutils
            p.curl
            p.gcc
            p.python313
            p.stdenv.cc.cc.lib
            p.uv
            p.zlib
          ];
          runScript = pkgs.writeShellScript "plamo-server-vllm" ''
            export PLAMO_BACKEND=vllm
            export LD_LIBRARY_PATH=/run/opengl-driver/lib
            exec ${mkServer pkgs [ ]}/libexec/plamo-server/serve.sh "$@"
          '';
          meta = {
            description = "Serves PLaMo 3 Translate 0.8B NVFP4 on vLLM";
            mainProgram = "plamo-server";
            platforms = [ "x86_64-linux" ];
          };
        };
    in
    {
      packages = forAllSystems (
        pkgs:
        {
          default = mkServer pkgs [ pkgs.llama-cpp ];
          vulkan = mkServer pkgs [ pkgs.llama-cpp-vulkan ];
        }
        // nixpkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
          vllm = mkVllmServer pkgs;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
