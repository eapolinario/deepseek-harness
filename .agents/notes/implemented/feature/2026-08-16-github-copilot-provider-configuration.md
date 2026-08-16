# Agent Note: GitHub Copilot as a configured provider

Status: implemented

English | [中文](2026-08-16-github-copilot-provider-configuration.zh.md)

## Problem

A Copilot subscription is the LLM access many contributors already have, but it does not fit the field the Models page offers. There is no long-lived key: an editor sign-in leaves a GitHub OAuth token in `~/.config/github-copilot/apps.json`, and `https://api.github.com/copilot_internal/v2/token` mints from it a token that expires in about thirty minutes. Two further details defeat a first attempt — the minting reply names the account's own API host, which is an enterprise domain for enterprise subscriptions rather than the catalog default, and Copilot rejects any request without editor identification, reporting `missing Editor-Version header for IDE auth`.

## Decision

Copilot is supported as configuration over the existing seams, and the [Models guide](../../../../docs/user/guide/providers.md) carries the recipe. [`dsh-llm-pi-ai`](../../../../packages/llm/llm-pi-ai/README.md) already exposes the three fields the provider needs: `apiKeyEnv` for the minted token, `baseURL` for the account's API host, and `headers` for `Copilot-Integration-Id`. `github-copilot` is an installed pi-ai catalog route that declares an api-key method, so `catalogProviderTakesApiKey` admits it and the adapter authenticates it exactly like any other keyed route.

The token's lifetime is handled by the credentials seam rather than by new code. [`dsh-credentials-local`](../../../../packages/credentials/credentials-local/README.md) hot-reloads `$DSH_HOME/.credentials.yaml`, so re-running the exchange replaces the stored value under a running server; no restart, no process-environment layer, and no secret in `settings.yaml`.

No adapter change accompanies this. pi-ai ships `githubCopilotOAuth` with a device flow and refresh, but `dsh-llm-pi-ai` deliberately holds no OAuth credential store and runs no login flow, which its [catalog](../../../../packages/llm/llm-pi-ai/src/catalog.ts) and [provider](../../../../packages/llm/llm-pi-ai/src/provider.ts) modules state as an owned limitation. Copilot's api-key method is what makes it reachable without crossing that line.

## Alternatives considered

**Teach `dsh-llm-pi-ai` to drive pi-ai's OAuth method.** This is the version that needs no external minting: the device flow logs in once and refreshes itself. It requires an OAuth credential store, a login interaction, and a refresh owner inside the adapter — the capability that module documents as absent, and a decision about where OAuth credentials live that reaches past one provider. The api-key path already carries Copilot today, so the store can be designed when a provider without one requires it.

**Mint the token inside a plugin.** A credentials provider or LLM plugin could exchange the editor OAuth token per request and keep it warm. It buys automatic refresh at the cost of a package that reads another application's credential file and owns a network exchange on the request path; the same refresh is a timer over one documented command.

**Document a proxy instead.** An OpenAI-compatible Copilot proxy in front of a custom provider needs no Copilot-specific fields at all. It adds a process to run and trust between the harness and the API, and it hides the endpoint and header requirements rather than stating them.

**Say nothing and let the custom-provider form carry it.** The form already accepts a base URL and key, so a determined user could arrive at the same place. They cannot discover the minting endpoint, the enterprise host, the required header, or the token lifetime from it, and each failure surfaces as an opaque provider rejection.

## Consequences

A contributor with a Copilot subscription configures it from the documented commands and gets the catalog's models on the route, with the credential stored in the same document as every other key. The cost is that the recipe is manual: nothing in the harness notices an expired token beyond the provider's rejection, so a stale credential looks like a provider failure until the exchange is repeated. Copilot's own terms govern non-editor use, which the guide states rather than decides.
