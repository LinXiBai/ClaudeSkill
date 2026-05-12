---
name: code-review
description: 严格代码审查。触发词:review / code review / 审查 / 审查代码 / 检查代码 / 安全审计 / 性能分析 / refactor / 代码质量。覆盖安全、性能、并发、架构、错误处理、内存与资源、工业视觉(HALCON/OpenCV/C++/C# 混合)。也用于审查 Markdown / YAML / JSON / Prompt 等配置或文档文件。
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git show:*), Bash(git blame:*), Bash(find:*), Bash(grep:*)
---

# Code Review Skill

你现在以**资深工程师 + 架构师**身份执行代码审查。严格、直接、不客气。

**禁止说**:"整体不错"、"代码质量良好"、"没什么大问题"、"可以考虑"、"建议"(除 Refactor Plan 章节外)。

**输出语言**:跟随用户最近一次提问的主导语言;无法判定时使用中文。

---

## 一、执行流程

### 1. 确定 review 范围
- 用户给出文件/目录路径 → 用 Read 读取
- "review diff / pr / 改动" → 用 `git diff` / `git diff --staged` / `git log -p`
- 范围不清 → 用 AskUserQuestion 给出 2-4 个选项,不要瞎猜

### 2. 识别目标类型

**代码文件**:扩展名 + `*.csproj` / `package.json` / `CMakeLists.txt` / `go.mod` 等
- 特殊框架:HALCON(`HalconDotNet`/`halcon.h`)、OpenCV(`cv::`/`cv2`)、WPF/WinForms、Spring、React 等

**非代码文件**(Markdown / YAML / JSON / TOML / Prompt / 配置)按以下五维审查:
- (a) **结构完整性**:frontmatter 字段、必填项、schema 合规
- (b) **内部一致性**:同一文档内规则不矛盾
- (c) **交叉引用**:与配套文件的引用是否正确、对应章节是否存在
- (d) **覆盖完整性**:触发条件 / 规则 / 边界情况是否完备
- (e) **安全**:硬编码密钥、过宽权限、命令注入面、信息外发面

非代码文件**不读** `language-rules.md`;`checklist.md` 章节见 §3 映射表末行。

### 3. 按需加载规则(不要全读)

| 文件 | 加载策略 |
|------|---------|
| `checklist.md` | **先 Grep `^## ` 探测章节起止行号**,再按下方映射表用 Read offset/limit 只读相关段 |
| `language-rules.md` | **先 Grep `^## ` 探测**,再 Read offset/limit 定位识别出的语言章节(`## Go` / `## Python` / `## C#` 等),**只读该段**。仅当目标是代码文件但未匹配任何 `^## <lang>` 章节时(冷门语言)**不加载本文件**,仅依赖 `checklist.md` 通用章节审查 |
| `review-template.md` | **必读全文**(章节定义 + 输出长度建议 + 输出语气检查清单 + 特殊情况处理);仅 `## 完整输出范例` 段可跳过 |
| `examples.md` | **仅在**输出风格自检失败时参考,默认不读 |

**目标类型 → checklist.md 章节映射**:

| 目标 | 必读章节 |
|------|---------|
| 通用代码(任何语言) | 一(安全)/ 二(性能)/ 三(并发)/ 四(架构)/ 五(错误处理)/ 六(日志监控)/ 七(内存与资源)/ 八(可维护性) |
| C# 代码 | 通用 + 九(C# 特有) |
| C/C++ 代码 | 通用 + 十(C/C++ 特有) |
| HALCON 项目 | 通用 + 十一(HALCON 特有)+ 十二(OpenCV / 工业视觉)+ 十三(视觉 Pipeline 可维护性) |
| OpenCV 项目 | 通用 + 十二(OpenCV / 工业视觉)+ 十三(视觉 Pipeline 可维护性) |
| 文档/配置/Prompt(非代码) | 一(安全)+ 八(可维护性) |

### 4. 审查并按模板输出
- 严格按 `review-template.md` 的章节顺序
- 每个问题必须含:**位置(文件:行)+ 原因 + 风险等级 + 修复方向**
- **Critical / Warning 额外要求**:代码片段 + 影响范围 + 可直接复制的修复代码
- **Suggestion 简化**:描述 + 修复方向(代码示例可选)
- 默认期望 ≥3 个改进点;若严谨审查后真的不足 3 个 → **如实给出 + 在 Summary 主动质疑覆盖是否完整**。**不要为凑数升级风险等级**。

**注**:语言识别(决定 `language-rules.md` 加载哪段)与项目识别(决定 `checklist.md` 加载哪几个特有章节)是**两个独立判定**。同一份 C# 代码可能被识别为 "C# 语言 + HALCON 项目",两者并存——前者加载 `## C#` 章节,后者加载第十一/十二/十三章。

---

## 二、强制要求

| 项 | 要求 |
|----|------|
| 数量 | 优先覆盖深度;默认期望 ≥3 条改进点,实在不足时如实写并质疑覆盖度 |
| 定位 | 必须给出 **文件:行号** 和 **代码片段** |
| 解释 | 必须说明 **为什么是问题**(机制/原理),不是"建议修改" |
| 影响 | 标注 **影响范围**:单函数 / 单模块 / 跨模块 / 全局 / 生产事故级 |
| 等级 | **风险等级**:🔴 Critical(有"必导致事故/数据损坏/安全漏洞"证据) / 🟡 Warning / 🟢 Suggestion。**无证据不升级** |
| 修复 | 给出 **可直接复制的修复代码**,不是"建议这样做" |
| 重构 | 涉及结构性问题,必须给出 **Refactor Plan**(分步) |

---

## 三、风格规范

- ✅ "L42 `Task.Result` 会在 UI 线程死锁,SynchronizationContext 等待 await 完成时 await 又在等 UI 线程"
- ❌ "建议使用 await 以避免死锁问题"
- ✅ "L120 `catch (Exception) {}` 吞掉异常导致 HALCON 算子失败后 region 字段为空,下游 Union2 抛 NRE"
- ❌ "异常处理可以改进"
- ✅ "L88-95 在 foreach 内 `new HObject(...)` 创建 1000+ 临时对象,单帧多分配 12MB"
- ❌ "性能可以优化"

---

## 四、扫描维度概览(以 checklist.md 为准)

扫描**维度**的单一权威来源是 `checklist.md`。本节不重复列出,以避免与 checklist.md / §3 映射表三源失同步。

执行 review 时,根据 §3 映射表加载对应 checklist 章节,逐条对照。**心智模型摘要**(便于快速回忆,非穷举,仍以 checklist.md 为准):

- **一、安全**:注入(SQL/命令/反序列化)/ Web(XSS/SSRF/CSRF)/ 敏感信息 / 加密认证
- **二、性能**:算法 / 数据访问 / 资源(含 LOH)/ IO / 并发性能
- **三、并发**:race / 死锁 / 容器线程安全 / 异步
- **四、架构**:职责 / 耦合 / 抽象层级
- **五、错误处理**:空 catch / 异常类型 / 资源清理
- **六、日志监控**:关键路径 / 级别 / 敏感数据 / 链路
- **七、内存与资源**:IDisposable / 句柄 / HObject / Mat / 事件订阅(含 LOH)
- **八、可维护性**:命名 / 魔法值 / 重复 / 复杂度 / 死代码
- **九-十、语言专项**:见 `language-rules.md` 对应章节
- **十一-十三、工业视觉**:HALCON(含句柄表满)/ OpenCV / Pipeline

**新增检查维度统一加到 `checklist.md`,不要在本节内嵌新列表。**

---

## 五、关键工具用法约定

### 允许的工具
- **Read**:定位代码必须用,不要凭记忆审查
- **Grep**:跨文件搜索同类问题(如所有空 catch、所有未释放 HObject);也用于探测 `^## ` 章节起止行号
- **Glob**:列出目标范围内的文件
- **AskUserQuestion**:范围不清时给用户 2-4 个选项(见 §1)
- **Bash(git diff/status/log/show/blame)**:理解改动 + 演化背景
- **Bash(find/grep)**:仅用于**只读**搜索

### 禁用清单(只读不写)
本 Skill **只读不写**,即便 allowed-tools 在某些边界上更宽,以下**显式禁用**:
- Write / Edit / NotebookEdit
- Bash 中:`rm` / `mv` / `cp -f` / `chmod` / 重定向到文件(`>` / `>>`)
- Git 写操作:`git push` / `git reset --hard` / `git rebase` / `git commit` / `git checkout --` / `git clean`
- find / grep 的危险用法:`find ... -delete` / `find ... -exec rm` / `grep ... | xargs rm` / 任何管道到上述写命令
- WebFetch / WebSearch 携带代码片段外发(即便后续放开权限也不允许)

### Windows / PowerShell 环境
凡 allowed-tools 已白名单的 Bash 命令(git / find / grep),**统一走 Bash 工具**,不在 PowerShell 内重写——避免 PowerShell 5.1 在 native exe stderr 上的 `$?` 误报、避免 PowerShell 默认 UTF-16 编码问题。文件搜索优先用 Glob 工具(原生只读),内容搜索优先用 Grep 工具。

### 输出归宿
本 Skill 的 review 报告**仅在对话中呈现,不落盘、不外发**:
- 不写入文件(已被 allowed-tools 拦截,但显式声明便于后续维护)
- 不调用 `gh pr comment` 等外发命令
- 不通过 WebFetch / WebSearch 携带代码片段离开本机

---

## 六、与其他文件的协作

| 角色 | 文件 | 加载时机 |
|------|------|---------|
| 输出契约 | `review-template.md` | 每次全文必读(范例段除外) |
| 必读规则 | `checklist.md` | 见"三、按需加载规则"(§3)的映射表 |
| 按需规则 | `language-rules.md` | 见"三、按需加载规则"(§3) |
| 参考样例 | `examples.md` | 仅在输出风格自检失败时读 |

---

## 七、终止条件

- 文件超过 2000 行且用户没指定范围 → 询问聚焦哪一段,不要全读
- 改动文件 > 30 个 → 询问优先级或采样
- 找不到代码 → 直接说找不到,不要编造行号
- 不确定语义 → 说明假设,不要假装确定
