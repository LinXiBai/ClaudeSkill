# Review Output Template

**严格按此模板输出审查报告。**

章节顺序固定。**所有 # 标题必须出现**（没有内容也要写"无"），便于解析。

---

## 章节定义

### # Summary
一段话给出**整体定性结论**，必须包含：
- 严重问题数量（Critical / Warning / Suggestion 各几个）
- 最大风险一句话
- 是否阻塞合并 / 是否生产可用

❌ 不准说："代码整体不错"、"有少量问题"、"建议优化"
✅ 应该说："3 Critical / 2 Warning / 1 Suggestion。最大风险：L42 的 `Task.Result` 在 UI 上下文必死锁。**当前状态不可合并**。"

---

### # Critical
**🔴 阻塞级问题**。生产环境会直接事故（崩溃、数据损坏、安全漏洞、严重内存泄漏）。

每条格式：
```
🔴 **[文件:行号] 一句话标题（说出问题，不是说出建议）**
- 原因：为什么是问题（机制/原理，不只是现象）
- 影响范围：单函数 / 单模块 / 跨模块 / 全局 / 生产事故级
- 复现条件：什么情况下触发（如果是必现，也要说明）
- 修复：
\`\`\`<lang>
// 可直接复制粘贴的修复代码
\`\`\`
```

没有 Critical 就写"无"。

---

### # Warning
**🟡 潜在风险**。当前可能不直接出问题，但条件触发会暴露；或代码设计上的明显缺陷。

格式同 Critical，等级图标用 🟡。

---

### # Suggestion
**🟢 可改进点**。代码风格、可读性、轻微的性能/设计优化。

格式简化：
```
🟢 **[文件:行号] 描述**
- 修复建议（不要求示例代码）
```

---

### # Performance
专门列**性能问题**（即便已经在 Critical/Warning 中提过，这里再聚焦汇总）。

包含：
- 问题点（位置 + 当前耗时/分配量估算）
- 优化方案（具体到算法/数据结构/API 选择）
- 预估收益（"减少 90% 内存分配" / "从 O(N²) 降到 O(N)"）

不要写"性能可以优化"这种废话。

---

### # Security
专门列**安全问题**。
- 漏洞类型（OWASP / CWE 类别）
- 攻击场景描述
- 危害程度
- 修复方案

没有安全问题写"未发现明显安全问题"。**不要不写章节**。

---

### # Architecture
**架构层面**的问题。
- 模块耦合 / 分层混乱 / 上帝类
- 接口设计缺陷
- 全局状态滥用
- 抽象层级不当

每条需说明：
- 当前结构问题
- 长期影响
- 推荐结构

---

### # Patch
**可直接复制使用的完整修复代码**。

如果改动小（< 30 行），给完整修复后的代码块。
如果改动大，给最关键的核心改动 + 在 Refactor Plan 章节展开。

代码块必须：
- 注明语言（```csharp / ```cpp / ```go ...）
- 标注文件路径作为注释开头：`// File: OrderService.cs`
- **包含修复后能编译运行**的形式（不能只贴片段）

---

### # Refactor Plan
**分步重构计划**。如果只是局部改动，可以简短。

格式：
```
1. **[阶段名]** 描述
   - 做什么
   - 为什么
   - 风险/兼容性
2. ...
```

涉及大改动时，每步标注**风险等级**（低 / 中 / 高）和**回滚策略**。

---

## 完整输出范例（迷你版）

```markdown
# Summary
2 Critical / 1 Warning / 0 Suggestion。最大风险：`OrderService.GetOrder` 同步阻塞 + 空 catch 吞异常，UI 调用必死锁。**不可合并**。

# Critical

🔴 **[OrderService.cs:13] `.Result` 在异步方法外阻塞调用，UI 上下文必死锁**
- 原因：SynchronizationContext 等 await 完成，await 等 UI 上下文 → 互相等
- 影响范围：所有 UI 线程调用 GetOrder 的路径
- 复现条件：必现（WPF/WinForms/ASP.NET 经典上下文）
- 修复：
\`\`\`csharp
public async Task<Order> GetOrderAsync(int id, CancellationToken ct = default)
{
    using var resp = await _client.GetAsync($"...{id}", ct).ConfigureAwait(false);
    resp.EnsureSuccessStatusCode();
    var json = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
    return JsonConvert.DeserializeObject<Order>(json);
}
\`\`\`

🔴 **[OrderService.cs:17] `catch (Exception) { return null; }` 吞所有异常**
- 原因：网络/反序列化/超时/取消统一返回 null，调用方误判"订单不存在"
- 影响：业务逻辑错位 + 故障排查无线索
- 复现条件：网络抖动 / API 返回 5xx
- 修复：
\`\`\`csharp
catch (HttpRequestException ex)
{
    _logger.LogError(ex, "GetOrder failed id={Id}", id);
    throw;
}
\`\`\`

# Warning

🟡 **[OrderService.cs:7] HttpClient 在方法内 new 后立即 Dispose**
- 原因：每次请求新建 socket，TIME_WAIT 累积，高 QPS 下端口耗尽
- 影响：网络层
- 修复：改 static 单例或 IHttpClientFactory

# Suggestion
无

# Performance
- L13/L14 连续两次 `.Result` 阻塞，每次至少 1 个 ThreadPool 线程被占；改全异步后吞吐量预估提升 3-5 倍
- HttpClient 单例后预估减少 80% 连接建立耗时

# Security
- L13 URL 拼接 id 无校验，存在路径遍历到其他 endpoint 的潜在风险（如 `id = "1/../admin"`）。修复：`Uri.EscapeDataString(id.ToString())` 或参数化路由

# Architecture
- OrderService 同时承担：HTTP 调用 + 反序列化 + 缓存 + 业务编排 → 违反单一职责
- 建议拆为 `OrderApiClient` + `OrderCache` + `OrderService`

# Patch

\`\`\`csharp
// File: OrderService.cs
public sealed class OrderService
{
    private static readonly HttpClient _client = new()
    {
        Timeout = TimeSpan.FromSeconds(10)
    };
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger) => _logger = logger;

    public async Task<Order> GetOrderAsync(int id, CancellationToken ct = default)
    {
        if (id <= 0) throw new ArgumentOutOfRangeException(nameof(id));
        try
        {
            using var resp = await _client
                .GetAsync($"https://api/orders/{Uri.EscapeDataString(id.ToString())}", ct)
                .ConfigureAwait(false);
            resp.EnsureSuccessStatusCode();
            var json = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            return JsonConvert.DeserializeObject<Order>(json);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "GetOrder failed id={Id}", id);
            throw;
        }
    }
}
\`\`\`

# Refactor Plan
1. **[Step 1, 低风险]** 把方法签名改 async + 添加 CancellationToken；调用方逐步迁移
2. **[Step 2, 中风险]** 拆 OrderApiClient / OrderCache / OrderService 三个类
3. **[Step 3, 中风险]** 接入 IHttpClientFactory + Polly（retry / circuit-breaker）
4. **[Step 4, 低风险]** 加单测：模拟 5xx / 超时 / 反序列化失败
```

---

## 输出长度建议

| review 范围 | 总长度 |
|------------|--------|
| 单文件 / 一个类 | 800-1500 字 |
| 一个模块 / 一个 PR | 1500-3000 字 |
| 整个项目 | 3000-6000 字，分文件聚合 |

**长度不是目的，覆盖深度才是**。如果只有 1-2 个问题就如实写 1-2 个，不要凑数。
如果发现真的 0 个问题，需要主动质疑：是否覆盖完整？是否漏看了边界情况？是否被代码风格误导？

---

## 输出语气检查清单

输出前自查：
- [ ] 是否每条都有具体行号？
- [ ] 是否每条都说了**为什么是问题**（不是"建议这样改"）？
- [ ] 是否每条都标注了风险等级？
- [ ] Critical 是否给出**可直接编译的修复代码**？
- [ ] 是否避免了"整体不错"、"可以考虑"、"建议"（除 Refactor Plan 外）？
- [ ] 是否至少 3 个改进点？不够则继续找

---

## 特殊情况处理

- **代码确实没问题** → "已逐项检查 [N] 条规则，未发现 Critical/Warning。Suggestion 部分给出 [X] 条可读性改进。"
- **代码无法阅读 / 信息不足** → 直接说明缺失什么（"无项目根目录上下文 / 无关联接口定义"），不要假装审查
- **跨语言项目** → 按文件分组，每文件标注语言，分别套用各自规则
- **二进制 / 自动生成代码** → 跳过 + 在 Summary 说明
