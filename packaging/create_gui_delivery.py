"""Package only the validated GUI application, runtime installer, and manual."""
from pathlib import Path
from xml.sax.saxutils import escape
import csv, hashlib, json, shutil
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image, PageBreak, KeepTogether
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.enums import TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader

root=Path(__file__).resolve().parents[1]
folder=root/'build'/'installer_stage'
(folder/'app').mkdir(parents=True,exist_ok=True)
shutil.copy2(root/'build/launcher/RobotTrajectoryLab.exe',folder/'RobotTrajectoryLab.exe')
shutil.copy2(root/'build/standalone/RobotTrajectoryLab.exe',folder/'app/RobotTrajectoryLab.exe')
startup=json.loads((root/'build/launcher_startup/startup_report.json').read_text('utf-8'))
gui=json.loads((root/'build/installed_runtime_gui/selftest_report.json').read_text('utf-8'))
assert startup['success'] and startup['windowVisible'] and startup['guiAndTimerReleased']
assert gui['success'] and gui['isDeployed'] and gui['guiAndTimerReleased']
assert 'MATLAB Runtime' in gui['runtimeRoot']
with (root/'results/validation/test_results.csv').open(encoding='utf-8-sig') as f:
    tests=list(csv.DictReader(f))
assert len(tests)==51 and all(x['Passed']=='1' and x['Failed']=='0' and x['Incomplete']=='0' for x in tests)
duration=sum(float(x['Duration_s']) for x in tests)
(folder/'开始使用.txt').write_text('''RobotTrajectoryLab 1.0.1 图形程序修正版

1. 完整解压整个程序包，双击根目录的 RobotTrajectoryLab.exe。
2. 启动时显示进度窗口，随后进入 MATLAB 机器人运动规划界面。
   首次启动需初始化运行库，可能需要一分钟左右。请等待界面出现。
3. 保留 app 文件夹，它包含 MATLAB 核心程序，不要只复制根目录 EXE。
4. 需要 MATLAB Runtime R2025a。已装好时不用重复安装。
   未安装时运行“安装器”中的 MATLAB_Runtime_Setup.exe，联网安装所需运行库。
5. 项目、结果与日志写入同目录 Data 文件夹。请把整个程序包放在可写位置。
   详细操作、算法、截图和验证说明见“使用说明.pdf”。

本版采用 MATLAB 开发核心界面与算法。小型 Windows 启动器仅负责
定位运行库和显示加载进度，不改写算法，也不修改系统 PATH。
本版仍需要 MATLAB Runtime，不是免运行库版本。
启动失败会显示错误提示；诊断文件位于 Data/startup_report.json。

修复：旧版控制台窗口、刚安装 Runtime 后旧会话找不到运行库的问题。
验证：51 项 MATLAB 测试通过；在独立 Runtime 下通过冷启动、三维回放、
MAT/CSV、计时器释放及无预设 Runtime 路径的启动器验证。
''',encoding='utf-8-sig')

pdfmetrics.registerFont(TTFont('Yahei','C:/Windows/Fonts/msyh.ttc',subfontIndex=0))
pdfmetrics.registerFont(TTFont('YaheiBold','C:/Windows/Fonts/msyhbd.ttc',subfontIndex=0))
pdfmetrics.registerFontFamily('Yahei',normal='Yahei',bold='YaheiBold')
body=ParagraphStyle('Body',fontName='Yahei',fontSize=10.2,leading=16,spaceAfter=7,wordWrap='CJK')
title=ParagraphStyle('Title',parent=body,fontName='YaheiBold',fontSize=20,leading=29,spaceAfter=12)
heading=ParagraphStyle('Heading',parent=body,fontName='YaheiBold',fontSize=14,leading=21,spaceBefore=10,spaceAfter=8)
small=ParagraphStyle('Small',parent=body,fontSize=8.8,leading=13,spaceAfter=5)
cell=ParagraphStyle('Cell',parent=small,fontSize=9.2,leading=14,spaceAfter=0)
caption=ParagraphStyle('Caption',parent=small,alignment=TA_CENTER,spaceBefore=5,spaceAfter=8)
width=174*mm
story=[]
def p(text,style=body): story.append(Paragraph(text,style))
def h(text): p(text,heading)
def table(rows,widths):
    t=Table([[Paragraph(escape(str(x)),cell) for x in row] for row in rows],colWidths=widths,repeatRows=1,hAlign='LEFT')
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#e7edf3')),
        ('GRID',(0,0),(-1,-1),.5,colors.HexColor('#d9d9d9')),('VALIGN',(0,0),(-1,-1),'MIDDLE'),
        ('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),
        ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6)]))
    story.extend([t,Spacer(1,9)])
def figure(name,text):
    img=Image(str(root/'build/installed_runtime_gui'/name))
    ratio=img.imageHeight/img.imageWidth
    img.drawWidth=width; img.drawHeight=width*ratio
    assert img.drawWidth<=width+1e-8
    story.append(KeepTogether([img,Paragraph(text,caption)]))
def page(): story.append(PageBreak())

p('RobotTrajectoryLab<br/>机器人运动规划程序使用说明',title)
p('Astrspire　｜　版本 1.0.1　｜　2026 年 10 月 25 日',small)
p('本程序采用 MATLAB 实现 UR5 六自由度机械臂与移动机器人两条仿真流程。本版修复启动时出现黑色终端的问题，增加自动定位运行库的 Windows 启动器，核心界面与算法仍由 MATLAB 开发。')
h('一 启动软件')
p('<b>安装：</b>运行交付文件夹中的 RobotTrajectoryLab_Setup.exe，按向导安装应用。安装器会检查 MATLAB Runtime R2025a，缺少时联网安装所需组件。已经安装对应运行库时可以复用。本版不是免运行库软件。')
p('<b>打开：</b>安装完成后，从开始菜单或安装目录启动 RobotTrajectoryLab。程序先显示加载进度，再打开机器人规划工作台。核心程序位于 app 子目录，不要单独移动启动器。')
p('<b>启动等待：</b>首次初始化可能需要一分钟左右。启动器自动查找 Runtime，不修改系统 PATH。失败时显示提示，诊断文件位于用户主目录的 RobotTrajectoryLab_Data/startup_report.json。')
h('二 页面功能')
table([['页面','主要功能'],['工作台','新建、打开和保存项目，查看记录'],['模型与环境','UR5 预览、关节约束、地图和障碍编辑'],
    ['运动规划','输入起终状态和参数，执行规划及约束检查'],['三维仿真','播放、暂停、重置、进度拖动与倍速'],
    ['优化与分析','时间缩放、安全路径处理、指标及曲线比较'],['实验记录','恢复输入、查看历史、导出 MAT 和 CSV 及 PNG']], [31*mm,143*mm])
p('程序数据保存于用户主目录的 RobotTrajectoryLab_Data 文件夹，与安装目录分开。小型启动器只负责启动和运行库定位。本软件不连接真实机器人。',small)

page();h('三 UR5 机械臂操作')
p('选择“六轴机械臂 · UR5”。模型页查看机械臂并按需添加环境箱体；运动规划页设置六关节起终位置、运动时间、采样周期，以及速度与加速度上限，执行后查看诊断。')
p('成功结果可在三维仿真页播放、暂停、拖动进度和调节倍速；分析页进行解析时间缩放，比较原始与当前轨迹。界面关节位置用度，内部统一采用米、秒、弧度。')
p('模型采用官方 universalUR5，末端为 tool0。轨迹调用 quinticpolytraj。令 τ=t/T、Δq=q1−q0，零端速度和零端加速度的五次轨迹为：')
p('<b>q(t) = q0 + Δq (10τ³ − 15τ⁴ + 6τ⁵)</b>')
p('解析峰值为 vmax=15|Δq|/(8T)、amax=10√3|Δq|/(3T²)。项目按解析峰值检查约束，在固定路径上计算满足各关节上限的同步时长，并保留原始结果。')
figure('standalone_arm.png','图 1　独立 Runtime 下的 UR5 三维回放')
p('默认速度 1 rad/s、加速度 2 rad/s² 是仿真设定，不是厂家额定值。checkCollision 检查自碰撞和环境箱体，仅跳过父子连杆。最大关节采样步长默认 0.02 rad，不能视作连续安全证明；时间缩放不会消除碰撞。',small)

page();h('四 移动机器人操作')
p('选择“移动机器人 · 栅格”，设置地图尺寸、格宽、原点、机器人半径和安全距离。默认地图 60×80 格、0.1 m/格。通过表格或地图编辑矩形障碍，点击设置起终单元格后执行规划。')
p('第一行位于地图顶部，世界坐标 Y 向上，起终点使用单元格中心。二维、三维与导出采用同一坐标约定。三维页可回放，分析页比较长度、转角和保守净空。')
p('采用 binaryOccupancyMap 与 plannerAStarGrid，固定四邻域及 Manhattan 代价和启发式，关闭启发式扰动。按圆形足迹、安全距离和半格对角线保守膨胀，单独处理地图边界。')
figure('standalone_mobile.png','图 2　独立 Runtime 下的移动机器人路径回放')
p('原始、直连简化和 Chaikin 圆角候选均逐线段复检，计入占用格外接圆。圆角默认两轮，候选不安全时保留已验证简化折线。保守膨胀可能拒绝窄通道；三维画面属于平面路径展示，参考时间不包含差速动力学、加减速和跟踪控制。',small)

page();h('五 保存与实验结果')
p('项目 MAT 保存配置，单次结果 MAT 保存输入、轨迹、约束、诊断和版本。CSV 列名带单位，PNG 保存分析图。参数变化后旧结果失效，需要重新规划。运动时间、计算耗时、后处理耗时和参考回放时间分别记录。')
table([['默认输入指标','原始','处理后'],['UR5 运动时间 s','3.000000',f"{gui['scaledDuration_s']:.6f}"],
    ['UR5 TCP 路径长度 m','0.518906','0.518906'],['最大关节速度 rad/s','0.375000','0.854815'],
    ['最大关节加速度 rad/s²','0.384900','2.000000'],['Jerk 平方积分 rad²/s⁵','3.970370','244.363155'],
    ['移动路径长度 m','10.200000',f"{gui['mobilePathLength_m']:.6f}"],['移动参考回放时间 s','34.000000','26.040832'],
    ['移动净空保守下界 m','0.179289','0.062964']], [88*mm,43*mm,43*mm])
p('时间缩短伴随 Jerk 增大，机械臂路径不变。移动示例圆角候选未通过复检，采用 4 点安全简化路径；净空下界仍大于 0.05 m 安全距离。',small)
h('六 验证与能力范围')
p(f'本版在 MATLAB R2025a 中重新运行 51 项测试，全部通过，0 失败、0 未完成，时长合计 {duration:.3f} s。已使用本机独立安装的 Runtime 验证冷启动、可见窗口、两类计算、MAT/CSV、回放和计时器释放。另在不预设 Runtime 路径的环境中验证了启动器。')
p('启动器与 MATLAB 核心程序均为 Windows 图形程序。安装器已排除可选运行依赖；构建报告所列 6 组依赖均为必需，未承诺安装后体积显著减少。全新电脑的安装流程尚未另行验收。')
p('五次轨迹与 A* 搜索使用 MATLAB 工具箱接口；时间缩放、路径简化和安全复检由项目实现。本版不包含逆运动学、通用求解器优化、批量实验或真实机器人控制。',small)

def footer(c,doc):
    c.setFont('Yahei',8);c.setFillColor(colors.HexColor('#555555'))
    c.drawString(18*mm,12*mm,'RobotTrajectoryLab 1.0.1　使用说明');c.drawRightString(192*mm,12*mm,str(doc.page))
pdf=folder/'使用说明.pdf'
SimpleDocTemplate(str(pdf),pagesize=(210*mm,297*mm),leftMargin=18*mm,rightMargin=18*mm,
    topMargin=17*mm,bottomMargin=19*mm,title='RobotTrajectoryLab 使用说明',author='Astrspire').build(story,onFirstPage=footer,onLaterPages=footer)
assert len(PdfReader(str(pdf)).pages)==4
story.clear()
p('RobotTrajectoryLab<br/>技术要点与项目创新说明',title)
p('Astrspire　｜　版本 1.0.1　｜　2026 年 10 月 25 日',small)
p('本项目围绕机器人运动规划课程作业，使用 MATLAB 建立可交互、可仿真和可保存结果的应用。技术重点是把输入校验、轨迹计算、安全检查、处理前后比较与实验记录连接成完整流程。以下区分工具箱能力和项目实现，不把已有规划理论作为原创成果。')
h('一 系统架构与开发方式')
table([['部分','职责与采用方式'],['界面与状态','程序化 uifigure、布局、回调、参数状态和历史记录，核心采用 MATLAB'],
    ['模型与运动学','官方 UR5/tool0，正运动学、雅可比和碰撞接口'],['规划与处理','五次轨迹和四邻域 A*；项目实现解析检查、时间缩放、安全简化与圆角复检'],
    ['仿真与数据','MATLAB 计时器回放、帧插值、MAT 项目与结果、CSV 和 PNG'],
    ['Windows 部署','MATLAB Compiler 生成图形程序；小型 Windows 启动器只定位 Runtime 和显示加载进度']], [33*mm,141*mm])
p('算法可脱离 GUI 调用，统一请求返回状态、输入快照、原始和最终路径、轨迹、约束、指标与诊断。内部采用米、秒、弧度；机械臂 q、qd、qdd 为 6×N，移动路径为 N×2 世界坐标。')
p('项目使用带 schemaVersion 的普通结构保存，不序列化窗口、计时器或工具箱对象。修改参数后旧结果立即失效，防止参数已变而界面继续播放旧实验。')
h('二 机械臂技术要点')
p('采用两点、零端速度和零端加速度的同步五次关节轨迹。轨迹采样由 quinticpolytraj 完成；项目按解析公式检查速度和加速度峰值，避免采样过疏而漏掉极值。')
p('<b>vmax = 15|Δq|/(8T)</b><br/><b>amax = 10√3|Δq|/(3T²)</b>')
p('固定路径最短可行时长按各关节速度、加速度约束取最大值：Treq=maxᵢ{15|Δqi|/(8vi), √[10√3|Δqi|/(3ai)]}。保留原始时长及结果，用同一条几何路径比较时序变化。')
p('碰撞检查沿关节路径独立取样，默认最大角步长 0.02 rad，覆盖自碰撞和可编辑环境箱体；只跳过官方父子连杆配对。检查报告明确分辨率与是否完成。',small)

page();h('三 移动机器人技术要点')
p('使用 binaryOccupancyMap 和 plannerAStarGrid；固定四邻域、Manhattan 代价与启发式、关闭扰动。地图尺寸、格宽和原点共享一套转换方式，起终状态取格子中心。')
p('规划图按机器人半径 r、安全距离 s 与半格对角线 h/√2 保守膨胀，同时内缩地图可用边界。完整输出线段再与原占用格独立复检，计算线段到格中心的最短距离，并计入占用格外接圆。')
p('处理顺序为原始路径检查、直连简化、Chaikin 圆角候选与复检。圆角不安全时回退到已经通过检查的简化折线，并保留失败原因。安全距离不会为得到路径而自动减小。')
h('四 课程作业中的特色与改进')
p('<b>1 解析约束与时间缩放结合。</b>用解析峰值而非仅靠离散采样判断速度、加速度上限，并在固定路径上重新选择时长，保留前后结果便于解释性能变化。')
p('<b>2 路径后处理包含安全闭环。</b>不直接接受看起来平滑的曲线，对候选逐线段复检；失败时回退到已验证路径，使优化结果与安全报告一致。')
p('<b>3 两类机器人共用完整交互流程。</b>机械臂与移动机器人共用输入、计算、仿真、分析和留档结构，既能改变参数观察结果，也能保存后恢复实验。')
p('<b>4 可追溯的结果比较。</b>保存输入快照、seed、版本、状态和真实数值，区分运动时间、计算耗时与参考回放时间。无路径、非法输入和安全验证失败分别显示。')
p('<b>5 部署过程提供可见反馈。</b>Windows 图形程序避免黑色终端；小型启动器自动定位已安装 Runtime，加载时显示进度，启动异常给出诊断位置。核心界面与算法没有改用其他语言。')
p('以上是本项目面向课程应用的工程特色，不代表提出新的 A*、五次轨迹或碰撞理论。官方模型、quinticpolytraj、plannerAStarGrid、checkCollision 等是工具箱能力；时间缩放、状态管理、路径处理和安全复检是项目代码。',small)

page();h('五 实测结果与说明')
table([['指标','原始','处理后'],['UR5 运动时间 s','3.000000','1.316074'],['TCP 路径长度 m','0.518906','0.518906'],
    ['最大关节速度 rad/s','0.375000','0.854815'],['最大关节加速度 rad/s²','0.384900','2.000000'],
    ['Jerk 平方积分 rad²/s⁵','3.970370','244.363155'],['移动路径长度 m','10.200000','7.812249'],
    ['移动参考回放时间 s','34.000000','26.040832'],['移动净空保守下界 m','0.179289','0.062964']], [88*mm,43*mm,43*mm])
p('结果来自默认输入的实际计算。时间缩放缩短运动时间，也提高了 Jerk；不声称所有指标同时改善。移动示例的圆角候选未通过安全复检，最终保留 4 点安全简化路径，净空仍大于设置的 0.05 m。')
h('六 验证证据')
p(f'在 MATLAB R2025a 中完整回归 51 项通过，0 失败、0 未完成，执行时长合计 {duration:.3f} s。测试覆盖模型、FK 独立连乘、雅可比差分、轨迹端点和解析峰值、时间缩放、碰撞、A*、坐标与安全、持久化、界面和资源释放。')
p('部署验证使用已独立安装的 MATLAB Runtime，而非开发环境 DLL。实际完成冷启动可见窗口、两条计算和回放流程、MAT/CSV、计时器释放；另在不预设 Runtime 路径的环境中验证了自动定位启动。启动器和 MATLAB 核心均检查为 Windows GUI 类型。')
h('七 能力边界')
p('机械臂采用运动学模型；碰撞是采样检查而非连续证明。时间缩放不解决碰撞或全局路径最优。移动场景是平面路径的三维展示，不包含差速动力学、加减速或跟踪控制。')
p('未实现 IK、其他规划器、通用求解器优化、批量统计和真实机器人控制。保留 MATLAB 方案意味着仍依赖 Runtime；本版无可删的可选依赖，未承诺大幅降低运行库占用。安装器已生成，全新无 MATLAB 电脑的安装流程尚未另行验收。',small)
technical=folder/'技术要点与创新点.pdf'
SimpleDocTemplate(str(technical),pagesize=(210*mm,297*mm),leftMargin=18*mm,rightMargin=18*mm,
    topMargin=17*mm,bottomMargin=19*mm,title='RobotTrajectoryLab 技术要点与创新点',author='Astrspire').build(story,onFirstPage=footer,onLaterPages=footer)
assert len(PdfReader(str(technical)).pages)==3
print('MANUAL_PAGES=4; TECHNICAL_PAGES=3; NO_ARCHIVE_CREATED')
