# Code Review Examples

每个示例都展示了 **"差代码 → 审查输出 → 修复后代码"** 的完整链路。
**严格按此风格输出审查报告。**

---

## 1. C# Review 示例

### 输入代码

```csharp
// File: OrderService.cs
public class OrderService
{
    private static HttpClient _client;
    private List<Order> _cache = new List<Order>();

    public Order GetOrder(int id)
    {
        try
        {
            var http = new HttpClient();
            var resp = http.GetAsync($"https://api/orders/{id}").Result;
            var json = resp.Content.ReadAsStringAsync().Result;
            http.Dispose();
            return JsonConvert.DeserializeObject<Order>(json);
        }
        catch (Exception) { return null; }
    }

    public async void SaveAsync(Order order)
    {
        _cache.Add(order);
        await Task.Delay(100);
    }
}
```

### 审查输出

# Summary
4 个 Critical、2 个 Warning。本类同时存在 async deadlock、HttpClient 反模式、async void 火-忘、空 catch 吞异常、非线程安全集合并发写、缺失 IDisposable，**生产环境会出 socket 耗尽 + 异常无声丢失 + 静默崩溃**。

# Critical

🔴 **[L9] `_client` 静态字段已声明却未使用，方法内新建 HttpClient 后立即 Dispose**
- 原因：每次请求新建 HttpClient → 底层 socket 进 TIME_WAIT → 数千 QPS 时端口耗尽
- 影响：跨整个服务，生产事故级
- 修复：
```csharp
private static readonly HttpClient _client = new HttpClient
{
    Timeout = TimeSpan.FromSeconds(10)
};
```

🔴 **[L13] `.Result` 在异步方法外阻塞调用**
- 原因：若调用栈中存在 SynchronizationContext（UI / ASP.NET 经典），`.Result` 在 UI 上下文等 await 完成、await 在等 UI 上下文 → 死锁
- 影响：调用栈所有 UI 线程
- 修复：方法签名改 `async Task<Order> GetOrderAsync(int id)`，内部 `await _client.GetAsync(...)`

🔴 **[L17] `catch (Exception) { return null; }` 吞异常**
- 原因：网络失败、反序列化失败、超时全部静默 → 调用方拿 null 误判为"订单不存在"
- 影响：业务逻辑错位 + 故障排查无日志
- 修复：
```csharp
catch (HttpRequestException ex)
{
    _logger.LogError(ex, "GetOrder failed id={Id}", id);
    throw;
}
```

🔴 **[L22] `async void SaveAsync`**
- 原因：async void 抛异常无法被调用方 catch，直接终结进程
- 影响：整应用崩溃
- 修复：`async Task SaveAsync(Order order)`

# Warning

🟡 **[L24] `_cache.Add` 在 async 方法中无锁访问**
- 原因：`List<T>` 非线程安全，多并发 SaveAsync 会损坏内部数组导致 `ArgumentException` 或丢数据
- 影响：本类所有调用方
- 修复：改 `ConcurrentBag<Order>` 或用 `lock`

🟡 **[L24] 缓存只增不删**
- 原因：无淘汰策略，长期运行 OOM
- 影响：进程级
- 修复：用 `MemoryCache` + 过期策略，或 LRU

# Performance
- L13 `.Result` + L14 `.Result` 连续阻塞两次，单调用至少阻塞 1 个 worker 线程

# Security
- L13 URL 拼接 id，若 id 来自外部输入未校验，可能造成路径遍历到其他 API endpoint

# Patch

```csharp
public class OrderService : IDisposable
{
    private static readonly HttpClient _client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(10)
    };
    private readonly ConcurrentDictionary<int, Order> _cache = new();
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger) => _logger = logger;

    public async Task<Order> GetOrderAsync(int id, CancellationToken ct = default)
    {
        if (id <= 0) throw new ArgumentOutOfRangeException(nameof(id));
        try
        {
            using var resp = await _client.GetAsync($"https://api/orders/{id}", ct)
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

    public Task SaveAsync(Order order)
    {
        if (order is null) throw new ArgumentNullException(nameof(order));
        _cache[order.Id] = order;
        return Task.CompletedTask;
    }

    public void Dispose() { /* _client 是 static, 此处不释放 */ }
}
```

# Refactor Plan
1. 把 OrderService 拆为 OrderApiClient（HTTP）+ OrderCache（缓存）+ OrderService（编排），单一职责
2. HttpClient 改为通过 `IHttpClientFactory` 注入，统一管理生命周期
3. 引入 Polly 做 retry/circuit-breaker
4. 缓存策略外置（MemoryCache / Redis），加 TTL

---

## 2. C++ Review 示例

### 输入代码

```cpp
class ImageProcessor {
    char* buffer;
    std::vector<int>* data;
public:
    ImageProcessor(int size) {
        buffer = new char[size];
        data = new std::vector<int>();
    }
    void process(const std::string& path) {
        FILE* f = fopen(path.c_str(), "r");
        fread(buffer, 1, 1024, f);
        for (int i = 0; i < data->size(); i++) {
            // ...
        }
    }
    ~ImageProcessor() { delete buffer; }
};
```

### 审查输出

# Summary
5 个 Critical、2 个 Warning。本类存在内存泄漏（`data` 不释放）、错误用 `delete` 释放数组、文件句柄泄漏、用 int 索引 size_t 比较、缺乏异常安全。**任何抛异常的路径都漏资源**。

# Critical

🔴 **[L9] `new char[size]` 用 `delete` 而不是 `delete[]` 释放**
- 原因：UB，未定义行为，可能内存泄漏或堆破坏
- 影响：每次实例化 + 析构都触发
- 修复：用 `std::unique_ptr<char[]>` 或 `std::vector<char>`

🔴 **[L16] `~ImageProcessor` 析构未释放 `data`**
- 原因：每个实例泄漏一个 vector + 其元素
- 影响：所有实例
- 修复：用 `std::vector<int>` 直接持有（不要指针）

🔴 **[L12] `fopen` 返回值未检查、`fclose` 缺失**
- 原因：文件不存在时 `fread(buffer, ..., NULL)` 是 UB；正常路径文件句柄永久泄漏
- 影响：文件描述符耗尽
- 修复：用 `std::ifstream` (RAII) 或 `fopen` 后立即检查 + 用 `unique_ptr<FILE, decltype(&fclose)>`

🔴 **[L13] `fread(buffer, 1, 1024, f)` 硬编码读 1024，buffer 实际大小是构造参数 size**
- 原因：若 size < 1024 → 缓冲区溢出（栈 / 堆 corruption）
- 影响：内存安全漏洞，可被攻击利用
- 修复：用 `size` 或 `std::min<size_t>(1024, size)`

🔴 **[L14] `int i` 与 `size()`（size_t）比较**
- 原因：编译器警告 + 大 vector 时整数溢出导致越界
- 影响：算法正确性
- 修复：`size_t i` 或 range-based for

# Warning

🟡 **[L4] 类未删除拷贝构造 / 赋值**
- 原因：默认浅拷贝指针 → double free 或悬空指针
- 影响：任何拷贝该类实例的代码
- 修复：`= delete` 或实现 rule of five

🟡 **缺失 explicit 单参数构造**
- 原因：`ImageProcessor p = 1024;` 隐式转换
- 修复：构造函数前加 `explicit`

# Patch

```cpp
class ImageProcessor {
    std::vector<char> buffer_;
    std::vector<int>  data_;
public:
    explicit ImageProcessor(size_t size) : buffer_(size) {}

    ImageProcessor(const ImageProcessor&) = delete;
    ImageProcessor& operator=(const ImageProcessor&) = delete;
    ImageProcessor(ImageProcessor&&) noexcept = default;
    ImageProcessor& operator=(ImageProcessor&&) noexcept = default;
    ~ImageProcessor() = default;

    void process(const std::filesystem::path& path)
    {
        std::ifstream f(path, std::ios::binary);
        if (!f) throw std::runtime_error("cannot open " + path.string());

        const size_t n = std::min(buffer_.size(), size_t{1024});
        f.read(buffer_.data(), static_cast<std::streamsize>(n));

        for (size_t i = 0; i < data_.size(); ++i) {
            // ...
        }
    }
};
```

# Refactor Plan
1. 全员替换裸 `new`/`delete` → `unique_ptr` / 容器
2. 文件 IO 全部走 RAII（fstream / unique_ptr with custom deleter）
3. 类的拷贝/移动语义显式声明（rule of zero 优先）
4. 引入 clang-tidy + ASan 进 CI

---

## 3. HALCON Review 示例

### 输入代码

```csharp
public class ShapeMatcher
{
    private HObject _model;

    public void LoadModel(string path)
    {
        HOperatorSet.ReadShapeModel(path, out HTuple modelId);
        _modelId = modelId;
    }

    public void Match(HObject image)
    {
        try
        {
            HOperatorSet.GenRectangle1(out HObject roi, 100, 100, 500, 500);
            HOperatorSet.ReduceDomain(image, roi, out HObject reduced);
            HOperatorSet.FindShapeModel(reduced, _modelId, 0, Math.PI*2, 0.5, 1, 0.5,
                "least_squares", 0, 0.9, out HTuple row, out HTuple col, out HTuple angle, out HTuple score);
            _result = reduced;
        }
        catch (Exception) { }
    }

    private HObject _result;
    private HTuple _modelId;
}
```

### 审查输出

# Summary
4 个 Critical 全部是 HObject / HALCON 句柄泄漏。本类长期运行会**耗尽 HALCON 内部对象池**导致后续算子失败。

# Critical

🔴 **[L13-14] `roi` 和 `reduced` 用完不 Dispose**
- 原因：HObject 是 HALCON 句柄包装，未 Dispose 不会被 GC 自动回收 HALCON 侧资源
- 影响：每次 Match 泄漏 2 个 HObject，连续运行内存与句柄都涨
- 修复：try/finally + ?.Dispose()，或用 using

🔴 **[L8] ReadShapeModel 的 modelId 重复加载未 ClearShapeModel**
- 原因：HALCON 模板独立于 HObject，由 `ClearShapeModel` 释放；多次 LoadModel 旧模板永远留在内核
- 影响：HALCON 模板池积压
- 修复：
```csharp
public void LoadModel(string path)
{
    if (_modelId is not null) HOperatorSet.ClearShapeModel(_modelId);
    HOperatorSet.ReadShapeModel(path, out HTuple modelId);
    _modelId = modelId;
}
```

🔴 **[L17] `_result = reduced;` 直接覆盖字段，旧 `_result` 未 Dispose**
- 原因：第二次 Match 起每次泄漏一个 reduced
- 影响：累积泄漏
- 修复：`_result?.Dispose(); _result = reduced;`

🔴 **[L19] 空 catch 吞 HALCON 异常**
- 原因：算子失败时上层完全无感知，且失败时 `reduced` 未赋值，资源已泄漏
- 影响：故障排查 + 资源管理双重灾难
- 修复：捕获 `HOperatorException` 并日志 + 重抛 / 业务降级

# Warning

🟡 **[L13] 每次 Match 都新建 ROI**
- 原因：若 ROI 固定，应缓存为字段；每次 GenRectangle1 是 HALCON 算子调用，单次微秒级但累计可观
- 修复：构造时建 ROI，析构时释放

🟡 **类未实现 IDisposable**
- 原因：`_model` `_modelId` `_result` 都是 HALCON 资源，宿主进程退出前必须显式释放
- 修复：实现 IDisposable

# Performance
- 算子顺序：`ReduceDomain(image, roi, out reduced)` 之后再 `FindShapeModel(reduced, ...)`，正确（先 reduce 再 find，避免全图搜索）。本项 OK。
- 若 image 是 RGB，FindShapeModel 应先 `Rgb1ToGray` 再传入（前提是模板基于灰度训练），否则性能下降 3 倍

# Patch

```csharp
public sealed class ShapeMatcher : IDisposable
{
    private HTuple _modelId;
    private HObject _roi;          // 缓存固定 ROI
    private HObject _lastReduced;  // 上次结果，用于显示

    public ShapeMatcher()
    {
        HOperatorSet.GenRectangle1(out _roi, 100, 100, 500, 500);
    }

    public void LoadModel(string path)
    {
        if (_modelId is not null && _modelId.Length > 0)
            HOperatorSet.ClearShapeModel(_modelId);
        HOperatorSet.ReadShapeModel(path, out _modelId);
    }

    public MatchResult Match(HObject image)
    {
        HObject reduced = null;
        try
        {
            HOperatorSet.ReduceDomain(image, _roi, out reduced);
            HOperatorSet.FindShapeModel(reduced, _modelId, 0, Math.PI * 2, 0.5, 1, 0.5,
                "least_squares", 0, 0.9, out HTuple row, out HTuple col,
                out HTuple angle, out HTuple score);

            _lastReduced?.Dispose();
            _lastReduced = reduced;
            reduced = null;  // 已转移所有权

            return new MatchResult(row, col, angle, score);
        }
        catch (HOperatorException ex)
        {
            _logger.LogError(ex, "FindShapeModel failed: {Code}", ex.GetErrorCode());
            throw;
        }
        finally
        {
            reduced?.Dispose();
        }
    }

    public void Dispose()
    {
        _roi?.Dispose();
        _lastReduced?.Dispose();
        if (_modelId is not null && _modelId.Length > 0)
            HOperatorSet.ClearShapeModel(_modelId);
    }
}
```

# Refactor Plan
1. 引入 `HObjectScope` 工具类（IDisposable 自动追踪一组 HObject）
2. HALCON 异常类型化（`HOperatorException` 转业务异常 + 错误码）
3. 单元测试中加 HALCON 资源计数（`get_system("memory")` 前后对比）
4. 长流程 pipeline 用 builder 模式 + `using` 作用域

---

## 4. OpenCV Review 示例

### 输入代码

```cpp
cv::Mat process(const std::string& path) {
    cv::Mat img = cv::imread(path);
    cv::Mat gray;
    cv::cvtColor(img, gray, cv::COLOR_BGR2GRAY);
    cv::Mat blur;
    cv::GaussianBlur(gray, blur, cv::Size(5,5), 1.5);
    cv::Mat edge = blur.clone();
    cv::Canny(blur, edge, 50, 150);
    return edge.clone();
}
```

### 审查输出

# Summary
1 个 Critical、3 个 Performance。函数语义正确但存在不必要的深拷贝、return 时再次拷贝、多个中间 Mat 占用内存。**单次调用至少 3 次冗余分配**。

# Critical

🔴 **[L7-8] `edge = blur.clone();` 紧接着 `cv::Canny` 覆写 edge**
- 原因：clone 出的内存立即被 Canny 输出覆盖，此 clone 完全无意义
- 影响：每次调用浪费一次大图分配 + 拷贝
- 修复：删除 L7

# Performance

🟡 **[L9] `return edge.clone()`**
- 原因：Mat 自身就是引用计数，return 时不需要 clone；C++ RVO 直接构造到调用方
- 影响：每次返回多一次深拷贝
- 修复：`return edge;`

🟡 **[L2] `cv::imread` 返回 BGR，立即转 gray，可直接读为 gray**
- 原因：imread BGR 后 cvtColor 多走一次 3 通道分配
- 修复：`cv::imread(path, cv::IMREAD_GRAYSCALE)`，省掉 L3-4 整个 cvtColor

🟡 **中间变量 `gray` `blur` `edge` 全部独立分配**
- 原因：对 4K 图像，每个 Mat ~ 8MB，单次调用峰值 ~32MB
- 修复：原地操作（in-place）OpenCV 大多算子支持 src == dst

# Patch

```cpp
cv::Mat process(const std::string& path)
{
    cv::Mat img = cv::imread(path, cv::IMREAD_GRAYSCALE);
    if (img.empty()) throw std::runtime_error("imread failed: " + path);

    cv::GaussianBlur(img, img, cv::Size(5, 5), 1.5);     // in-place
    cv::Canny(img, img, 50, 150);                         // in-place
    return img;                                            // 引用计数返回，无拷贝
}
```

# Refactor Plan
1. 项目内全局禁用 `Mat::clone()` 除非业务确实需要独立副本，clang-tidy 规则拦截
2. 长 pipeline 用 `cv::UMat`（OpenCL 后端）/ CUDA Stream
3. 静态分析中识别 `result.clone()` 在 return 前的反模式

---

## 5. 多线程问题示例（C# / async）

### 输入代码

```csharp
public class Counter
{
    private int _count;
    private Dictionary<string, int> _stats = new Dictionary<string, int>();
    private readonly object _lock = new object();

    public void Increment(string key)
    {
        _count++;
        if (_stats.ContainsKey(key))
            _stats[key]++;
        else
            _stats[key] = 1;
    }

    public async Task<int> GetAsync(string key)
    {
        lock (_lock)
        {
            return await FetchFromDbAsync(key);
        }
    }
}
```

### 审查输出

# Summary
3 个 Critical 全是并发/异步致命错误。本类**多线程下数据必错，async 路径必死锁**。

# Critical

🔴 **[L9] `_count++` 非原子**
- 原因：x86 也只有对齐 int 的读/写原子，`++` 是 read-modify-write 三步
- 影响：多线程并发 increment 漏计数
- 修复：`Interlocked.Increment(ref _count);`

🔴 **[L10-13] Dictionary 多线程读写无锁**
- 原因：Dictionary 非线程安全；ContainsKey + 索引器赋值 还存在 check-then-act
- 影响：并发写损坏内部结构，抛 InvalidOperationException / 死循环 / 丢数据
- 修复：用 `ConcurrentDictionary<string, int>` + `AddOrUpdate(key, 1, (_, v) => v + 1)`

🔴 **[L20-23] `lock` 内 `await`**
- 原因：lock 不支持跨 await 持有；线程进 lock → await → 恢复时是另一线程 → 那个线程不持有 lock → 释放时崩溃，或更隐蔽的死锁
- 影响：偶发崩溃 + 难复现
- 修复：用 `SemaphoreSlim.WaitAsync()`，或在 lock 外做异步获取数据

# Patch

```csharp
public class Counter
{
    private int _count;
    private readonly ConcurrentDictionary<string, int> _stats = new();
    private readonly SemaphoreSlim _dbGate = new(1, 1);

    public void Increment(string key)
    {
        Interlocked.Increment(ref _count);
        _stats.AddOrUpdate(key, 1, (_, v) => v + 1);
    }

    public async Task<int> GetAsync(string key, CancellationToken ct = default)
    {
        await _dbGate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            return await FetchFromDbAsync(key, ct).ConfigureAwait(false);
        }
        finally { _dbGate.Release(); }
    }
}
```

# Refactor Plan
1. 全项目搜索 `lock (...) { await ... }` 模式，全部替换
2. 引入 Roslyn 分析器 `VSTHRD002` / `VSTHRD003`
3. 共享可变状态全部走 `Interlocked` / `Concurrent*` / `SemaphoreSlim`

---

## 6. 内存泄漏示例（C# WPF + 事件订阅）

### 输入代码

```csharp
public class MyControl : UserControl
{
    public MyControl()
    {
        InitializeComponent();
        App.Settings.Changed += OnSettingsChanged;
        App.Camera.FrameReceived += OnFrame;
    }

    void OnSettingsChanged(object s, EventArgs e) { /*...*/ }
    void OnFrame(object s, FrameArgs e) { Dispatcher.Invoke(() => Image1.Source = e.Bitmap); }
}
```

### 审查输出

# Summary
2 个 Critical 都是事件订阅泄漏，**每打开一次该控件，全局单例多持有一个 UserControl 引用，关闭控件 GC 不掉**。

# Critical

🔴 **[L5-6] 订阅静态/单例事件无对应 -= **
- 原因：`App.Settings` `App.Camera` 是长寿对象，订阅后强引用 MyControl，控件关闭 Unloaded 不会自动解绑
- 影响：每次打开/关闭累积一个 UserControl 在堆上 + 每次 Frame 都触发已"关闭"控件的回调
- 修复：在 Unloaded 解绑

🔴 **[L10] `Dispatcher.Invoke` 在 worker 线程**
- 原因：FrameReceived 通常在采图线程；`Invoke` 阻塞采图线程到 UI 处理完 → 帧率被 UI 拖慢
- 影响：采图丢帧
- 修复：用 `BeginInvoke` 或 `Dispatcher.InvokeAsync`

# Patch

```csharp
public class MyControl : UserControl
{
    public MyControl()
    {
        InitializeComponent();
        Loaded   += OnLoaded;
        Unloaded += OnUnloaded;
    }

    void OnLoaded(object s, RoutedEventArgs e)
    {
        App.Settings.Changed += OnSettingsChanged;
        App.Camera.FrameReceived += OnFrame;
    }

    void OnUnloaded(object s, RoutedEventArgs e)
    {
        App.Settings.Changed -= OnSettingsChanged;
        App.Camera.FrameReceived -= OnFrame;
    }

    void OnSettingsChanged(object s, EventArgs e) { /*...*/ }

    void OnFrame(object s, FrameArgs e)
    {
        // 不阻塞采图线程
        Dispatcher.BeginInvoke(() =>
        {
            if (IsLoaded) Image1.Source = e.Bitmap;
        });
    }
}
```

# Refactor Plan
1. 项目级引入 `WeakEventManager<TEventSource, TEventArgs>` 包装跨生命周期订阅
2. 写一个基类 `LifecycleUserControl` 提供 `OnAttached/OnDetached` 钩子，统一管理订阅
3. 单测 + dotMemory 验证多次打开/关闭后实例数为 0

---

## 7. 工业视觉 Pipeline 示例

### 场景
4 通道相机并行采图，每路独立配方，结果显示到 4 个 HALCON 窗口。原代码：

```csharp
foreach (var ch in channels)
{
    Task.Run(() =>
    {
        var img = ch.Camera.Grab();
        var result = ch.Recipe.Run(img);

        // 直接在 worker 线程操作 HALCON 窗口
        ch.Window.ClearWindow();
        ch.Window.DispObj(result);
    });
}
```

### 审查输出

# Summary
3 个 Critical（HALCON 渲染竞争、相机句柄无释放、Task fire-and-forget）+ 2 个 Architecture。**4 通道高负载下必丢帧、必崩**。

# Critical

🔴 **HALCON 窗口在 worker 线程并发渲染**
- 原因：HALCON 的图形管道（flush_graphic、graphics_stack）是**进程级全局状态**；4 个线程同时 `ClearWindow/DispObj` 会相互覆盖中间状态，导致丢帧或绘图错乱
- 影响：4 通道并行时随机丢帧
- 修复：全局渲染锁 + UI 线程统一渲染（推荐用 SynchronizationContext）
```csharp
internal static class HalconRenderLock { public static readonly object Sync = new(); }
// 渲染处:
lock (HalconRenderLock.Sync) { ch.Window.ClearWindow(); ch.Window.DispObj(result); }
```

🔴 **`Task.Run(...)` 火-忘，无异常处理**
- 原因：worker 内异常无人 catch → 默认 UnobservedTaskException → .NET 4.5+ 不杀进程但 5.0+ 视配置可能杀
- 影响：单线程崩溃静默
- 修复：保留 Task 引用 + 统一 await / `.ContinueWith(t => log)`

🔴 **`ch.Camera.Grab()` / `result` 等 HObject 无 Dispose**
- 原因：长循环每帧泄漏图像
- 影响：累积内存暴涨
- 修复：try/finally + Dispose；result 在 DispObj 后释放（HObjectList 内部引用计数已增加）

# Warning

🟡 **采图与配方耦合在同一 Task**
- 原因：配方耗时 > 采图间隔时帧堆积；采图慢时配方饿死
- 修复：拆为 producer / consumer 两条 pipeline，中间用 BoundedChannel 限速

🟡 **缺失通道级隔离**
- 原因：一通道异常 → 整 foreach 不终止但日志混在一起；崩溃时无法定位通道
- 修复：每通道独立 SupervisorTask + 通道 id 进所有日志

# Architecture

- 显示直接吃 worker 线程结果，缺少明确的"业务结果 → 展示数据"边界。建议引入 `FrameResult` DTO，业务线程产出 DTO 入队，UI 线程消费后调用 HALCON 渲染
- HALCON 窗口资源（HWindow）和业务对象（Recipe）混在 channel 配置里，应分层

# Patch（关键骨架）

```csharp
public sealed class Channel : IDisposable
{
    private readonly Camera _cam;
    private readonly Recipe _recipe;
    private readonly HWindow _win;
    private readonly Channel<FrameResult> _queue;
    private readonly CancellationTokenSource _cts = new();
    private Task _producer, _consumer;

    public void Start()
    {
        _producer = Task.Run(ProducerLoop);
        _consumer = Task.Run(ConsumerLoop);
    }

    async Task ProducerLoop()
    {
        var ct = _cts.Token;
        while (!ct.IsCancellationRequested)
        {
            HObject img = null;
            try
            {
                img = _cam.Grab();
                var dto = _recipe.Run(img);   // recipe 内部释放 img
                await _queue.Writer.WriteAsync(dto, ct);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex)
            {
                _log.LogError(ex, "Ch={Id} producer", _id);
                img?.Dispose();
            }
        }
    }

    async Task ConsumerLoop()
    {
        await foreach (var dto in _queue.Reader.ReadAllAsync(_cts.Token))
        {
            try
            {
                lock (HalconRenderLock.Sync)
                {
                    _win.ClearWindow();
                    _win.DispObj(dto.Region);
                }
            }
            finally { dto.Dispose(); }
        }
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { Task.WaitAll(new[]{_producer, _consumer}, 2000); } catch {}
        _cam.Dispose();
        _win.Dispose();
    }
}
```

# Refactor Plan
1. 引入 channel-based pipeline；producer / consumer 显式分层
2. 渲染层统一锁 + UI 上下文同步
3. 每通道独立监控（FPS / 丢帧率 / 异常计数）
4. 每帧关键节点埋点（采图 / 算子 / 渲染耗时）
5. 长时间稳定性测试 + HALCON `get_system("memory")` 监控
