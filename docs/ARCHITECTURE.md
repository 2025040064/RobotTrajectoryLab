# RobotTrajectoryLab V1.0 架构与实施记录

## 目标与边界
在当前空目录新建纯 MATLAB R2025a 中文科研工作台。第一阶段交付 UR5 关节五次轨迹、约束与采样碰撞检查、解析时间缩放、移动机器人四邻域 A*、安全路径处理、三维回放、MAT/CSV/PNG 导出与自动化测试。按用户补充要求增加 Windows 打包与作业说明；IK、其他搜索器、通用求解器优化和批量实验不在本次范围。

## 已核查环境
MATLAB 25.1.0.2943329 (R2025a)。UR5、quinticpolytraj、checkCollision、plannerAStarGrid 已实际调用。rigidBodyTree.show 不支持 UIAxes；采用 uifigure → uipanel → 经典 axes，FastUpdate 与工具栏已验证。A* 创建后分别设置 DiagonalSearch、GCost、HCost、TieBreaker，避免构造器参数上限。

## 分层
main.m 仅负责入口。+rtl 内按 +app、+models、+kinematics、+planning、+optimization、+simulation、+io 分工。GUI 调用无界面算法，不持有第二份业务参数。项目保存普通结构；机器人对象只作运行时缓存。所有持久化文件使用 schemaVersion=1；内部米、秒、弧度，界面关节编辑采用度。

## 数据契约
项目为 struct：schemaVersion、name、arm、mobile。arm/mobile 本身是完整规划 request，含 kind、algorithm、start、goal、options、seed。arm.model='universalUR5'，arm.endEffector='tool0'；arm.start/goal 为 1×6 弧度；options 含 duration_s、samplePeriod_s、velocityLimits (1×6)、accelerationLimits (1×6)、scaleTime、collisionStep_rad、boxes (N×6，中心 xyz、尺寸 xyz)。mobile.map 含 rows、cols、cellSize_m、originXY_m、rectangles (N×4：[row col height width])；start/goal 是 1×2 栅格索引。移动 options 含 robotRadius_m、safetyMargin_m、smoothIterations、referenceSpeed_m_s。

统一入口 rtl.planning.plan(request) -> result。result 含 schemaVersion、id、kind、algorithm、status、message、request、createdAt、softwareVersion、matlabRelease、rawPath、finalPath、trajectory、baseline、metrics、constraints、collision、diagnostics。status 为 success/no_path/invalid_input/validation_failed/error。失败不冒充成功。路径使用 N×2 或 N×3 世界坐标。机械臂 trajectory：t (1×N)、q/qd/qdd (6×N)、tcp (3×N)；移动：t、position (2×N)、yaw。baseline 保存优化前 trajectory/metrics。metrics 字段名带单位，GUI 动态显示。diagnostics 为 cellstr。

## 机械臂
官方 UR5/tool0、quinticpolytraj/getTransform/geometricJacobian。零端导数、两点同步轨迹，解析极值检查。速度和加速度默认 1 rad/s 与 2 rad/s²，标为仿真设定。固定路径时间缩放不声称全局最优。碰撞按关节路径采样，最大角步长 0.02 rad，包含自碰撞和箱形环境，仅跳过父子配对；报告分辨率，不宣称连续证明。FK 独立连乘与雅可比差分进行数值验证。

## 移动机器人
默认 60×80、0.1 m/格。矩形列表为地图编辑源，栅格矩阵由它生成；第一行位于地图顶部，world2grid/grid2world 集中处理。官方四邻域 A*，Manhattan 代价，TieBreaker 关闭。圆形足迹+安全距离+半格对角线保守膨胀；边界内缩。对所有输出线段计算到原始占用格中心的解析距离，以占用格外接圆补偿，不依赖稀疏采样。直连简化后两轮 Chaikin 圆角，复检失败回退。保守近似可能拒绝窄通道，不能自动缩小安全距离。

## GUI 与生命周期
六页：工作台、模型与环境、运动规划、三维仿真、优化与分析、实验记录。浅色、左侧导航、可滚动参数区；1280×800 与 1920×1080 视觉检查。参数改变立即使当前结果失效。同步分步规划显示繁忙态、防止重入；计时器回放支持暂停、重置、进度与倍速，关闭窗口释放资源。移动仿真为平面路径的三维展示，非动力学或跟踪控制。

## 数据与验证
实验保存算法、输入、seed、版本、环境、时间、结果和诊断。MAT 重载普通结构，CSV 数值带单位，PNG 导出图表；计算耗时、运动时间与回放参考时间分开。输出放 results/，临时验证产物放项目内，交付前清理无用临时文件。

实施顺序：契约 → 两类核心及测试 → GUI → 回放/导出 → R2025a 自动化与可见界面验收。发现缺陷先补失败测试。测试覆盖 FK/J、端点/峰值/缩放、碰撞/非法参数、A* 最短代价/无路径、坐标/安全距离/路径处理、保存重载、GUI 与资源释放。环境探测不计作项目验收。

## 实施记录
- 2026-10-25：用户授权将工程推送到 `2025040064/RobotTrajectoryLab` 并发布 v1.0.1。接续远端 main 的初始 README 提交，源码与指定示例/验收证据纳入 Git，安装器、卸载器和两份 PDF 作为独立 Release 附件。忽略构建缓存、日志、历史运行及 dist，不上传密钥或 .env。发布与下载校验通过后，清理本次发布中间文件及旧版重复打包文件，保留源码、当前交付及实验/验收记录。
- 2026-10-25：按用户要求增加独立卸载入口。小型 Windows 图形程序从当前用户和本机卸载注册表读取 RobotTrajectoryLab 与 MATLAB Runtime R2025a 的官方卸载命令；两项分别由用户点击启动。不复制官方卸载器、不自行删除安装目录或实验数据、不自动连带卸载共享运行库。仅验证发现、命令解析与界面，不执行实际卸载。
- 2026-10-25：增加约 9 KB 的 Windows 图形启动器（packaging/WindowsLauncher.cs），仅负责读取 Runtime 注册位置、设置子进程 DLL 路径与显示加载进度；MATLAB 核心界面和算法不改语言。启动器在界面就绪后隐藏，保留生命周期管理直到 MATLAB 子进程退出。数据写入用户主目录，避免安装到 Program Files 后权限不足。用户确认必须遵守 MATLAB 开发要求，可接受 Runtime，因此不转为其他语言的小程序。最终交付为未压缩目录，含完整安装程序、使用说明、技术要点与创新点三文件。
- 2026-10-25：用户报告双击后只有黑色终端。部署回归检查确认旧 EXE 的 Windows Subsystem=3（控制台）；改用 standaloneWindowsApplication 生成 GUI Subsystem=2，并增加产品启动图、正常冷启动验证入口 --startup-check 与 startup_report.json。启动失败使用可见错误框，正常启动和自检共用同一条 GUI 初始化流程。版本 1.0.1；安装器显式排除可选 Runtime 依赖，并记录 required/optional 清单，保留必需图形组件。使用用户新安装的独立 Runtime 验证，不能沿用开发环境运行库的旧结论。
- 2026-10-24：用户批准方案，开始实施；没有旧工程或用户数据需要迁移。
- 2026-10-24：核心与六页 GUI 已实现；MATLAB 数值验证确认 UR5 FK/雅可比、五次解析峰值及采样碰撞结果。A* 官方 PathCost 已是米，不能再乘格宽。
- 2026-10-24：页面采用同一网格单元叠放、切换 Visible，由网格负责自适应；分析页清除隐藏基线且保持轴布局，避免跨机器人残留曲线。参数编辑事务化回滚，恢复历史先校验候选项目，规划启动及清理检查对象生命周期。
- 2026-10-24：完成两个领域的真实 MAT/CSV 示例导出；中文 GUI 使用 MATLAB UITest 按钮操作和 1280×800 / 1920×1080 截图复核。最终验收数字见 ACCEPTANCE.md，不将环境探测计作产品验收。
- 2026-10-25：明确仅打包现有第一阶段作业。新增 RobotTrajectoryLab.m 独立入口、build_release.m、package_release.ps1；UR5 模型随包保存为 assets/models/universalUR5.mat。main 支持显式 DataRoot，避免用户结果写入部署解压区；安装版默认用户主目录，便携启动脚本使用包内 Data 目录。
- 2026-10-25：再次完整回归 51/51 通过，0 失败、0 未完成，测试耗时合计 108.704 s。MATLAB Compiler 实际生成 EXE 与在线 Runtime 安装器；本机没有单独安装 Runtime，EXE 验证使用当前进程临时指定的 MATLAB 开发环境运行库，不修改系统 PATH。部署报告区分 isDeployed=true 与普通 MATLAB 调用。
