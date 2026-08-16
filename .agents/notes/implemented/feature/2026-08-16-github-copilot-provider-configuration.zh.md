# Agent Note: 作为配置项支持的 GitHub Copilot 提供方

Status: implemented

[English](2026-08-16-github-copilot-provider-configuration.md) | 中文

## 问题

Copilot 订阅是许多贡献者本就拥有的 LLM 访问途径，但它并不契合模型页提供的那个字段。它没有长期有效的密钥：通过编辑器登录会在 `~/.config/github-copilot/apps.json` 留下一个 GitHub OAuth token，而 `https://api.github.com/copilot_internal/v2/token` 会据此铸造一个约三十分钟后过期的 token。另有两处细节会让初次尝试失败——铸造响应会指明该账户自己的 API 主机，企业订阅得到的是企业域名而非目录默认值；而 Copilot 会拒绝任何不带编辑器标识的请求，并报告 `missing Editor-Version header for IDE auth`。

## 决策

Copilot 以配置方式在既有 seam 之上得到支持，[模型指南](../../../../docs/user/guide/providers.md)承载具体步骤。[`dsh-llm-pi-ai`](../../../../packages/llm/llm-pi-ai/README.md) 已经暴露该提供方所需的三个字段：用于铸造 token 的 `apiKeyEnv`、用于账户 API 主机的 `baseURL`，以及用于 `Copilot-Integration-Id` 的 `headers`。`github-copilot` 是一条声明了 api-key 认证方式的、已安装的 pi-ai 目录路由，因此 `catalogProviderTakesApiKey` 接纳它，适配器对它的认证方式与任何其他带密钥的路由完全一致。

token 的有效期由凭据 seam 处理，而非由新代码处理。[`dsh-credentials-local`](../../../../packages/credentials/credentials-local/README.md) 对 `$DSH_HOME/.credentials.yaml` 热重载，因此重新执行一次交换即可在服务器运行期间替换存储值；无需重启，不经过进程环境层，`settings.yaml` 中也不出现密文。

本次没有随附任何适配器改动。pi-ai 提供了带设备流与刷新的 `githubCopilotOAuth`，但 `dsh-llm-pi-ai` 有意不持有 OAuth 凭据存储、也不运行登录流程，其 [catalog](../../../../packages/llm/llm-pi-ai/src/catalog.ts) 与 [provider](../../../../packages/llm/llm-pi-ai/src/provider.ts) 模块已将此表述为自有限制。正是 Copilot 的 api-key 方式让它无需越过这条界线即可接入。

## 曾考虑的替代方案

**让 `dsh-llm-pi-ai` 驱动 pi-ai 的 OAuth 方式。** 这是无需外部铸造的版本：设备流登录一次即可自行刷新。它需要在适配器内引入 OAuth 凭据存储、登录交互和刷新归属方——正是该模块记载为缺失的能力，而且这会牵涉到 OAuth 凭据存放位置这一超出单个提供方范围的决策。api-key 路径今天已经能承载 Copilot，因此该存储可以等到某个没有 api-key 方式的提供方确有需要时再设计。

**在插件内铸造 token。** 凭据提供方插件或 LLM 插件可以按请求交换编辑器 OAuth token 并保持其新鲜。它换来自动刷新，代价是引入一个读取另一应用凭据文件、并在请求路径上承担一次网络交换的包；而同样的刷新用一个定时任务加一条文档化命令即可完成。

**改为推荐使用代理。** 在自定义提供方前面放一个 OpenAI 兼容的 Copilot 代理，完全不需要任何 Copilot 专属字段。但它增加了一个需要运行并信任的进程，横亘在 harness 与 API 之间，而且会掩盖端点与请求头要求，而不是把它们讲清楚。

**什么都不写，交给自定义提供方表单。** 该表单本就接受 base URL 和密钥，执着的用户确实可能自行摸索到同一结果。但他们无法从表单中得知铸造端点、企业主机、必需的请求头或 token 有效期，而每一次失败都表现为一条含义不明的提供方拒绝信息。

## 后果

拥有 Copilot 订阅的贡献者按文档中的命令即可完成配置，并在该路由上获得目录中的模型，凭据与其他所有密钥存放在同一份文档中。代价是该步骤是手工的：除了提供方的拒绝信息之外，harness 不会察觉 token 已过期，因此在重新执行交换之前，陈旧凭据看起来就像一次提供方故障。非编辑器用途受 Copilot 自身条款约束，指南对此如实说明，而不代为决定。
