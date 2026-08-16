{
  description = "DeepSeek Harness (dsh) — development shells for running and building the harness from source";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forEachSystem = builder: nixpkgs.lib.genAttrs systems (system: builder nixpkgs.legacyPackages.${system});

      # The Node majors CI covers, with the checksums nodejs.org publishes in
      # each release's SHASUMS256.txt.
      nodeReleases = {
        node22 = {
          version = "22.23.2";
          hashes = {
            "aarch64-darwin" = "5eff7a9011895aae3f29d06f167b84a62b028a591370c7cafb59103559fd26e1";
            "aarch64-linux" = "fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8";
            "x86_64-linux" = "d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307";
          };
        };
        node24 = {
          version = "24.19.0";
          hashes = {
            "aarch64-darwin" = "3f1cf157479c1480352083105e13faf9d008ede98e7e157746b6df940d197b94";
            "aarch64-linux" = "01443c1e1a29e531ccad5a46fefa6df490d2189c49f7955904aecdbb0fe86fdc";
            "x86_64-linux" = "14b342e71204f811bde6153be8e04b62aef63c236fef92b55f9c83154b409647";
          };
        };
        node26 = {
          version = "26.7.0";
          hashes = {
            "aarch64-darwin" = "595d2f934e081b82961d1a5fd41c6dbd0c5a952d9e8be5b4566ab754426968d2";
            "aarch64-linux" = "afc7a004018485092ac8985b817b0d5684472bd9472e0b57d2ab88737e50090d";
            "x86_64-linux" = "982aa24dd8be4c889c6a8ab337ddff3b0896645b20f4239356e80552c16277ee";
          };
        };
      };

      nodePlatforms = {
        "aarch64-darwin" = "darwin-arm64";
        "aarch64-linux" = "linux-arm64";
        "x86_64-linux" = "linux-x64";
      };
    in
    {
      devShells = forEachSystem (pkgs:
        let
          inherit (pkgs) lib;
          inherit (pkgs.stdenv.hostPlatform) isLinux system;

          # The official Node.js distribution, not the nixpkgs build. The Cordis
          # loader reaches Node's internal ESM loader through the prebuilt
          # `node-addon-require-builtin` addon, which recognizes only the getter
          # machine code the official builds emit; against a nixpkgs Node it
          # reports "Unsupported/no-getter", so the loader resolves bare plugin
          # names from vendor/loader's own directory instead of the composing
          # bundle's, where pnpm's isolated layout keeps that bundle's
          # dependencies. Booting from source then fails on the first
          # runtime-mounted entry, such as the directory picker's client surface.
          mkOfficialNode = release: pkgs.stdenv.mkDerivation {
            pname = "nodejs-official";
            inherit (release) version;

            src = pkgs.fetchurl {
              url = "https://nodejs.org/dist/v${release.version}/node-v${release.version}-${nodePlatforms.${system}}.tar.xz";
              sha256 = release.hashes.${system};
            };

            # Rewrites the ELF interpreter and RPATH so the binary also runs on
            # NixOS; the executable code the addon inspects stays untouched.
            nativeBuildInputs = lib.optional isLinux pkgs.autoPatchelfHook;
            buildInputs = lib.optionals isLinux [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -R . "$out"
              runHook postInstall
            '';
          };

          # Every shell carries the same toolchain; only the Node major and the
          # extra workflow packages differ. `pnpm` is a bootstrap: pnpm 10+
          # manages package-manager versions itself, so inside this repository it
          # delegates to the `packageManager` pin in package.json.
          harnessToolchain = [ pkgs.pnpm pkgs.git ]
            # node-gyp compiles the node-pty and koffi dependencies from source.
            ++ [ pkgs.python3 pkgs.gnumake ]
            # The Linux process-sandbox runner dsh-sandbox-local probes first.
            ++ lib.optional isLinux pkgs.bubblewrap;

          mkHarnessShell = { nodejs, extraPackages ? [ ] }: pkgs.mkShell {
            packages = [ nodejs ] ++ harnessToolchain ++ extraPackages;

            # Build against these headers instead of downloading a tarball per Node major.
            npm_config_nodedir = nodejs;

            shellHook = ''
              echo "DeepSeek Harness dev shell — node $(node --version), pnpm delegates to the repository pin"
              echo "Run from source: pnpm install && pnpm run build && pnpm dsh web"
            '';
          };

          engineShells = lib.mapAttrs
            (_: release: mkHarnessShell { nodejs = mkOfficialNode release; })
            nodeReleases;
        in
        engineShells // {
          default = engineShells.node26;

          # python/development.md drives the Python SDK workflows with uv.
          python = mkHarnessShell {
            nodejs = mkOfficialNode nodeReleases.node26;
            extraPackages = [ pkgs.uv ];
          };
        } // lib.optionalAttrs isLinux {
          # esbuild, oxlint, and lefthook ship dynamically linked ELF binaries
          # that expect /lib64/ld-linux-x86-64.so.2. This shell supplies that
          # loader for NixOS hosts without nix-ld; every other host uses `default`.
          fhs = (pkgs.buildFHSEnv {
            name = "dsh-fhs";
            targetPkgs = fhsPkgs: [ (mkOfficialNode nodeReleases.node26) ] ++ (with fhsPkgs; [
              pnpm
              git
              python3
              gnumake
              gcc
              bubblewrap
            ]);
            profile = ''
              export npm_config_nodedir="${mkOfficialNode nodeReleases.node26}"
            '';
            runScript = "bash";
          }).env;
        });
    };
}
