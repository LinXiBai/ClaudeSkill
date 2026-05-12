# Claude Skills

我的 Claude Code 代码审查Skill 可全局安装到 `~/.claude/skills/`。

## Available Skills

### code-review

企业级严格代码审查 Skill。

**触发词**：`review` / `code review` / `审查` / `审查代码` / `检查代码` / `安全审计` / `性能分析` / `refactor` / `代码质量`

**覆盖维度**：安全、性能、并发、架构、错误处理、内存与资源、可维护性、工业视觉（HALCON/OpenCV/C++/C# 混合）。

**特色**：
- 单一权威来源设计（checklist.md 是规则唯一权威，其余文件路由/示例）
- 按需加载（按目标类型 + 语言只读相关章节，不全量加载）
- 分级输出（Critical/Warning 必须带代码片段+修复代码，Suggestion 简化）
- 支持非代码文件审查（Markdown/YAML/JSON/Prompt）
- 严格风格（禁用"整体不错"、"可以考虑"等空话）

详见 [`skills/code-review/SKILL.md`](skills/code-review/SKILL.md)。

---

## 一键安装

### Windows (PowerShell)

```powershell
git clone https://github.com/LinXiBai/ClaudeSkill.git
cd ClaudeSkill
.\install.ps1
```

### 验证

```powershell
ls "$env:USERPROFILE\.claude\skills\code-review"
# 应看到 5 个 .md 文件
```

新开 Claude Code → 输入 `/skills` → 应在列表里看到 `code-review · user`。

测试触发：
```
审查 这个函数
```

---

## 更新到最新版

```powershell
cd ClaudeSkill
.\update.ps1
```

`update.ps1` 会自动 `git pull` 并把最新版复制到 `~/.claude/skills/`。

---

## 手动安装（不用脚本）

```powershell
git clone https://github.com/LinXiBai/ClaudeSkill.git
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\skills"
Copy-Item -Recurse -Force ClaudeSkill\skills\* "$env:USERPROFILE\.claude\skills\"
```

---

## 卸载

```powershell
Remove-Item -Recurse "$env:USERPROFILE\.claude\skills\code-review"
```

---

## 目录结构

```
ClaudeSkill/
├── README.md
├── install.ps1
├── update.ps1
└── skills/
    └── code-review/
        ├── SKILL.md            主入口（触发词 + 执行流程 + 强制要求）
        ├── checklist.md        13 类审查清单（单一权威来源）
        ├── language-rules.md   9 种语言专项规则
        ├── examples.md         7 个完整 review 示例
        └── review-template.md  输出格式契约
```

---

## 注意

- Skill 是**用户级**安装，所有 Claude Code 会话都生效（不依赖项目）
- 如果某个项目想用专属版本，把 `code-review` 复制到该项目 `.claude/skills/` 下，会**覆盖全局版本**
- 修改了 Skill 文件后，需要**新开 Claude Code 会话**才生效
