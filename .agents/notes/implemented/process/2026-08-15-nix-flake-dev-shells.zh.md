# Agent Note: Nix flake 开发 shell

Status: implemented

[English](2026-08-15-nix-flake-dev-shells.md) | 中文

## 问题

[README](../../../../README.md) 中从源码运行的路径假定宿主机已具备受支持范围内的 Node.js、启用了 Corepack 的 pnpm、Git 2.26+，以及 node-gyp 编译 `node-pty` 和 `koffi` 所需的 `python3`、`make` 和 C++ 工具链。逐台宿主机凑齐这些是读者抵达 `pnpm dsh web` 之前的第一道阻碍，它会与 [`engines`](../../../../package.json) 范围和 `packageManager` 锁定版本发生漂移；而在 NixOS 上它会直接失败，因为 npm 分发的预编译 ELF 二进制找不到 `/lib64/ld-linux-x86-64.so.2`。

## 决策

[flake.nix](../../../../flake.nix) 只导出开发 shell，并不为 Nix 打包 harness 本身。单个 `mkHarnessShell` 构造器以 Node.js derivation 和额外软件包为参数，因此 `node22`、`node24`、`node26`、`python` 和 `fhs` 共用同一份工具链清单，`default` 即 `node24`。这些 Node 主版本恰好是 CI 覆盖的版本，于是复现某个版本特有的 CI 失败只需切换 shell。

`pkgs.pnpm` 是引导程序，而非贡献者实际运行的版本：pnpm 10+ 自行管理包管理器版本，因此在本仓库中它会转交给 `packageManager` 锁定的版本，`pnpm --version` 报告的也是该版本。因此 flake 从不重述锁定的 pnpm 版本，调整该锁定版本也无需改动 flake。

这些 shell 将 `npm_config_nodedir` 设为自身的 Node.js，使 node-gyp 依据这些头文件构建，而不必为每个 Node 版本下载 tarball；Linux 上的 shell 还提供 `bwrap`，即 [`dsh-sandbox-local`](../../../../packages/sandbox/sandbox-local/README.md) 最先探测的运行器。仅限 Linux 的 `fhs` shell 用 `buildFHSEnv` 包裹同一份工具链，面向未启用 `nix-ld` 的 NixOS 宿主机——在那里 esbuild、oxlint 和 lefthook 分发的预编译 ELF 二进制需要一个常规的加载器路径。已提交的 [`.envrc`](../../../../.envrc) 使用 `use flake`，执行一次 `direnv allow` 后默认 shell 即可通过 direnv 加载。

## harness 所要求的 Node.js 构建

各 shell 安装的都是 nodejs.org 官方 tarball，并按系统以校验和固定，而非 nixpkgs 的 Node derivation。[`vendor/loader`](../../../../vendor/loader/src/internal.ts) 通过预编译的 `node-addon-require-builtin` 插件获取 Node 内部 ESM loader，该插件靠识别 getter 的编译后机器码来定位 `requireBuiltin`。nixpkgs 编译出的 Node 生成的代码不在其识别范围内，于是它以 `Unsupported/no-getter` 失败关闭；此时 `ModuleLoader.fromInternal()` 返回 undefined，[`Tree.import`](../../../../vendor/loader/src/config/tree.ts) 退回到在自身文件中求值的裸 `import(name)`，而不再依据组装该应用的 bundle 的 `baseUrl` 解析。

该回退路径从 `vendor/loader/` 向上解析插件名，而 pnpm 的隔离式布局并不会在那里暴露某个 bundle 的依赖。凡是在 `cordis.yml` 中写明的条目仍能解析，因为 `verify-cordis-config` 保证这些名字出现在解析器清单中，且工作区 `paths` 映射覆盖了 Host 包；运行期挂载的条目则不然。因此从源码启动 `dsh web` 会在 `directory-picker-auto` 挂载的客户端界面上失败——即 `@deepseek-ai/dsh-client-ui-directory-picker-native` 或其 `browse` 对应包，二者都未由 Client 聚合发布到 Host 的 `paths` 映射中。在 Linux 上，`autoPatchelfHook` 会改写官方二进制的解释器与 RPATH，使其同样能在 NixOS 上运行，同时不触碰该插件所检查的可执行代码。

`flake.lock` 固定 nixpkgs，因此在有人运行 `nix flake update` 之前工具链是可复现的。仓库的检查、CI workflow 和脚本都不使用该 flake：它是一条可选的入口路径，没有 Nix 的贡献者不受影响。

## 曾考虑的替代方案

**把 `dsh` 本身作为 flake 输出打包。** `pnpm.fetchDeps` derivation 能让 `nix run` 可用，但它需要一个每次锁文件变更都会失效的依赖哈希，并且必须复刻分阶段的 `tsc -b` 与 tsdown host/client 构建、打过补丁的 `node-pty` 以及 Landlock 原生启动器。对一个处于开发者预览、锁文件持续变动的仓库来说，这等于在权威构建之外再维护第二套构建系统。开发 shell 在不接管构建的前提下给出同样的工具链保证。

**改用 Corepack 而非 `pkgs.pnpm`。** 前置条件写的是启用了 Corepack 的 pnpm，而 Corepack 读取的是同一个 `packageManager` 锁定版本。它需要 `corepack enable` 把 shim 写入某个可写目录，该目录还必须排在 `PATH` 其余部分之前，这类 shell hook 状态在不同宿主机上有不同的失效方式。pnpm 自带的版本管理用一个普通软件包就能抵达完全相同的锁定版本。

**使用 nixpkgs 的 Node derivation。** 对 flake 来说这是显而易见的选择，无需校验和、无需抓取 tarball，也无需 `autoPatchelfHook`。但它无法从源码运行 harness：`node-addon-require-builtin` 会拒绝该构建，随后 loader 的解析回退会在第一个运行期挂载的条目上失败。固定官方 tarball 的代价是每个 Node 主版本三个校验和，换来的是一个 `pnpm dsh web` 真正能启动的 shell。

**只在文档里写明 Node 版本，由贡献者自行安装。** 前置条件已经给出受支持的版本范围，因此 flake 只提供 pnpm、Git 和原生工具链即可。但这会重新引入 flake 本要消除的逐台宿主机拼装工作，还会掩盖本仓库更尖锐的约束：仅有版本范围并不够，构建方式与版本同样重要。

**只提供一个 shell，不覆盖 CI 的 Node 矩阵。** 单个 `default` shell 体量更小，但仓库支持 22.19+、24 和 26，届时排查某个 Node 版本特有失败的贡献者仍要手工拼装其他主版本——重新引入了 flake 本要消除的问题。有了发行版本表，每增加一个主版本只是一个条目。

**无视 NixOS 上预编译二进制的失败。** 只在文档里写明 `programs.nix-ld.enable` 代码更少，但这会让 flake 的主要承诺取决于贡献者未必能掌控的系统级设置。`fhs` shell 是同一文件内自足的兜底方案。

## 后果

Nix 宿主机用 `nix develop` 加上 README 中既有的命令即可得到可用的检出目录，Node 主版本、Git 和原生构建工具链都来自 `flake.lock` 而非宿主机状态。固定官方 Node tarball 会在 flake 中为每个受支持主版本引入三个校验和，升级 Node 时需手工修改；其余部分仍由 nixpkgs 治理。仓库因此多了一份可能与 `engines` 范围及文档所列前置条件不一致的工具链描述；缓解办法是 flake 把 pnpm 版本完全交给锁定机制，并只声明 CI 已覆盖的 Node 主版本。CI 不测试 Nix，因此漂移只会在贡献者使用该 flake 时暴露，不会更早。
