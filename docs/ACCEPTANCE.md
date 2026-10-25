# RobotTrajectoryLab V1.0 第一阶段验收记录

日期：2026-10-24。环境：Windows / MATLAB `25.1.0.2943329 (R2025a)`，使用 Robotics System Toolbox、Navigation Toolbox。第一阶段实施、真实自动化测试、可见界面走查和截图复核已完成；按用户要求在本阶段交付后停止，不进入后续阶段。

## 交付与来源

本工程在空工作目录新建，没有旧代码迁移、已有产品原型或第三方模板改造。界面为程序化中文 `uifigure`；机械臂和移动算法采用 MATLAB 官方 API，业务逻辑、数据接口、界面和测试源码均在本工程内。

| 层次 | 实际文件与职责 |
| --- | --- |
| 入口与界面 | `main.m`、`+rtl/+app`：六页工作台、参数状态、历史、分析显示与计时器生命周期 |
| 模型与运动学 | `+rtl/+models`、`+rtl/+kinematics`：UR5、FK、独立变换连乘、雅可比验证适配和采样碰撞检查 |
| 规划与处理 | `+rtl/+planning`、`+rtl/+optimization`：统一入口、五次轨迹、解析时间缩放、栅格 A*、连续线段安全检查和路径处理 |
| 回放与持久化 | `+rtl/+simulation`、`+rtl/+io`：保存轨迹的帧插值、场景、普通结构 MAT、轨迹与摘要 CSV、日志和环境版本 |
| 验证与示例 | `tests`、`examples/run_examples.m`、`run_tests.m`、`validate_ui.m` |

已实现的两条完整流程：UR5 关节起终点→同步五次轨迹→解析速度/加速度约束与采样碰撞检查→固定路径时间缩放→三维回放与导出；移动地图/矩形障碍→四邻域 A*→安全直连简化与 Chaikin 候选复检→平面路径三维回放与导出。参数变化使当前结果失效，MAT 项目和单次实验可重新加载。

## 运行与公共接口

在 MATLAB 中切换到工程根目录：

```matlab
app = main;                       % 可见窗口
hiddenApp = main(Visible="off");  % 自动化入口
delete(hiddenApp);
run_tests;                        % 全套验证及报告
run_tests(CoreOnly=true);          % 算法和数据接口
validate_ui;                      % 可见窗口操作与截图
addpath(fullfile(pwd,"examples"));
outputs = run_examples;            % 三个可复现实验并真实导出
```

- `rtl.defaultProject()` 返回 `schemaVersion=1` 的完整项目配置；`rtl.planning.plan(request)` 返回结构化结果，状态区分 `success/no_path/invalid_input/validation_failed/error`。
- 机械臂调用 `loadrobot('universalUR5')`、`getTransform`、`geometricJacobian`、`quinticpolytraj`、`checkCollision`；移动规划使用 `binaryOccupancyMap`、`plannerAStarGrid`、`world2grid/grid2world`。机械臂三维展示使用嵌入 `uifigure` 的经典 `axes`。
- `rtl.io.saveProject/loadProject/validateProject` 校验项目；`saveResult/loadResult` 保留成功及失败实验；`exportResult` 返回 `mat/trajectory/summary` 路径。持久化不保存图窗、计时器或机器人对象。
- 项目内部使用米、秒、弧度。机械臂 `q/qd/qdd` 为 `6×N`；移动路径为世界坐标 `N×2`。CSV 英文列名包含单位，MAT 保存请求快照、seed、原始/最终结果、约束、诊断、软件和 MATLAB/工具箱版本。
- 自动结果：`results/<id>/result.mat`；手动导出：`<id>.mat`、`<id>_trajectory.csv`、`<id>_summary.csv`，GUI 另生成分析 PNG。运行日志为根目录 `logs/YYYY-MM-DD.log`，日期为 UTC。

## 已完成的验证证据

最终完整运行为 **51/51 测试通过，0 失败、0 未完成**：TestApp 11、TestArm 14、TestIO 12、TestMobile 13、TestDisplay 1。TestResult 记录的执行时长合计 **93.928 s**，不含 MATLAB 启动及后续可见窗口走查。MATLAB 批处理退出码为 0。

| 验证层级 | 证据与检查范围 |
| --- | --- |
| MATLAB 自动化 | `results/validation/test_results.csv`、`test_results.mat`、`tests.log`；覆盖 FK/J 数值校验、端点与解析峰值、时间缩放、碰撞/非法输入、A* 代价与坐标、安全距离/圆角回退、MAT/CSV、GUI 状态和资源释放 |
| 可复现实验 | `results/examples/arm`、`armScaled`、`mobile` 均已有真实 MAT、轨迹 CSV、摘要 CSV；`experiments/example_project.mat` 为可重载配置 |
| 可见界面 | `validate_ui` 已使用 MATLAB UITest 实际按下规划、优化和播放按钮；已生成 `results/validation/screenshots/01_...png` 至 `10_...png` 共 10 张，覆盖 `1280×800` 与 `1920×1080` |
| 图片复核 | 已修复隐藏基线曲线残留、地图障碍表高度不足、进度刻度密集；重新导出后复核模型、规划、仿真、分析与历史页。最终 1920 分析页四图边界正常、无跨机器人残留曲线；1280 参数区通过滚动访问，表格和回放控件可用 |

`test_results.csv` 和 `test_results.mat` 是最终 51 项结果；`tests.log` 追加保留了早期失败及修复过程，不能将早期失败摘要当作最终状态。可见窗口走查由 MATLAB UITest 实际触发规划、优化和播放按钮，未用静态界面效果图代替软件运行。测试专属临时文件已由测试清理，保留实验结果、CSV、日志和截图作为交付证据。

已用失败测试复现并修复的缺陷包括：模型缓存声明遗漏、A* 路径代价重复单位换算、地图非法文本导致界面和请求不一致、失败记录破坏当前项目、关闭窗口后访问已删除对象、jerk 和计数单位缺失、跨机器人隐藏曲线残留、碰撞配对文本类型导致诊断框异常。展示层提供中文指标、原始/当前对照及 `NaN` 的“无可用值”说明，机器导出保留数值与字段名。

## 可复现实验数值

以下取自 `results/examples` 中真实导出的摘要 CSV，使用默认项目输入，未加入随机噪声或展示用假数据。

| 指标 | 原始 | 处理后 |
| --- | ---: | ---: |
| UR5 运动时间 (s) | 3 | 1.3160740143 |
| UR5 关节路径长度 (rad) | 1.1575836903 | 1.1575836903 |
| TCP 路径长度 (m) | 0.5189062397 | 0.5189062397 |
| 最大关节速度 (rad/s) | 0.375 | 0.8548151455 |
| 最大关节加速度 (rad/s²) | 0.3849001795 | 1.999999996 |
| Jerk 平方积分 (rad²/s⁵) | 3.9703703704 | 244.3631552837 |
| 移动路径长度 (m) | 10.2 | 7.8122494508 |
| 移动参考回放时间 (s) | 34 | 26.0408315025 |
| 移动最小净空保守下界 (m) | 0.1792893219 | 0.0629643345 |

机械臂默认采样碰撞检查为 31 个配置、实际最大关节步长 0.02 rad；检查通过。时间缩短伴随 Jerk 增大，未宣称所有指标同时改善。移动安全距离为 0.05 m，最终净空保守下界大于该值；默认地图的 Chaikin 候选未通过复检，诚实回退到安全直连简化路径（4 个点）。

## 能力边界与后续阶段

- 机械臂碰撞是报告所列关节角分辨率下的采样检查，默认最大步长 `0.02 rad`，不是连续碰撞证明。速度/加速度上限为可编辑仿真设定，非厂家额定值；固定五次曲线缩短时间可能增加 jerk，不解决碰撞或全局路径最优问题。
- 移动安全检查计入圆形足迹、安全距离、地图边界和占用格外接圆；保守膨胀可能拒绝窄通道，不会自动缩小安全距离。圆角失败回退到已验证路径；最终轨迹仍为折线。
- 移动回放时间是路径长度/参考速度，不包含差速动力学、加减速或跟踪控制；三维界面是平面路径的空间展示。没有真实机器人或硬件验证。
- 原阶段未实现 IK、其他路径/轨迹算法、通用约束优化、批量统计和 URDF 模型库。这些功能未在本次追加实施；独立 EXE 按用户后续作业打包要求提前交付，见以下补充记录。

## 2026 年 10 月 25 日作业打包补充

用户明确只打包现有第一阶段，完成后写说明文档并停止。本轮没有增加规划算法。新增 `RobotTrajectoryLab.m` 独立入口、`build_release.m` 编译脚本、`package_release.ps1` 归档脚本、UR5 模型资源及可写数据目录选择；首页同步修正打包状态。

- 完整回归重新运行：**51/51 通过，0 失败，0 未完成**，TestResult 时长合计 **108.704 s**。原日期的 93.928 s 属于上一次运行。
- 实际编译生成 `RobotTrajectoryLab.exe` 和 `RobotTrajectoryLab_Setup.exe`，使用本机 MATLAB Compiler R2025a；无未解析符号或排除文件。
- EXE 直接启动曾报告缺少 MATLAB Runtime 25.1。随后仅为验证进程设置现有 MATLAB 的运行库路径，未修改系统 PATH。自检记录 `isDeployed=true`，实际执行 UR5、解析时间缩放、移动 A*、项目 MAT 重载、结果 MAT/CSV 导出和三维回放。
- 安装器使用在线 Runtime 分发模式，不内置离线运行库；未在无 MATLAB 的全新电脑上验收安装流程。这一项不计为通过，也没有用源码测试替代。
- 打包首次调用安装器 API 时因缺少 Results 参数失败，已根据本机 R2025a 文档修正为 `compiler.package.installer(results,'Options',opts)` 并成功重新生成安装器。部署截图曾抓到未刷新完的页面，增加等待后重新采集和复核。启动脚本对负退出码漏判已先复现，再修正。
- 交付源码 ZIP、Windows 运行 ZIP、在线安装器、作业说明 PDF 与可编辑 Markdown，以及 SHA256 清单。仅打包指定示例与验证证据，不收集其他历史实验。
- 重复归档校验复现了清单 ASCII 编码丢失中文文件名、总包纳入自身校验的问题；改为 UTF-8 清单并限定实际交付文件后，重新逐项校验归档和 SHA256。

## 1.0.1 启动修复与最终安装版

用户报告打开程序只有黑色终端，随后确认以 MATLAB 开发要求为先，可接受运行库。旧 EXE 回归检查实际读出 Windows Subsystem=3，断言失败；改用 standaloneWindowsApplication 后，MATLAB 核心与 Windows 启动器均为 GUI Subsystem=2。增加启动画面、startup_report.json、可见失败提示，并验证与正常初始化共用流程的 --startup-check。

新安装 Runtime 后，旧会话未继承新的 DLL 路径，首次启动验证退出 -1。显式指定独立 Runtime 后验证通过；再加入只负责定位运行库的 Windows 启动器，在清除预设 Runtime 路径的环境中验证通过。启动器不修改系统 PATH，不替代 MATLAB 核心界面与算法。首次 C# 编译曾因 Windows 路径分隔符传参失败，改用原生反斜杠路径后成功。

- 完整 MATLAB 回归：51/51 通过，0 失败、0 未完成，合计 122.012 s。
- 独立 Runtime 冷启动检查：65.756 s，总流程正常退出，窗口可见、计时器已释放。
- 独立 Runtime 两领域 GUI 自检：47.329 s，实际计算、回放、MAT/CSV 和计时器释放通过。
- 最终启动器生命周期验证：47.43 s，在无预设 Runtime 路径的环境中，自动查找运行库、隐藏加载窗口、等待 MATLAB 子进程退出，均通过。
- 运行库路径确认为 C:/Program Files/MATLAB/MATLAB Runtime/R2025a，未使用 E:/MATLAB1 的开发环境 DLL。
- Runtime 依赖审计：6 组全部必需，可选项为空；已显式 OptionalDependencies=none，不能据此声称安装占用大幅缩小。
- 最终安装器打包启动器、MATLAB 核心和两份文档，快捷方式指向图形启动器。新建用户/全新电脑的安装流程未另行执行；安装器生成成功不等同于该项验收。
- 文档共 7 页，已渲染逐页复核；最终交付不压缩，只含安装程序、使用说明、技术要点与创新点文档。
# 独立卸载入口补充验收（2026-10-25）

新增 `packaging/WindowsUninstaller.cs` 和 `packaging/build_uninstaller.ps1`，生成 `RobotTrajectoryLab_Uninstall.exe`，与安装器和两份 PDF 放在同一未压缩交付目录。使用 Windows 自带 .NET Framework 编译，Windows GUI Subsystem=2，不需要 MATLAB Runtime 即可打开。

本机只读发现确认 RobotTrajectoryLab 1.0.1 安装于 `E:\tool`，官方卸载器为其 `uninstall\bin\win64\Uninstall_Application.exe`；MATLAB Runtime R2025a 官方卸载器亦存在。路径来自注册表，不固定开发机路径。命令解析覆盖带引号、空格、参数及非法命令；界面已渲染复核。证据为 `results/deployment/v101/uninstaller_validation.txt` 与 `uninstaller_window.png`。未启动任何实际卸载，不能声称已验证卸载完成；运行库须由用户单独选择，入口不会删除实验数据。
