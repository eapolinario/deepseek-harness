# Agent Note: Nix flake development shells

Status: implemented

English | [中文](2026-08-15-nix-flake-dev-shells.zh.md)

## Problem

The source-checkout path in the [README](../../../../README.md) assumes a host that already carries a Node.js in the supported range, a Corepack-enabled pnpm, Git 2.26+, and the `python3`, `make`, and C++ toolchain that node-gyp compiles `node-pty` and `koffi` with. Assembling that per host is the first thing between a reader and `pnpm dsh web`, it drifts from the [`engines`](../../../../package.json) range and the `packageManager` pin, and on NixOS it fails outright because npm-distributed prebuilt ELF binaries find no `/lib64/ld-linux-x86-64.so.2`.

## Decision

[flake.nix](../../../../flake.nix) exports development shells only; the harness itself is not packaged for Nix. One `mkHarnessShell` builder parameterizes the Node.js derivation and extra packages, so `node22`, `node24`, `node26`, `python`, and `fhs` share a single toolchain list, and `default` is `node24`. The Node majors are exactly the ones CI covers, which makes reproducing a version-specific CI failure a shell selection.

`pkgs.pnpm` is a bootstrap, not the version contributors run: pnpm 10+ manages package-manager versions itself, so within this repository it delegates to the `packageManager` pin and `pnpm --version` reports it. The flake therefore never restates the pinned pnpm version, and a pin bump needs no flake change.

The shells set `npm_config_nodedir` to their own Node.js so node-gyp builds against those headers rather than downloading a tarball per Node version, and Linux shells add `bwrap`, the runner [`dsh-sandbox-local`](../../../../packages/sandbox/sandbox-local/README.md) probes first. The Linux-only `fhs` shell wraps the same toolchain in `buildFHSEnv` for NixOS hosts without `nix-ld`, where esbuild, oxlint, and lefthook ship prebuilt ELF binaries that need a conventional loader path. A committed [`.envrc`](../../../../.envrc) with `use flake` makes the default shell load through direnv after one `direnv allow`.

## The Node.js build the harness requires

Every shell installs the official nodejs.org tarball, checksum-pinned per system, instead of the nixpkgs Node derivation. [`vendor/loader`](../../../../vendor/loader/src/internal.ts) obtains Node's internal ESM loader through the prebuilt `node-addon-require-builtin` addon, which locates `requireBuiltin` by recognizing the getter's compiled machine code. A nixpkgs-compiled Node emits code that addon does not recognize, so it fails closed with `Unsupported/no-getter`; `ModuleLoader.fromInternal()` then returns undefined and [`Tree.import`](../../../../vendor/loader/src/config/tree.ts) falls back to a bare `import(name)` evaluated from its own file rather than resolving against the composing bundle's `baseUrl`.

That fallback resolves plugin names from `vendor/loader/` upward, where pnpm's isolated layout does not expose a bundle's dependencies. Every entry named in a `cordis.yml` still resolves, because `verify-cordis-config` keeps those names in the resolver manifest and the workspace `paths` map covers Host packages; an entry mounted at runtime does not. Booting `dsh web` from source therefore fails on the client surface `directory-picker-auto` mounts — `@deepseek-ai/dsh-client-ui-directory-picker-native` or its `browse` counterpart, neither of which the Client aggregate publishes to the Host `paths` map. On Linux, `autoPatchelfHook` rewrites the official binary's interpreter and RPATH so it also runs on NixOS, leaving the executable code the addon inspects untouched.

`flake.lock` pins nixpkgs, so the toolchain is reproducible until someone runs `nix flake update`. Nothing in the repository's gates, CI workflows, or scripts consumes the flake: it is an optional entry path, and a contributor without Nix is unaffected.

## Alternatives considered

**Package `dsh` itself as a flake output.** A `pnpm.fetchDeps` derivation would make `nix run` work, but it requires a vendored-dependency hash that every lockfile change invalidates, and it would have to reproduce the multi-phase `tsc -b` and tsdown host/client build, the patched `node-pty`, and the Landlock native launcher. That is a second build system to maintain beside the authoritative one, for a repository in developer preview whose lockfile changes constantly. Development shells give the toolchain guarantee without owning the build.

**Ship Corepack instead of `pkgs.pnpm`.** The prerequisites name a Corepack-enabled pnpm, and Corepack reads the same `packageManager` pin. It needs `corepack enable` to write shims into a writable directory that must then precede the rest of `PATH`, which is shell-hook state that breaks differently per host. pnpm's own version management reaches the identical pinned version with a plain package.

**Use the nixpkgs Node derivation.** It is the obvious choice for a flake and needs no checksums, no tarball fetch, and no `autoPatchelfHook`. It also cannot run the harness from source: `node-addon-require-builtin` rejects that build, and the loader's resolution fallback then fails on the first runtime-mounted entry. Pinning the official tarball costs three checksums per Node major and buys a shell in which `pnpm dsh web` actually boots.

**Document a Node version and let contributors install it.** The prerequisites already name a supported range, so the flake could ship only pnpm, Git, and the native toolchain. That reinstates the per-host assembly the flake exists to remove, and it hides the sharper constraint this repository has: the range alone is not sufficient, because the build matters as much as the version.

**One shell instead of the CI Node matrix.** A single `default` shell is smaller, but the repository supports 22.19+, 24, and 26, and a contributor debugging a Node-version-specific failure would then hand-assemble the other majors — reintroducing the problem the flake exists to remove. The release table makes each additional major one entry.

**Ignore NixOS prebuilt-binary failures.** Documenting `programs.nix-ld.enable` and stopping there is less code, but it makes the flake's main promise conditional on a system-level setting a contributor may not control. The `fhs` shell is a self-contained fallback in the same file.

## Consequences

A Nix host reaches a working checkout with `nix develop` and the README's existing commands, and the Node major, Git, and native-build toolchain come from `flake.lock` rather than host state. Pinning the official Node tarball puts three checksums per supported major in the flake, and a Node bump edits them by hand; nixpkgs governs everything else. The repository gains a second toolchain description that can disagree with the `engines` range and the documented prerequisites; the mitigation is that the flake delegates the pnpm version entirely and states the Node majors CI already covers. Nix is not tested in CI, so drift surfaces when a contributor uses the flake, not before.
