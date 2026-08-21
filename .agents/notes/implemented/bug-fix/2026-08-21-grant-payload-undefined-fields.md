# Agent Note: A grant payload commits through the properties a JSON round trip keeps

Status: implemented

English | [中文](2026-08-21-grant-payload-undefined-fields.zh.md)

## Problem

A GitHub Copilot sign-in ran the whole device flow — the human opened the verification page, entered the code, and approved the account — and then failed on the write, with `credentials-local: record "llm-pi-ai/github-copilot" payload holds a value JSON cannot represent` surfacing as pi-ai's `ModelsError: Credential store modify failed`. Nothing was stored, so the approval bought nothing and the next attempt had to start from a fresh device code.

The payload pi-ai returns for that provider ends `enterpriseUrl: enterpriseDomain`, and `enterpriseDomain` is `undefined` for an account that signs in through github.com rather than a GitHub Enterprise Server. That property is present and undefined rather than omitted, and `assertJsonValue` walks `Object.values()` and refuses `undefined` — so the failure reached every github.com Copilot account, which is the ordinary case, while the enterprise-server case it was written for went through.

## Decision

`toRecord` drops the object properties a JSON round trip drops, and the seam's guard stays exactly as strict as it was.

A grant payload's one constraint is that it survives a JSON round trip, and `JSON.stringify` omits an `undefined` property rather than encoding it. Such a property therefore already means "absent" in the stored record; refusing the whole write over it rejects a payload that round-trips fine. Only `undefined` is normalized — a `Date`, a function, a `bigint`, or an `undefined` array element still reaches the store and fails loudly, because those lose data rather than describing an absent field.

This also closes an asymmetry inside `toRecord` itself: its `api_key` branch already spreads `key` and `env` conditionally so an absent optional field is omitted rather than written as `undefined`, while the `grant` branch passed the library's object through verbatim. The two branches now agree about what an absent optional field means.

`llm-pi-ai` is where this belongs because it owns the translation between pi-ai's credential model and the record union; the seam holds a payload it never reads, so it cannot know which of a foreign format's fields are optional.

## Alternatives considered

**Accept `undefined` in `assertJsonValue`.** One line, and it fixes every plugin at once. It also weakens the guard for payloads whose `undefined` is a real loss rather than an absent field, and it moves a decision about one library's format into the seam that is defined not to interpret formats.

**Round-trip the payload through `JSON.parse(JSON.stringify(...))`.** This is the constraint stated literally, and it needs no rules of its own. It also silently rewrites more than it repairs — a `Date` becomes a string, an `undefined` array element becomes `null`, a `toJSON` method redirects the whole value — so a payload that genuinely could not be stored would be stored as something else instead of failing.

**Patch the credential inside `registerPiAiFlows`.** Deleting the known field where the login runs is the narrowest possible change. It fixes one provider by name and leaves the next library credential carrying an optional field to fail the same way, at the same point, after another human has already approved.

## Consequences

A Copilot sign-in through github.com commits its grant, and the stored payload holds what pi-ai refreshes against — the refresh half included — with the absent enterprise field simply not written. A route that names no `apiKeyEnv` then authenticates from that record and refreshes itself, which is what removes the external half-hourly token exchange the [Models guide](../../../../docs/user/guide/providers.md) documents for a subscription with no long-lived key.

The normalization is invisible to a payload that was already representable, so nothing else that stores a grant changes.

## Testing

`llm-pi-ai`'s auth suite stores an OAuth credential whose optional field is an explicit `undefined` and asserts the committed record holds the remaining fields without it, beside the existing test that an ordinary OAuth credential is kept verbatim with its refresh half. The failure this fixes was found by running the real flow against a live account, which is the only place the offending payload is produced.
