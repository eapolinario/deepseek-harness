# Agent Note：授权载荷按 JSON 往返所保留的属性提交

Status: implemented

[English](2026-08-21-grant-payload-undefined-fields.md) | 中文

## 问题

一次 GitHub Copilot 登录跑完了整个设备流——用户打开验证页、输入代码并批准了账户——随后却在写入阶段失败，报出 `credentials-local: record "llm-pi-ai/github-copilot" payload holds a value JSON cannot represent`，并以 pi-ai 的 `ModelsError: Credential store modify failed` 呈现。没有任何东西被存下，因此这次批准毫无所得，下一次尝试只能从新的设备代码重新开始。

pi-ai 为该提供方返回的载荷以 `enterpriseUrl: enterpriseDomain` 结尾，而对于通过 github.com（而非 GitHub Enterprise Server）登录的账户，`enterpriseDomain` 为 `undefined`。该属性是存在且取值为 undefined，而非被省略，`assertJsonValue` 会遍历 `Object.values()` 并拒绝 `undefined`——于是这一失败波及每个 github.com Copilot 账户，也就是最常见的那种，反倒是它原本针对的企业服务器场景能够通过。

## 决策

`toRecord` 丢弃 JSON 往返本就会丢弃的对象属性，而 seam 自身的守卫维持原有严格程度。

授权载荷唯一的约束是能经受一次 JSON 往返，而 `JSON.stringify` 会省略取值为 `undefined` 的属性而非将其编码。因此这样的属性在存下的记录中本就意味着「不存在」；为它拒绝整次写入，等于拒绝了一个往返完全正常的载荷。只有 `undefined` 会被规范化——`Date`、函数、`bigint` 或数组中取值为 undefined 的元素仍会抵达存储并大声失败，因为它们是数据丢失，而不是在描述一个缺省字段。

这同时消除了 `toRecord` 内部的一处不对称：它的 `api_key` 分支早已用条件展开处理 `key` 与 `env`，使缺省的可选字段被省略而不是写成 `undefined`，而 `grant` 分支却把库的对象原样透传。现在两个分支对「缺省的可选字段」含义一致。

这属于 `llm-pi-ai` 的职责，因为它拥有 pi-ai 凭据模型与记录联合之间的转换；seam 持有的是一个它从不读取的载荷，因而无从知晓某个外部格式的哪些字段是可选的。

## 备选方案

**让 `assertJsonValue` 接受 `undefined`。** 只需一行，且一次性修好所有插件。但它也会为那些 `undefined` 确属数据丢失而非缺省字段的载荷削弱守卫，并把关于某个库格式的决策挪进一个被定义为不解释格式的 seam。

**用 `JSON.parse(JSON.stringify(...))` 对载荷做一次往返。** 这是对该约束最字面的实现，且无需自定规则。但它悄悄改写的东西多于它修复的——`Date` 变成字符串，数组中 undefined 的元素变成 `null`，`toJSON` 方法会改写整个值——于是一个确实无法存储的载荷会被存成别的东西，而不是失败。

**在 `registerPiAiFlows` 内部修补该凭据。** 在登录发生处删掉那个已知字段是可能的最小改动。它按名字修好一个提供方，而下一个带可选字段的库凭据仍会以同样方式、在同样的位置、在又一位用户批准之后失败。

## 影响

通过 github.com 的 Copilot 登录会提交其授权，存下的载荷持有 pi-ai 据以刷新的内容——包括刷新那一半——而缺省的企业字段则根本不会被写入。此后，一条未指定 `apiKeyEnv` 的路由便可凭该记录完成认证并自行刷新，这正是[模型指南](../../../../docs/user/guide/providers.zh.md)为「没有长期密钥的订阅」所记载的、每半小时一次的外部 token 交换得以取消的原因。

对于本就可表示的载荷，这项规范化是不可见的，因此其他存储授权的路径均不受影响。

## 测试

`llm-pi-ai` 的 auth 套件会存入一个可选字段为显式 `undefined` 的 OAuth 凭据，并断言提交后的记录持有其余字段而不含该字段，与既有的「普通 OAuth 凭据连同其刷新那一半被原样保留」用例并列。本次修复的故障是通过对真实账户运行真实流程发现的，而那也是唯一会产生该问题载荷的地方。
