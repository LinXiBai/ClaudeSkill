# Code Review Checklist

按章节逐条对照。**不要跳过任何一项**——找不到问题也要在心里过一遍，确认确实不存在。

---

## 一、安全（Security）

### 注入类
- [ ] SQL 注入：字符串拼接 SQL、未参数化、ORM 原生查询拼接
- [ ] 命令注入：`Process.Start` / `exec` / `system` 接受外部输入未转义
- [ ] LDAP / XPath / 模板注入
- [ ] 反序列化注入：`BinaryFormatter` / `pickle` / `Newtonsoft.Json TypeNameHandling.All`

### Web / 网络
- [ ] XSS：未转义的 HTML 输出、`innerHTML` 拼接用户输入
- [ ] SSRF：HTTP 客户端接受外部 URL 未校验
- [ ] CSRF：缺失 Token、SameSite cookie 未设置
- [ ] CORS 配置过于宽松（`*` 配合 credentials）
- [ ] 路径遍历：`File.Open(userInput)` 未 `Path.GetFullPath` + 白名单校验
- [ ] 开放重定向：`Redirect(userInput)`

### 敏感信息
- [ ] 硬编码：密码、API Key、连接字符串、私钥、Token
- [ ] 日志泄露：日志打印密码 / Token / PII / 银行卡 / 身份证
- [ ] 错误页面泄露：堆栈、SQL、内部路径返回给前端
- [ ] HTTPS 缺失 / 证书校验关闭（`ServerCertificateValidationCallback = (_,_,_,_)=>true`）

### 加密 / 认证
- [ ] 弱算法：MD5/SHA1 用于密码、DES、RC4
- [ ] 自实现加密
- [ ] JWT 签名校验缺失 / `alg: none` 允许
- [ ] 会话固定 / 会话不失效 / 密码明文存储

---

## 二、性能（Performance）

### 算法 / 数据结构
- [ ] O(N²) 嵌套循环（含 LINQ `Where().Where()` 链）
- [ ] List 频繁 `Contains` 应改 HashSet
- [ ] 字符串拼接循环（应 StringBuilder）
- [ ] 重复计算（应缓存）

### 数据访问
- [ ] N+1 查询：循环内查数据库 / 调接口
- [ ] 缺失索引（明显的全表 WHERE）
- [ ] 大数据集 `ToList()` 全量加载
- [ ] 缺失分页

### 资源 / 对象
- [ ] 大对象频繁创建（Mat / HObject / Bitmap / 大数组）
- [ ] 不必要的深拷贝（`Mat.clone()` / `new HObject(obj)`）
- [ ] 装箱拆箱（`object` 容器存 int）
- [ ] LOH 频繁分配（> 85K 字节）
- [ ] 反射 / 动态代理热路径调用

### IO / 网络
- [ ] 同步阻塞 IO 在异步上下文
- [ ] HttpClient 短生命周期（应单例）
- [ ] 缺失流式读写（一次性 ReadAllBytes 大文件）
- [ ] 缺失缓存（重复读相同配置 / 字典）

### 并发性能
- [ ] 高频锁竞争
- [ ] 锁粒度过大（lock 包整个方法）
- [ ] `lock` 内调用阻塞方法 / 异步方法

---

## 三、并发（Concurrency）

### 通用
- [ ] race condition：共享可变状态无同步
- [ ] check-then-act 非原子（ContainsKey + Add）
- [ ] ABA 问题
- [ ] 可见性：跨线程读写无 volatile / memory barrier

### 死锁 / 活锁
- [ ] 锁顺序不一致
- [ ] `lock` 内 await（C#）/ block on Task.Result
- [ ] 锁内同步调用回调
- [ ] async 死锁（UI 线程 + ConfigureAwait(false) 缺失 + .Result）

### 容器 / 集合
- [ ] 非线程安全 Dictionary / List 多线程读写
- [ ] `ConcurrentDictionary.AddOrUpdate` 的 factory 内修改外部状态
- [ ] foreach 遍历集合期间被改写
- [ ] LINQ 并行（`.AsParallel()`）副作用

### 异步
- [ ] `async void`（除事件处理器）
- [ ] 未 await 的 Task 被丢弃
- [ ] CancellationToken 未传递
- [ ] Task.Run 包裹同步代码挂在 UI 上下文
- [ ] Goroutine 泄漏（启动后无退出条件）
- [ ] channel 死锁（无人读 / 关闭后写）

---

## 四、架构（Architecture）

- [ ] 单一职责：函数 > 100 行、类 > 500 行
- [ ] 接口暴露过多内部细节
- [ ] 循环依赖
- [ ] 上帝类：核心业务全堆一个类
- [ ] 分层混乱：DAL 直调 UI、UI 直访 DB
- [ ] 不一致的错误传播策略
- [ ] 全局可变状态滥用（单例、`static` 字段）
- [ ] 过早抽象 / 过度泛型
- [ ] 缺失抽象：相同代码复制 3 次以上
- [ ] 依赖具体类而非接口（不利于测试）

---

## 五、错误处理（Error Handling）

- [ ] 空 catch 块：`catch {}` / `catch (Exception) {}`
- [ ] catch 后 swallow（无 log / 无 rethrow / 无业务降级）
- [ ] catch 类型过宽（`catch (Exception)` 而非具体类型）
- [ ] catch 后 `throw ex;`（丢失堆栈，应 `throw;`）
- [ ] 缺失 finally / using
- [ ] 资源释放在 try 内（异常时漏释放）
- [ ] 错误码与异常混用
- [ ] 业务异常 vs 系统异常未区分
- [ ] retry 无退避 / 无上限
- [ ] 异常被转换为 bool 返回值，调用方忽略

---

## 六、日志监控（Logging & Monitoring）

- [ ] 关键路径无日志（入参 / 出参 / 异常）
- [ ] 日志级别错误（错误用 Info、调试用 Error）
- [ ] 字符串插值 vs 模板（C# Serilog 推荐模板）
- [ ] 日志风暴（循环内打日志、Debug 级别误为 Info）
- [ ] 日志泄露敏感数据（密码、Token、PII）
- [ ] 缺失链路追踪（TraceId / RequestId）
- [ ] 缺失关键业务指标（Metric / Counter）
- [ ] 健康检查 / Readiness 缺失

---

## 七、内存与资源（Memory & Resources）

### 通用
- [ ] IDisposable 类未实现 / 实现不完整（Dispose pattern）
- [ ] using 缺失：FileStream / SqlConnection / HttpClient
- [ ] 事件订阅未解订阅（`+=` 没对应 `-=`）→ UI / 单例引用泄漏
- [ ] 静态字段持有长生命周期对象
- [ ] WeakReference / WeakEventManager 适用场景未用
- [ ] Finalizer 中调用受管对象方法
- [ ] GC.Collect() 滥用
- [ ] LOH 频繁分配（> 85K 字节）：大数组 / 大字符串 / 大位图导致大对象堆碎片化、Gen2 GC 压力

### HALCON / OpenCV / 工业视觉
- [ ] HObject 未 Dispose：`out HObject` 收完未释放、字段重赋值不释放旧值
- [ ] HObject 在异常路径泄漏（缺 finally）
- [ ] HOperatorSet.GenXxx 后的中间对象不释放
- [ ] Mat 未 release / 字段重赋值
- [ ] Bitmap / Image 未 Dispose
- [ ] 相机句柄未关闭（`CloseFramegrabber` / `Stop`）
- [ ] 大图像复制（不必要的 clone / copyTo）
- [ ] ShapeModel / NCC / DL 模型句柄不释放（`ClearShapeModel`）

---

## 八、可维护性（Maintainability）

- [ ] 命名：拼音 / 缩写 / 单字母 / 误导命名
- [ ] 魔法值：硬编码数字 / 字符串散落
- [ ] 重复代码：相同片段 ≥ 3 处
- [ ] 长方法：> 100 行 / 嵌套 > 4 层 / 圈复杂度 > 15
- [ ] 巨型函数 / 上帝方法
- [ ] 注释错误 / 与代码不符 / 仅复述代码
- [ ] 公开 API 缺文档
- [ ] 测试缺失（核心业务无单测）
- [ ] 死代码 / 注释代码块
- [ ] TODO / FIXME 未跟进

---

## 九、C# 特有

- [ ] IDisposable 实现不完整（缺 Dispose(bool) pattern）
- [ ] using 声明 / using 语句缺失
- [ ] async deadlock：UI 上下文 + `.Result` / `.Wait()`
- [ ] `Task.Result` / `.Wait()` 阻塞调用
- [ ] LINQ 性能：多次枚举、Where().Count() 改 Count(predicate)
- [ ] boxing：值类型存 object 容器
- [ ] EF Core：N+1、Include 缺失、Tracking 滥用、SaveChanges 在循环内
- [ ] nullability：缺失 `?` 注解、`null!` 滥用、`bang` 抑制警告
- [ ] ConfigureAwait：库代码应 `ConfigureAwait(false)`，UI 代码反之
- [ ] LOH：> 85K 字节对象频繁分配
- [ ] 反射热路径：Activator.CreateInstance / GetMethod 未缓存
- [ ] PInvoke：参数 marshaling 错误、StringBuilder 长度未指定
- [ ] unsafe / fixed：边界检查
- [ ] WPF / WinForms：UI 线程访问、Dispatcher 误用、绑定泄漏
- [ ] struct 过大（> 16 字节传值开销）
- [ ] readonly struct / in 参数适用未用

---

## 十、C/C++ 特有

- [ ] 野指针：未初始化指针、悬空引用
- [ ] use-after-free
- [ ] double free
- [ ] buffer overflow：strcpy / sprintf / 数组越界
- [ ] 未初始化内存读取
- [ ] RAII 缺失：手动 new/delete、缺析构
- [ ] 智能指针误用：`unique_ptr` 传值复制、`shared_ptr` 循环引用、`weak_ptr` 缺失
- [ ] 移动语义：未用 `std::move`、移动后使用
- [ ] 虚函数析构：基类析构未 virtual
- [ ] 多重继承 / 菱形继承陷阱
- [ ] ABI 风险：跨 DLL 传 std::string / std::vector
- [ ] STL 性能：`vector.erase` 循环内、`map` 应改 `unordered_map`
- [ ] memcpy / memset 风险：非 POD 类型、size 错误
- [ ] 未定义行为：有符号溢出、严格别名违反、未初始化布尔
- [ ] 多线程共享：缺 atomic / mutex / 内存序错误
- [ ] new / delete 不配对 / 数组 new 用 delete（非 delete[]）
- [ ] 异常安全：构造抛异常资源泄漏

---

## 十一、HALCON 特有

- [ ] HObject 生命周期：`out` 收对象后未释放
- [ ] HObject 字段重赋值未 Dispose 旧值
- [ ] HTuple 类型混用（D vs I vs S）
- [ ] HTuple.Clone() 滥用（HTuple 是值类型语义，多数场景不需要）
- [ ] 大图像深拷贝（`new HObject(img)` 在 .NET 是引用计数，但 `HOperatorSet.CopyObj` 是深拷贝）
- [ ] ReadShapeModel / ReadOcvModel 后模型句柄未 `Clear*Model`
- [ ] OpenFramegrabber 后 CloseFramegrabber 缺失
- [ ] 算子调用顺序：Domain 未设置就处理大图、未 ReduceDomain
- [ ] ROI 优化：全图处理 / Reduce 缺失 / Domain 反复重设
- [ ] count_obj / select_obj：大元组反复扫描
- [ ] region/xld 转换冗余（Region → XLD → Region 来回转）
- [ ] 重复算子：相同参数算子在热路径多次执行
- [ ] 并行采图未隔离：多相机共享同一 HWindow
- [ ] HWindow 渲染竞争（多线程同时 DispObj）
- [ ] 图像格式转换开销（mono → rgb 反复）
- [ ] HALCON 算子异常未处理（`HOperatorSet.XxxOp` 失败抛 HOperatorException）
- [ ] **HALCON 句柄表满**：长跑进程中 HObject / HTuple / Region 持续创建而不释放，触达 HALCON 内部句柄表上限（默认 65536）→ `HOperatorException` 或进程崩溃。检查：长循环内是否 try-finally Dispose、字段重赋值是否释放旧值、模型句柄是否定期 Clear*Model

---

## 十二、OpenCV / 工业视觉

- [ ] Mat 浅拷贝/深拷贝混淆（`=` vs `.clone()`）
- [ ] `Mat.clone()` / `copyTo()` 热路径滥用
- [ ] GPU ↔ CPU 频繁切换（`upload` / `download` 在循环内）
- [ ] 图像格式转换开销（BGR/Gray/HSV 反复）
- [ ] ROI 缺失：全图算子 vs ROI 算子
- [ ] 多线程访问同一 Mat（OpenCV 大多算子非线程安全）
- [ ] 通道 / 类型 mismatch：`CV_8UC3` 当 `CV_8UC1`
- [ ] 内存对齐：性能敏感场景 stride / continuous
- [ ] 大图像 imshow（自动 resize 开销 + 同步等待）
- [ ] cv::waitKey 在 worker 线程

---

## 十三、视觉 Pipeline 可维护性

- [ ] 算子链耦合：UI 直接驱动算子
- [ ] 配方文件格式不固化（XML 结构频繁变动无版本号）
- [ ] 中间结果缓存策略不明确
- [ ] 配置参数硬编码 vs 配置文件
- [ ] 模型版本管理缺失
- [ ] 日志关键节点缺失（每步耗时、每步输入输出 hash / 尺寸）
- [ ] 异常恢复策略缺失（单帧失败 → 整线停摆 vs 跳过）
- [ ] 相机断线重连
- [ ] 资源回收时机（配方切换、应用退出）
