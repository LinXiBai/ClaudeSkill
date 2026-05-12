# Language Rules

按检测到的语言加载对应章节，**作为通用 checklist 的增强**。
检测优先级：文件扩展名 → 项目文件（csproj/CMakeLists.txt/go.mod/package.json）→ import/using 语句。

---

## Go

### 必查
- **context 泄漏**：函数接收 `context.Context` 但不向下传；`context.Background()` 在请求路径用；忘记 cancel 导致定时器/连接泄漏
- **channel 死锁**：
  - 无人读的 unbuffered channel 写阻塞
  - close 后写 panic
  - select 缺 default 在非阻塞场景
- **goroutine 生命周期**：
  - `go func(){...}` 无退出条件（for 循环 + select 无 done channel）
  - WaitGroup 不正确（`Add` 在 goroutine 内、`Done` 缺 defer）
  - 主流程返回但 goroutine 还活着
- **interface 设计**：
  - 接口定义在实现包（应定义在消费者包）
  - 空接口 `interface{}` / `any` 滥用
  - 过大接口（应拆小）
- **errors.Is/As**：err 比较用 `==` 而非 `errors.Is`
- **map 并发读写**：未用 sync.Map / mutex
- **slice 陷阱**：append 共享底层数组、`s[:]` 内存泄漏（持有大底层数组的小切片）
- **defer 性能**：循环内 defer

### 示例反模式
```go
// BAD
ch := make(chan int)
go func() { ch <- 1 }()  // 写阻塞，若无 read 永远不退出

for _, item := range items {
    defer close(item)  // 循环内 defer，全部累积到函数返回
}
```

---

## Java

### 必查
- **空指针**：`Optional` 适用未用、链式 `a.b().c().d()` 任一返回 null
- **事务传播**：`@Transactional` 在 private 方法（无效）、自调用绕过代理、事务嵌套传播错误
- **线程池**：
  - `Executors.newFixedThreadPool` 无界队列 → OOM
  - 提交任务未 try/catch → 线程静默死掉
  - shutdown 缺失
- **Spring 生命周期**：
  - 单例 Bean 持有 prototype Bean（应注入 `ObjectProvider`）
  - `@PostConstruct` 抛异常导致启动失败但日志难定位
  - 循环依赖
- **ORM 查询**：
  - `@OneToMany` 无 `fetch = LAZY` + N+1
  - 实体逃出事务 → LazyInitializationException
  - 批量操作未用 batch
- **Stream API**：
  - `parallelStream` 在 ForkJoinPool 公共池阻塞
  - terminal 操作多次（`.collect()` 用于已收集流）
- **try-with-resources**：手动 close 容易漏
- **String / StringBuilder**：循环内 + 拼接
- **equals / hashCode**：只重写一个

---

## Python

### 必查
- **类型问题**：
  - 缺 type hints；hints 与实际不符
  - 可变默认参数（`def f(a=[])`）
- **GIL 影响**：
  - 多线程做 CPU 密集（应 multiprocessing）
  - IO 密集多线程是 OK 的，但日志/print 串行化竞争
- **异常处理**：
  - 裸 `except:` 抓 KeyboardInterrupt
  - `except Exception` 后无 logging
- **资源管理**：
  - `open()` 不用 with
  - 数据库连接 / 文件句柄未关
- **pandas/numpy 性能**：
  - DataFrame 行循环（应 vectorize）
  - `iterrows()` / `itertuples()` 大数据
  - `.apply` lambda 串行
  - 不必要的 `.copy()`
  - dtype 错误导致 object 列（慢 10x）
- **闭包陷阱**：循环内闭包捕获循环变量（应默认参数固定）
- **mutable global state**：跨模块共享 dict / list

---

## TypeScript / JavaScript

### 必查
- **any 滥用**：尤其在边界类型（API 响应、第三方库）
- **类型断言 `as`**：跳过类型检查
- **Promise 错误**：
  - `async` 函数无 try/catch
  - `.then(onResolve, onReject)` 而非 `.catch`
  - Promise 数组 `for await` 串行（应 `Promise.all`）
  - 未 await 的 Promise 静默丢失
- **React 状态**：
  - useState 闭包陈旧（stale closure）
  - useEffect 依赖数组缺项 / 多项
  - 状态对象嵌套深 → 浅比较失效
  - setState in render
  - useEffect 内 async（应内部 IIFE）
- **null/undefined**：`==` vs `===`、可选链 `?.` 缺失
- **内存泄漏**：
  - 事件监听器未 removeEventListener
  - setInterval 未 clearInterval
  - 闭包持有大对象
- **不可变数据**：直接 mutate state / props
- **bundle size**：大库 import 全量（应 tree-shake）

---

## C#

### 必查
- **async/await**：
  - `async void`（除事件）
  - `Task.Result` / `.Wait()` 阻塞调用
  - `lock` 内 `await`
  - 库代码缺 `ConfigureAwait(false)`
  - 长任务无 CancellationToken
  - `Task.Run` 包同步代码挂 UI 上下文
- **IDisposable**：
  - 实现 IDisposable 类未实现完整 Dispose pattern
  - using 缺失
  - 字段类型 IDisposable，外层类未实现 IDisposable
  - Finalizer 中调用其他对象方法
- **WPF / WinForms UI 线程**：
  - 后台线程访问 UI 元素
  - `Dispatcher.Invoke` 与 `BeginInvoke` 误用（同步 vs 异步）
  - 事件订阅未解订阅（典型内存泄漏）
- **unsafe / PInvoke**：
  - `fixed` 边界 / 越界
  - `[DllImport]` 字符串编码（Ansi vs Unicode）
  - StringBuilder 长度未指定
  - struct 布局 `[StructLayout(LayoutKind.Sequential, Pack=...)]`
- **LINQ 性能**：
  - 多次枚举（`Count() > 0` 应 `Any()`、`Where().Count()` 应 `Count(predicate)`）
  - 链中多 `ToList()`
  - 在 IQueryable 上调 ToList 强制全量
- **boxing/unboxing**：值类型存 object 容器、`string.Format` 装箱
- **EF Core**：
  - N+1（缺 Include 或 ThenInclude）
  - Tracking 不必要（只读应 AsNoTracking）
  - SaveChanges 在循环内
  - 同步阻塞（用 await SaveChangesAsync）
- **nullability (#nullable enable)**：
  - `null!` 抑制警告
  - bang `!` 滥用
  - 返回 null 但签名非 nullable
- **LOH**：> 85K 字节对象频繁分配 → Gen2 GC
- **反射**：热路径未缓存 MethodInfo / PropertyInfo
- **string**：
  - 循环 `+=`
  - `Substring` 大字符串（应 `Span<char>`）
  - `string.Split` 临时数组热路径
- **DateTime / DateTimeOffset**：跨时区用 DateTime
- **Decimal vs double**：金钱用 double（精度问题）

---

## C++

### 必查
- **RAII**：
  - 手动 `new`/`delete` → 改 unique_ptr
  - 资源类未实现析构（fd / handle / lock）
- **移动语义**：
  - 函数返回大对象未利用 RVO
  - 移动后使用源对象（已被掏空）
  - `std::move` 在 const 上无效
- **智能指针**：
  - `unique_ptr` 按值传递（应按引用 / 移动）
  - `shared_ptr` 循环引用（用 weak_ptr 打破）
  - `shared_ptr` 频繁拷贝（原子计数开销）
  - `make_shared` vs `shared_ptr(new ...)`（make_shared 一次分配）
- **STL 性能**：
  - `vector::erase` 循环内（O(N²)）→ 用 erase-remove
  - `map` 应改 `unordered_map`（O(log N) → O(1) 均摊）
  - `std::endl` 强制 flush（应用 `'\n'`）
  - `push_back` 未 reserve
  - copy elision / SSO 不利用
- **内存对齐 / 缓存**：
  - 热数据结构 false sharing（多线程不同变量同一 cacheline）
  - struct 字段顺序导致 padding
- **UB**：
  - 有符号整数溢出
  - 严格别名（reinterpret_cast 跨类型读）
  - 未初始化局部变量读取
  - shift 超过位宽
- **类设计**：
  - 基类析构未 `virtual`
  - rule of three/five 不一致
  - explicit 缺失（单参数构造）
- **异常安全**：
  - 构造函数抛异常 → 资源泄漏
  - noexcept 缺失（影响优化）
  - basic / strong guarantee 不清
- **C++17/20 现代特性**：
  - `auto` 在公开 API 滥用
  - `[[nodiscard]]` 缺失
  - `std::optional` / `std::variant` 适用未用
- **ABI**：
  - 跨 DLL 传 std 容器（不同 CRT）
  - 跨 DLL 抛异常
  - 内联函数与导出符号冲突
- **多线程**：
  - 缺 `std::atomic` / `std::mutex`
  - 内存序错误（`memory_order_relaxed` 不够）
  - condition_variable 缺 predicate（spurious wakeup）

---

## HALCON

### 必查
- **HObject 生命周期**：
  - `out HObject obj` 接收后未 Dispose
  - 字段类型 `HObject`，新赋值前未释放旧值
  - 异常路径未释放（缺 finally）
  - 多重引用 + 任一方 Dispose 导致其他方失效
- **HObject 拷贝语义**：
  - **`new HObject(obj)`** = 增加引用计数（轻量）
  - **`HOperatorSet.CopyObj(src, out dst, 1, count)`** = 深拷贝（每元素都复制 HALCON 内部对象）
  - 性能场景应优先用 `new HObject(...)` 增加引用计数；只在需要独立修改时才 CopyObj
- **HTuple 误用**：
  - 类型混淆（`.D` `.I` `.S` `.L` 错调）
  - 多余 `.Clone()`（HTuple 是值语义包装，多数场景不需要克隆）
  - HTuple 与原生类型频繁转换
- **算子调用顺序**：
  - 大图未先 `ReduceDomain` 就 `Threshold` / `EdgesSubPix`
  - `Connection` 后未 `SelectShape` 直接遍历所有 region
  - `Reduce` 已 reduce 过的图（无意义）
- **ROI 优化**：
  - 全图算子（应 `ReduceDomain` + `GenRectangle1`）
  - ROI 反复生成（应缓存固定 ROI）
- **region/xld 转换**：
  - `RegionToContourXld` ↔ `GenRegionContourXld` 来回转
  - `GenContourPolygonXld` + `GenRegionPolygonXld` 多余链
- **`count_obj` / `select_obj` 性能**：
  - 元组大时反复 select；可一次性 hung 起来用 `obj_to_tuple` 取索引
- **重复算子**：
  - 相同参数 `Threshold` 在循环内 / 每帧重算 `GenStructuringElement`（应缓存）
- **模型句柄**：
  - `ReadShapeModel` / `ReadOcvModel` / `ReadOcr` 后忘 `ClearShapeModel` 等
  - 重新加载模型未先释放旧句柄
  - Deep Learning 模型句柄 `ClearDlModel`
- **相机 / OpenFramegrabber**：
  - `OpenFramegrabber` 后异常路径 `CloseFramegrabber` 缺失
  - `GrabImage` 失败无重试 / 无超时
  - 多相机共享 hWindow
- **并行采图线程安全**：
  - HALCON 算子大部分可重入但部分非线程安全（窗口操作、`SetSystem`）
  - 多线程同时调 `DispObj` 同一窗口 → 渲染竞争
  - `flush_graphic` 是全局参数，多线程切换互相覆盖
- **HALCON 与 C# 混调**：
  - HObject 通过 `Marshal` 传给 C++ 后双方释放策略不清
  - 跨语言 HTuple 容易内存归属不明
- **大图内存**：
  - 4K / 8K 图像 Mat / HObject 数 GB 级，避免无意义的 `CopyObj`
  - `CountObj` 前确认是否需要全量复制
- **可维护性**：
  - 算子链硬编码在 UI（应配方化）
  - 配方参数无版本号
  - 中间结果缓存策略不明确
- **异常**：
  - `HOperatorException` 未单独捕获（混在 `Exception` 里看不出 HALCON 错误码）
  - 错误码 `ex.GetErrorCode()` / `ex.GetErrorMessage()` 未利用

### HALCON 特殊代码味
```csharp
// BAD: 重复创建 ROI、缺 Dispose、HALCON 异常被吞
foreach (var img in images)
{
    try {
        HOperatorSet.GenRectangle1(out HObject roi, 0,0,100,100);
        HOperatorSet.ReduceDomain(img, roi, out HObject r);
        // ... 用 r ...
    } catch (Exception) {}
}
```

```csharp
// GOOD: ROI 缓存 + 异常类型化 + finally 释放
private readonly HObject _roi;  // ctor: GenRectangle1(out _roi, ...)
foreach (var img in images)
{
    HObject reduced = null;
    try {
        HOperatorSet.ReduceDomain(img, _roi, out reduced);
        // ... 用 reduced ...
    }
    catch (HOperatorException ex) {
        _log.LogError(ex, "Reduce failed code={Code}", ex.GetErrorCode());
        throw;
    }
    finally { reduced?.Dispose(); }
}
```

---

## OpenCV / 工业视觉

### 必查
- **Mat 拷贝语义**：
  - `cv::Mat a = b;` = 引用计数（浅拷贝）
  - `a = b.clone();` 或 `b.copyTo(a)` = 深拷贝
  - return Mat 时 `clone()` 多余（RVO）
- **GPU / CPU 切换**：
  - `upload` / `download` 在循环内
  - 一帧内多次切换
- **图像格式转换**：
  - imread 默认 BGR；如果只要 gray，直接 `IMREAD_GRAYSCALE`
  - BGR ↔ RGB ↔ HSV 反复转换
- **ROI**：
  - `Mat::operator()` ROI 是浅拷贝（共享底层），修改会影响原图（双刃剑）
  - `setTo` / `copyTo` 配合 mask
- **多线程**：
  - OpenCV 大多算子非线程安全（即便 Mat 不同也可能共享 OpenCL 上下文）
  - 推荐每线程独立 cv::Mat / cv::UMat
- **数据类型**：
  - `CV_8UC3` 当 `CV_8UC1`（深度 / 通道错位）
  - 大图 `at<T>(i,j)` 慢（应 `ptr<T>(i)`）
- **GUI**：
  - `imshow` + `waitKey` 在 worker 线程（必须 main 线程）
  - `imshow` 大图自动 resize 开销
- **CUDA**：
  - cv::cuda::Stream 缺失（同步等待）
  - host/device 内存频繁分配
- **dnn 模块**：
  - 模型加载在循环内
  - blob 复用未利用

### 工业视觉 Pipeline 通用
- **配方 / 工艺管理**：版本号、参数白名单、外部可视化编辑
- **中间结果**：可序列化、可重放、可追溯
- **异常恢复**：单帧失败不影响整线；崩溃自动重连相机
- **资源监控**：HObject 计数、Mat 计数、GPU 显存、相机 FPS
- **日志结构化**：帧号 / 通道号 / 算子耗时 / 输入输出 hash
- **可测试性**：算子函数纯函数化，输入图像 + 参数 → 输出结果；UI 不参与计算
