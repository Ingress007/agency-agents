# 🧭 The Agency × Pi (pi-coding-agent) — 使用说明

> Pi 并不在 The Agency 上游支持的集成列表里（上游支持 Claude Code / Codex / Gemini CLI / Cursor 等）。
> 本仓库新增了一个适配脚本，把 232 个 agent 人格转换成 **Pi subagent** 格式，
> 安装后即可在 Pi 里以子代理方式按需调用它们。

---

## 一、项目是什么（一句话）

**The Agency** = 232 个精心编写的 AI「agent 人格」，分 16 个部门
（engineering / marketing / sales / design / security / testing / gis / game-development 等）。
每个 agent 是一个 Markdown 文件：`name` + `description` 元数据 + 一大段「我是谁 / 我的能力 / 我的产出 / 我的规则」的人格正文。

在 Pi 里，它最自然的落点是 **Pi 的 subagent 机制**：
每个 The Agency agent → 一个 Pi 子代理，正文直接作为子代理的 system prompt（`systemPromptMode: replace`）。

---

## 二、Pi 侧的原理

Pi 的 subagent（由 `pi-subagents` 包提供）从这些目录发现自定义代理：

- 用户级（本机所有项目可用）：`~/.pi/agent/agents/`（旧）或 `~/.agents/`（新，规范路径）
- 项目级：项目根的 `.pi/agents/` 或 `.agents/`

代理文件格式 = Markdown + YAML frontmatter，必需字段只有 `name` 和 `description`：

```markdown
---
name: engineering-frontend-developer
description: Expert frontend developer ...
aliases: Frontend Developer          # 可选：用显示名也能选中
tools: read, grep, find, ls, bash     # 子代理工具白名单
systemPromptMode: replace             # 正文整体替换默认系统提示
---
（原样追加 The Agency 的人格正文）
```

The Agency 文件自带的 `color` / `emoji` / `vibe` 等多余字段会被 Pi 忽略，不影响加载。

---

## 三、转换 & 安装

```bash
# 1. 生成全部 232 个 Pi 代理文件 → integrations/pi/agents/（gitignored）
./scripts/convert-pi.sh

# 2. 安装到用户级目录 ~/.pi/agent/agents/（本机所有会话可用）
./scripts/convert-pi.sh --install

# 只装某几个部门
./scripts/convert-pi.sh --division engineering,security --install

# 预览而不写盘
./scripts/convert-pi.sh --dry-run

# 改名空间：加 --package agency 后，运行时名变成 agency.engineering-xxx
./scripts/convert-pi.sh --package agency --install
```

默认工具分配策略（安全起步，可自行改安装后的文件）：

| 部门 | tools |
|------|-------|
| engineering / security / testing / game-development / gis / spatial-computing / specialized（大部分） | `read, grep, find, ls, bash` |
| academic / design / finance / marketing / paid-media / product / project-management / sales / support | `read, grep, find, ls`（只读） |
| 例外（只读） | engineering-code-reviewer、engineering-codebase-onboarding-engineer、engineering-technical-writer 等 |

---

## 四、怎么用（调用方式）

安装后，在任意 Pi 会话里：

### 1. 自然语言（最简单）
> “用 Frontend Developer 帮我建一个 React 表格组件”
> “请 Converge 几个 advisor 评审这份架构方案”

父代理会自动从 232 个代理里挑合适的委托。

### 2. `/run` 命令
```
/run engineering-frontend-developer 帮我写一个 React 数据表格组件
/run security-penetration-tester 对该仓库做威胁建模（授权范围内）
/run engineering-code-reviewer Review 这次 diff --bg        # 后台
```

### 3. 工具调用 / 编排（workflow 脚本）
```
subagent({ agent: "engineering-code-reviewer", task: "review this diff" })
```
并行 fanout、串行编排、mission 等见 `pi-subagents` 文档
（`/subagents-guide workflows`）。

### 4. 查看可用的代理
> “列出所有可用的 subagent”
或 `subagent({ action: "list" })`

---

## 五、⚠️ 环境修复（本机必需，一次性）

本机 Pi 是通过 `@agegr/pi-web` 包装器启动的（`node bin/pi-web.js`），
导致子代理 spawn 时找不到 Pi 自身的 CLI 脚本，报 `spawn pi ENOENT`。

已通过目录联接（junction）修复：

```
~/.pi/agent/npm/node_modules/@earendil-works/pi-coding-agent
   → D:\DevEnvironment\nodejs\node_global\node_modules\@earendil-works\pi-coding-agent
```

若将来 Pi 升级 / 重装包后子代理再次 `ENOENT`，重建即可：

```bash
cmd /c mklink /J "%USERPROFILE%\.pi\agent\npm\node_modules\@earendil-works\pi-coding-agent" "D:\DevEnvironment\nodejs\node_global\node_modules\@earendil-works\pi-coding-agent"
```

（`pi` 用 `.cmd` shim 启动，Node 的 `spawn` 在 Windows 上无法直接执行 `.cmd`，所以需要让
`pi-subagents` 解析到真正的 `cli.js` 脚本路径，用 `node.exe cli.js` 方式启动子代理。）

---

## 六、常见调优

- **换模型**：代理文件里加 `model:`，或全局在 `~/.pi/agent/settings.json` 配 `subagents.defaultModel`。
- **调思考强度**：文件里加 `thinking: high`（可选 off/minimal/low/medium/high/xhigh/max）。
- **只读/可写**：改 `tools:` 字段，加入 `write`、`edit` 等可让子代理直接改文件（父代理默认仍是写作者）。
- **卸载**：删掉 `~/.pi/agent/agents/` 里对应文件即可。