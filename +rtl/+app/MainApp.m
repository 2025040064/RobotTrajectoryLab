classdef MainApp < handle
    %MAINAPP 中文科研工作台。业务参数只保存在 Project 中。
    properties (SetAccess=private)
        Figure
        Controls = struct()
        Project
        Kind = 'arm'
        CurrentResult = []
        History = {}
        IsStale = true
        IsBusy = false
        PlaybackTimer
        PlaybackTime = 0
        Root
    end
    properties (Access=private)
        Pages = struct()
        Results = struct('arm',[],'mobile',[])
        Stale = struct('arm',true,'mobile',true)
        PageName = 'home'
        SimAxes
        PreviewAxes
        MapAxes
        PlanAxes
        AnalysisAxes
        SimModel
        MobileTransform
        SelectedObstacle = 0
        SelectedBox = 0
        SelectedHistory = 0
        DragStart = []
        DragRectangle = []
        PlaybackClock
        PlaybackOffset = 0
        Refreshing = false
        BusyControls = []
        BusyEnable = {}
    end
    methods
        function obj = MainApp(root,visible)
            obj.Root=root;
            obj.Project=rtl.defaultProject();
            try
                obj.buildUI(visible);
                obj.PlaybackTimer=timer('ExecutionMode','fixedSpacing', ...
                    'Period',0.05,'BusyMode','drop', ...
                    'TimerFcn',@(~,~)obj.tick(), ...
                    'ErrorFcn',@(~,event)obj.timerError(event));
                obj.syncControls();
                obj.refreshModel();
                obj.selectPage('home');
                obj.setStatus('就绪 · 请选择机器人类型，设置参数后执行规划');
            catch exception
                delete(obj);
                rethrow(exception);
            end
        end
        function delete(obj)
            if ~isempty(obj.PlaybackTimer) && isvalid(obj.PlaybackTimer)
                stop(obj.PlaybackTimer); delete(obj.PlaybackTimer);
            end
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.CloseRequestFcn=[];
                delete(obj.Figure);
            end
        end
        function selectPage(obj,name)
            names=fieldnames(obj.Pages);
            for k=1:numel(names)
                obj.Pages.(names{k}).Visible=strcmp(names{k},name);
            end
            obj.PageName=name;
            if strcmp(name,'simulation'), obj.refreshSimulation(); end
            if strcmp(name,'analysis'), obj.refreshAnalysis(); end
        end
        function setKind(obj,kind)
            validatestring(kind,{'arm','mobile'});
            obj.pause(); obj.Kind=kind;
            obj.CurrentResult=obj.Results.(kind);
            obj.IsStale=obj.Stale.(kind);
            obj.Controls.Kind.Value=kind;
            obj.Controls.ArmPlanning.Visible=strcmp(kind,'arm');
            obj.Controls.MobilePlanning.Visible=strcmp(kind,'mobile');
            if strcmp(kind,'arm')
                obj.Controls.ModelTabs.SelectedTab=obj.Controls.ArmTab;
            else
                obj.Controls.ModelTabs.SelectedTab=obj.Controls.MobileTab;
            end
            obj.PlaybackTime=0;
            obj.refreshResults();
            if strcmp(obj.PageName,'simulation'), obj.refreshSimulation(); end
        end
        function setRequest(obj,request)
            % 供示例、测试和项目重载共用，不绕过业务失效处理。
            validatestring(request.kind,{'arm','mobile'});
            obj.Project.(request.kind)=request;
            obj.invalidate(request.kind);
            obj.syncControls(); obj.setKind(request.kind); obj.refreshModel();
        end
        function result = runPlanning(obj)
            result=[];
            if ~isvalid(obj) || obj.IsBusy, return; end
            obj.pause(); obj.IsBusy=true;
            obj.BusyControls=findall(obj.Figure,'-property','Enable');
            obj.BusyEnable=cell(numel(obj.BusyControls),1);
            for k=1:numel(obj.BusyControls)
                obj.BusyEnable{k}=obj.BusyControls(k).Enable;
                obj.BusyControls(k).Enable='off';
            end
            cleanup=onCleanup(@()obj.endBusy());
            obj.setStatus('正在规划、检查约束与碰撞，请稍候…'); drawnow;
            if ~isvalid(obj), return; end
            result=rtl.planning.plan(obj.Project.(obj.Kind));
            obj.Results.(obj.Kind)=result; obj.CurrentResult=result;
            obj.Stale.(obj.Kind)=false; obj.IsStale=false;
            obj.History{end+1}=result; obj.SelectedHistory=numel(obj.History);
            obj.PlaybackTime=0;
            try
                rtl.io.saveResult(result,fullfile(obj.Root,'results',result.id,'result.mat'));
                rtl.io.appendLog(obj.Root,[result.id ' ' result.status ' ' result.message],'INFO');
            catch exception
                result.diagnostics{end+1}=['Auto-save failed: ' exception.message];
                obj.CurrentResult=result; obj.Results.(obj.Kind)=result;
                obj.History{end}=result;
            end
            obj.refreshHistory(); obj.refreshResults();
            if strcmp(obj.PageName,'simulation'), obj.refreshSimulation(); end
            obj.setStatus([obj.statusName(result.status) ' · ' result.message]);
            clear cleanup
        end
        function result = applyOptimization(obj)
            if strcmp(obj.Kind,'arm')
                obj.Project.arm.options.scaleTime=true;
            end
            obj.invalidate(obj.Kind);
            result=obj.runPlanning(); obj.selectPage('analysis');
        end
        function saveProject(obj,path)
            rtl.io.saveProject(obj.Project,path);
            obj.setStatus(['项目已保存：' path]);
        end
        function openProject(obj,path)
            project=rtl.io.loadProject(path);
            obj.pause(); obj.Project=project;
            obj.Results=struct('arm',[],'mobile',[]);
            obj.Stale=struct('arm',true,'mobile',true);
            obj.CurrentResult=[]; obj.IsStale=true;
            obj.syncControls(); obj.setKind(obj.Kind); obj.refreshModel();
            obj.setStatus(['项目已加载：' path]);
        end
        function openResult(obj,path)
            obj.importResult(path);
        end
        function files = exportCurrent(obj,folder)
            if isempty(obj.CurrentResult) || obj.IsStale
                error('RobotTrajectoryLab:NoCurrentResult','No valid current result to export.');
            end
            files=rtl.io.exportResult(obj.CurrentResult,folder);
            obj.refreshAnalysis();
            exportgraphics(obj.AnalysisAxes(1),fullfile(folder,'path_or_position.png'),'Resolution',150);
            exportgraphics(obj.AnalysisAxes(2),fullfile(folder,'velocity_or_clearance.png'),'Resolution',150);
            obj.setStatus(['结果已导出：' folder]);
        end
        function play(obj)
            if obj.IsBusy || obj.IsStale || isempty(obj.CurrentResult) || ...
                    ~strcmp(obj.CurrentResult.status,'success'), return; end
            if ~isfield(obj.CurrentResult.trajectory,'t') || isempty(obj.CurrentResult.trajectory.t), return; end
            if obj.PlaybackTime>=obj.duration(), obj.PlaybackTime=0; end
            obj.selectPage('simulation');
            obj.PlaybackOffset=obj.PlaybackTime; obj.PlaybackClock=tic;
            if strcmp(obj.PlaybackTimer.Running,'off'), start(obj.PlaybackTimer); end
        end
        function pause(obj)
            if ~isempty(obj.PlaybackTimer) && isvalid(obj.PlaybackTimer)
                stop(obj.PlaybackTimer);
            end
        end
        function resetPlayback(obj)
            obj.pause(); obj.seek(0);
        end
        function seek(obj,time_s)
            obj.PlaybackTime=max(0,min(obj.duration(),time_s));
            obj.PlaybackOffset=obj.PlaybackTime; obj.PlaybackClock=tic;
            obj.drawFrame();
        end
        function loadHistory(obj,index)
            if index<1 || index>numel(obj.History), return; end
            result=obj.History{index}; obj.SelectedHistory=index;
            candidate=obj.Project;
            try
                if ~ismember(result.kind,{'arm','mobile'})
                    error('RobotTrajectoryLab:InvalidInput','Unknown robot kind in saved request.');
                end
                candidate.(result.kind)=result.request;
                rtl.io.validateProject(candidate);
            catch exception
                obj.selectPage('history');
                obj.Controls.HistoryDetails.Value=[obj.resultNotes(result); ...
                    {'此失败记录的输入不完整或无效，已保留记录，当前项目未改变。';exception.message}];
                obj.setStatus('失败记录已加载；无效输入未恢复到当前项目。');
                return;
            end
            obj.Project=candidate;
            obj.Results.(result.kind)=result; obj.Stale.(result.kind)=false;
            obj.syncControls(); obj.setKind(result.kind); obj.refreshModel();
            obj.selectPage('analysis');
        end
    end
    methods (Access=private)
        function buildUI(obj,visible)
            bg=[0.95 0.96 0.98]; navy=[0.08 0.15 0.25];
            obj.Figure=uifigure('Name','RobotTrajectoryLab · 机器人运动轨迹研究工作台', ...
                'Position',[80 60 1440 900],'Visible',visible,'Color',bg, ...
                'CloseRequestFcn',@(~,~)delete(obj));
            root=uigridlayout(obj.Figure,[3 2]); root.RowHeight={76,'1x',30};
            root.ColumnWidth={180,'1x'}; root.Padding=[0 0 0 0]; root.RowSpacing=0; root.ColumnSpacing=0;
            brand=uipanel(root,'BackgroundColor',navy,'BorderType','none');
            b=uigridlayout(brand,[2 1]); b.RowHeight={30,20}; b.BackgroundColor=navy;
            uilabel(b,'Text','RTL  /  研究工作台','FontSize',17,'FontWeight','bold','FontColor',[1 1 1]);
            uilabel(b,'Text','RobotTrajectoryLab  1.0.1','FontColor',[0.65 0.76 0.88]);
            header=uigridlayout(root,[1 4]); header.ColumnWidth={'1x',100,180,125};
            header.Padding=[24 18 24 18]; header.BackgroundColor=[1 1 1];
            uilabel(header,'Text','机器人运动轨迹规划与优化','FontSize',23,'FontWeight','bold');
            uilabel(header,'Text','当前研究对象','HorizontalAlignment','right');
            obj.Controls.Kind=uidropdown(header,'Items',{'六轴机械臂 · UR5','移动机器人 · 栅格'}, ...
                'ItemsData',{'arm','mobile'},'Value','arm','ValueChangedFcn',@(s,~)obj.setKind(s.Value));
            uilabel(header,'Text','MATLAB R2025a','FontColor',[0.32 0.43 0.56]);
            nav=uigridlayout(root,[9 1]); nav.BackgroundColor=navy;
            nav.RowHeight={42,42,42,42,42,42,'1x',32,28}; nav.Padding=[12 22 12 12];
            names={'home','model','planning','simulation','analysis','history'};
            titles={'01  工作台','02  模型与环境','03  运动规划','04  三维仿真','05  优化与分析','06  实验记录'};
            for k=1:numel(names)
                page=names{k};
                uibutton(nav,'Text',titles{k},'FontSize',14,'FontColor',[1 1 1], ...
                    'BackgroundColor',[0.14 0.23 0.35],'ButtonPushedFcn',@(~,~)obj.selectPage(page));
            end
            spacer=uilabel(nav,'Text',''); spacer.Layout.Row=7;
            uilabel(nav,'Text','纯软件 · 可复现实验','FontColor',[0.7 0.8 0.9]);
            uilabel(nav,'Text','SI 单位 / 数值验证','FontColor',[0.55 0.68 0.81]);
            content=uipanel(root,'BorderType','none','BackgroundColor',bg,'AutoResizeChildren','off');
            obj.Controls.Content=content;
            host=uigridlayout(content,[1 1]); host.Padding=[0 0 0 0];
            host.RowSpacing=0; host.ColumnSpacing=0; host.BackgroundColor=bg;
            obj.Controls.PageHost=host;
            for k=1:numel(names)
                panel=uipanel(host,'BorderType','none','BackgroundColor',bg,'Visible','off');
                panel.Layout.Row=1; panel.Layout.Column=1;
                obj.Pages.(names{k})=panel;
            end
            obj.Controls.Status=uilabel(root,'Text','初始化…','FontColor',[0.25 0.36 0.47]);
            obj.Controls.Status.Layout.Row=3; obj.Controls.Status.Layout.Column=[1 2];
            obj.buildHome(); obj.buildModels(); obj.buildPlanning();
            obj.buildSimulation(); obj.buildAnalysis(); obj.buildHistory();
        end
        function buildHome(obj)
            g=uigridlayout(obj.Pages.home,[7 1]);
            g.RowHeight={38,48,52,85,150,'1x',40}; g.Padding=[28 24 28 24];
            uilabel(g,'Text','从模型到结果，保留每一步证据','FontSize',25,'FontWeight','bold');
            uilabel(g,'Text',{'两条完整研究流程：UR5 关节轨迹与移动机器人路径规划。', ...
                '先设置模型与环境，再规划、检查、回放并保存实验。'},'FontColor',[0.35 0.43 0.53]);
            bar=uigridlayout(g,[1 4]); bar.ColumnWidth={150,150,150,'1x'}; bar.Padding=[0 4 0 4];
            uibutton(bar,'Text','新建研究项目','ButtonPushedFcn',@(~,~)obj.newProject());
            uibutton(bar,'Text','打开 MAT 项目','ButtonPushedFcn',@(~,~)obj.openDialog());
            uibutton(bar,'Text','保存项目配置','ButtonPushedFcn',@(~,~)obj.saveDialog());
            cards=uigridlayout(g,[1 3]); cards.ColumnWidth={'1x','1x','1x'};
            obj.homeCard(cards,'机械臂研究','六自由度 / 五次轨迹 / 约束检查');
            obj.homeCard(cards,'移动路径研究','栅格 A* / 安全距离 / 几何圆角');
            obj.homeCard(cards,'实验数据','输入快照 / MAT · CSV · PNG');
            info=uitextarea(g,'Editable','off','Value',{ ...
                '第一阶段：运动学仿真与几何路径研究', ...
                '机械臂：官方 UR5 模型；关节位置、速度、加速度及 TCP 路径。', ...
                '移动机器人：圆形足迹；四邻域 A*；保守膨胀与连续线段复检。', ...
                '时间缩放只优化固定五次曲线的时长；路径圆角不宣称全局最优。', ...
                '提供 MATLAB 源码与 Windows 运行包；逆运动学、差速跟踪和批量实验未实现。'});
            info.FontSize=14;
            obj.Controls.HomeHistory=uitable(g,'ColumnName',{'运行时间 UTC','对象','算法','状态'},'RowName',{});
            uibutton(g,'Text','进入运动规划  →','ButtonPushedFcn',@(~,~)obj.selectPage('planning'));
        end
        function homeCard(~,parent,title,description)
            panel=uipanel(parent,'BackgroundColor',[1 1 1]);
            g=uigridlayout(panel,[2 1]); g.RowHeight={26,'1x'};
            g.Padding=[12 8 12 8]; g.RowSpacing=2;
            uilabel(g,'Text',title,'FontWeight','bold','FontSize',17);
            uilabel(g,'Text',description,'FontColor',[0.35 0.45 0.56],'WordWrap','on');
        end
        function buildModels(obj)
            g=uigridlayout(obj.Pages.model,[2 1]); g.RowHeight={40,'1x'};
            uilabel(g,'Text','模型与环境  /  参数改变后需要重新规划','FontSize',20,'FontWeight','bold');
            tabs=uitabgroup(g); obj.Controls.ModelTabs=tabs;
            arm=uitab(tabs,'Title','六轴机械臂 · UR5'); mobile=uitab(tabs,'Title','移动机器人与地图');
            obj.Controls.ArmTab=arm; obj.Controls.MobileTab=mobile;
            tabs.SelectionChangedFcn=@(~,e)obj.modelTabChanged(e.NewValue);
            a=uigridlayout(arm,[1 2]); a.ColumnWidth={390,'1x'};
            left=uigridlayout(a,[7 1]); left.RowHeight={50,100,28,'1x',38,35,42}; left.Scrollable='on';
            uilabel(left,'Text',{'官方模型：universalUR5','末端坐标系：tool0 · 内部单位：rad / m / s'},'FontWeight','bold');
            obj.Controls.ModelInfo=uitable(left,'ColumnName',{'关节','下限 (deg)','上限 (deg)'},'RowName',{});
            uilabel(left,'Text','环境箱体：中心 XYZ、尺寸 XYZ，单位 m');
            obj.Controls.Boxes=uitable(left,'Data',zeros(0,6), ...
                'ColumnName',{'X','Y','Z','长','宽','高'},'ColumnEditable',true(1,6),'RowName',{}, ...
                'CellEditCallback',@(~,~)obj.inputsChanged('arm'), ...
                'CellSelectionCallback',@(~,e)obj.boxSelected(e));
            buttons=uigridlayout(left,[1 2]); buttons.Padding=[0 0 0 0];
            uibutton(buttons,'Text','添加箱体','ButtonPushedFcn',@(~,~)obj.addBox());
            uibutton(buttons,'Text','删除选中箱体','ButtonPushedFcn',@(~,~)obj.removeBox());
            uilabel(left,'Text','关节起终点和速度 / 加速度约束在运动规划页设置。','WordWrap','on');
            uilabel(left,'Text','仿真不连接真实机器人；碰撞采用关节路径采样检查。','WordWrap','on','FontColor',[0.42 0.47 0.55]);
            preview=uipanel(a,'Title','模型预览 · 鼠标旋转与缩放');
            obj.PreviewAxes=axes('Parent',preview,'Units','normalized','Position',[0.08 0.08 0.87 0.86]);
            m=uigridlayout(mobile,[1 2]); m.ColumnWidth={330,'1x'};
            p=uigridlayout(m,[12 1]); p.RowHeight={28,180,44,24,120,36,24,30,36,28,28,38};
            p.Scrollable='on'; p.RowSpacing=6; p.Padding=[8 8 8 8];
            uilabel(p,'Text','地图与圆形机器人参数','FontSize',16,'FontWeight','bold');
            obj.Controls.MapSettings=uitable(p,'ColumnName',{'参数','数值'},'ColumnEditable',[false true], ...
                'RowName',{},'CellEditCallback',@(~,~)obj.inputsChanged('mobile'));
            uilabel(p,'Text',{'障碍矩形：[行, 列, 高度格数, 宽度格数]', ...
                '修改行列可移动；也可在地图选择并拖动。'},'WordWrap','on');
            uilabel(p,'Text','矩形障碍列表');
            obj.Controls.Obstacles=uitable(p,'ColumnName',{'行','列','高度','宽度'}, ...
                'ColumnEditable',true(1,4),'RowName',{}, ...
                'CellEditCallback',@(~,~)obj.inputsChanged('mobile'), ...
                'CellSelectionCallback',@(~,e)obj.obstacleSelected(e));
            buttons=uigridlayout(p,[1 2]); buttons.Padding=[0 0 0 0];
            uibutton(buttons,'Text','添加障碍','ButtonPushedFcn',@(~,~)obj.addObstacle());
            uibutton(buttons,'Text','删除选中障碍','ButtonPushedFcn',@(~,~)obj.removeObstacle());
            uilabel(p,'Text','地图点击操作');
            obj.Controls.MapMode=uidropdown(p,'Items',{'选择并拖动障碍','设置起点','设置终点'});
            uibutton(p,'Text','刷新地图与起终点','ButtonPushedFcn',@(~,~)obj.inputsChanged('mobile'));
            uilabel(p,'Text','绿色：起点   红色：终点','FontColor',[0.15 0.4 0.35]);
            uilabel(p,'Text','灰色膨胀区域为保守安全限制','FontColor',[0.4 0.46 0.54]);
            uilabel(p,'Text','起终点使用栅格中心；地图外视为障碍。','WordWrap','on');
            obj.MapAxes=uiaxes(m); obj.MapAxes.ButtonDownFcn=@(~,~)obj.mapClicked();
        end
        function buildPlanning(obj)
            g=uigridlayout(obj.Pages.planning,[3 1]); g.RowHeight={40,'1x',48};
            uilabel(g,'Text','运动规划  /  设置条件、生成结果、检查可行性','FontSize',20,'FontWeight','bold');
            body=uigridlayout(g,[1 2]); body.ColumnWidth={450,'1x'};
            holder=uipanel(body,'BorderType','none','AutoResizeChildren','off');
            stack=uigridlayout(holder,[1 1]); stack.Padding=[0 0 0 0];
            arm=uipanel(stack,'BorderType','none');
            mobile=uipanel(stack,'BorderType','none','Visible','off');
            arm.Layout.Row=1; arm.Layout.Column=1; mobile.Layout.Row=1; mobile.Layout.Column=1;
            obj.Controls.ArmPlanning=arm; obj.Controls.MobilePlanning=mobile;
            a=uigridlayout(arm,[8 1]); a.RowHeight={44,220,30,30,30,50,40,44}; a.Scrollable='on';
            uilabel(a,'Text',{'关节空间 · 同步五次多项式','起终速度与加速度均为零'},'FontSize',15,'FontWeight','bold');
            obj.Controls.Joints=uitable(a,'ColumnName',{'关节','起点 deg','终点 deg','v rad/s','a rad/s²'}, ...
                'ColumnEditable',[false true true true true],'RowName',{}, ...
                'CellEditCallback',@(~,~)obj.inputsChanged('arm'));
            obj.Controls.Duration=obj.numberRow(a,'运动时间 (s)',3,@(~,~)obj.inputsChanged('arm'));
            obj.Controls.Sample=obj.numberRow(a,'最大采样周期 (s)',0.02,@(~,~)obj.inputsChanged('arm'));
            obj.Controls.CollisionStep=obj.numberRow(a,'碰撞最大关节步长 (rad)',0.02,@(~,~)obj.inputsChanged('arm'));
            uilabel(a,'Text','速度与加速度为仿真设定值，可按实验需要编辑。超限结果不会标记为可行。','WordWrap','on');
            obj.Controls.Scale=uilabel(a,'Text','当前：使用输入运动时间','WordWrap','on');
            uilabel(a,'Text','时间缩放在“优化与分析”页执行，原始结果始终保留。','WordWrap','on');
            p=uigridlayout(mobile,[10 1]); p.RowHeight={44,32,32,32,32,32,32,32,65,'1x'}; p.Scrollable='on';
            uilabel(p,'Text','A* · 四邻域 · Manhattan','FontSize',16,'FontWeight','bold');
            obj.Controls.StartRow=obj.numberRow(p,'起点行',50,@(~,~)obj.inputsChanged('mobile'));
            obj.Controls.StartCol=obj.numberRow(p,'起点列',8,@(~,~)obj.inputsChanged('mobile'));
            obj.Controls.GoalRow=obj.numberRow(p,'终点行',10,@(~,~)obj.inputsChanged('mobile'));
            obj.Controls.GoalCol=obj.numberRow(p,'终点列',70,@(~,~)obj.inputsChanged('mobile'));
            obj.Controls.Smoothing=obj.numberRow(p,'圆角迭代次数 (0–4)',2,@(~,~)obj.inputsChanged('mobile'));
            obj.Controls.Speed=obj.numberRow(p,'回放参考速度 (m/s)',0.3,@(~,~)obj.inputsChanged('mobile'));
            obj.Controls.Seed=obj.numberRow(p,'记录随机种子 (A* 为确定性)',0,@(~,~)obj.inputsChanged('mobile'));
            uilabel(p,'Text','原始、简化与圆角路径逐段复检。保守膨胀可能阻塞窄通道；不会自动减小安全距离。','WordWrap','on');
            uilabel(p,'Text','回放时间由路径长度和参考速度得到，不代表动力学执行时间。','WordWrap','on');
            right=uigridlayout(body,[3 1]); right.RowHeight={40,'1x',105};
            obj.Controls.ResultSummary=uilabel(right,'Text','尚无运行结果','FontWeight','bold','WordWrap','on');
            obj.PlanAxes=uiaxes(right); title(obj.PlanAxes,'规划结果'); grid(obj.PlanAxes,'on');
            obj.Controls.PlanningNotes=uitextarea(right,'Editable','off','Value',{'尚未执行规划。'});
            buttons=uigridlayout(g,[1 4]); buttons.ColumnWidth={170,170,170,'1x'};
            obj.Controls.Run=uibutton(buttons,'Text','执行规划与检查','FontWeight','bold', ...
                'BackgroundColor',[0.16 0.4 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)obj.guard(@()obj.runPlanning()));
            uibutton(buttons,'Text','查看三维仿真','ButtonPushedFcn',@(~,~)obj.selectPage('simulation'));
            uibutton(buttons,'Text','查看指标与曲线','ButtonPushedFcn',@(~,~)obj.selectPage('analysis'));
        end
        function field=numberRow(~,parent,text,value,callback)
            g=uigridlayout(parent,[1 2]); g.ColumnWidth={'1x',115}; g.Padding=[0 0 0 0];
            uilabel(g,'Text',text); field=uieditfield(g,'numeric','Value',value,'ValueChangedFcn',callback);
        end
        function buildSimulation(obj)
            g=uigridlayout(obj.Pages.simulation,[3 1]); g.RowHeight={42,'1x',80};
            obj.Controls.SimTitle=uilabel(g,'Text','三维运动学仿真','FontSize',20,'FontWeight','bold');
            panel=uipanel(g,'BorderType','none');
            obj.SimAxes=axes('Parent',panel,'Units','normalized','Position',[0.08 0.15 0.84 0.78]);
            bar=uigridlayout(g,[2 6]); bar.RowHeight={40,24};
            bar.ColumnWidth={95,95,95,100,'1x',130};
            obj.Controls.Play=uibutton(bar,'Text','▶ 播放','ButtonPushedFcn',@(~,~)obj.play());
            uibutton(bar,'Text','Ⅱ 暂停','ButtonPushedFcn',@(~,~)obj.pause());
            uibutton(bar,'Text','↺ 重置','ButtonPushedFcn',@(~,~)obj.resetPlayback());
            obj.Controls.Rate=uidropdown(bar,'Items',{'0.25×','0.5×','1×','2×','4×'}, ...
                'ItemsData',[0.25 0.5 1 2 4],'Value',1, ...
                'ValueChangedFcn',@(~,~)obj.seek(obj.PlaybackTime));
            obj.Controls.Progress=uislider(bar,'Limits',[0 1],'Value',0, ...
                'MajorTicks',[0 0.25 0.5 0.75 1], ...
                'MajorTickLabels',{'0%','25%','50%','75%','100%'},'MinorTicks',[], ...
                'ValueChangedFcn',@(s,~)obj.seek(s.Value*obj.duration()));
            obj.Controls.Time=uilabel(bar,'Text','0.00 / 0.00 s','HorizontalAlignment','right');
            note=uilabel(bar,'Text','播放倍速只改变显示；轨迹数据与约束报告不变。','FontColor',[0.4 0.46 0.54]);
            note.Layout.Row=2; note.Layout.Column=[1 6];
        end
        function buildAnalysis(obj)
            g=uigridlayout(obj.Pages.analysis,[3 1]); g.RowHeight={42,'1x',44};
            uilabel(g,'Text','优化与分析  /  原始结果和处理结果对照','FontSize',20,'FontWeight','bold');
            body=uigridlayout(g,[1 2]); body.ColumnWidth={360,'1x'};
            left=uigridlayout(body,[4 1]); left.RowHeight={78,'1x',28,125};
            uilabel(left,'Text','机械臂采用固定五次曲线解析时间缩放；移动路径采用安全简化与圆角。两者均不宣称全局最优。','WordWrap','on');
            obj.Controls.Metrics=uitable(left,'ColumnName',{'指标','原始','当前','单位'}, ...
                'ColumnWidth',{135,60,60,65},'RowName',{});
            uilabel(left,'Text','约束与诊断');
            obj.Controls.Diagnostics=uitextarea(left,'Editable','off','Value',{'尚无结果。'});
            plots=uigridlayout(body,[2 2]);
            obj.AnalysisAxes=gobjects(1,4);
            for k=1:4, obj.AnalysisAxes(k)=uiaxes(plots); grid(obj.AnalysisAxes(k),'on'); end
            obj.Controls.AnalysisAxes=obj.AnalysisAxes;
            bar=uigridlayout(g,[1 3]); bar.ColumnWidth={220,180,'1x'};
            obj.Controls.Optimize=uibutton(bar,'Text','执行优化并重新检查', ...
                'ButtonPushedFcn',@(~,~)obj.guard(@()obj.applyOptimization()));
            uibutton(bar,'Text','导出 MAT / CSV / PNG','ButtonPushedFcn',@(~,~)obj.exportDialog());
        end
        function buildHistory(obj)
            g=uigridlayout(obj.Pages.history,[4 1]); g.RowHeight={42,45,'1x',140};
            uilabel(g,'Text','实验记录  /  每次运行保留输入快照','FontSize',20,'FontWeight','bold');
            bar=uigridlayout(g,[1 4]); bar.ColumnWidth={150,150,160,'1x'};
            uibutton(bar,'Text','重载选中实验','ButtonPushedFcn',@(~,~)obj.loadHistory(obj.SelectedHistory));
            uibutton(bar,'Text','打开结果 MAT','ButtonPushedFcn',@(~,~)obj.resultDialog());
            uibutton(bar,'Text','导出当前结果','ButtonPushedFcn',@(~,~)obj.exportDialog());
            obj.Controls.History=uitable(g,'ColumnName',{'运行时间 UTC','对象','算法','状态','运行标识'}, ...
                'RowName',{},'CellSelectionCallback',@(~,e)obj.historySelected(e));
            obj.Controls.HistoryDetails=uitextarea(g,'Editable','off','Value', ...
                {'运行后自动保存到 results/<运行标识>/result.mat。','载入实验会恢复当时参数，并显示其原始结果。'});
        end
        function syncControls(obj)
            obj.Refreshing=true; cleanup=onCleanup(@()obj.finishRefresh());
            a=obj.Project.arm; m=obj.Project.mobile;
            obj.Controls.Joints.Data=[(1:6)',rad2deg(a.start(:)),rad2deg(a.goal(:)), ...
                a.options.velocityLimits(:),a.options.accelerationLimits(:)];
            obj.Controls.Duration.Value=a.options.duration_s;
            obj.Controls.Sample.Value=a.options.samplePeriod_s;
            obj.Controls.CollisionStep.Value=a.options.collisionStep_rad;
            obj.Controls.Boxes.Data=a.options.boxes;
            obj.Controls.StartRow.Value=m.start(1); obj.Controls.StartCol.Value=m.start(2);
            obj.Controls.GoalRow.Value=m.goal(1); obj.Controls.GoalCol.Value=m.goal(2);
            obj.Controls.Smoothing.Value=m.options.smoothIterations;
            obj.Controls.Speed.Value=m.options.referenceSpeed_m_s; obj.Controls.Seed.Value=m.seed;
            names={'地图行数';'地图列数';'格宽 (m)';'原点 X (m)';'原点 Y (m)';'机器人半径 (m)';'安全距离 (m)'};
            values=[m.map.rows;m.map.cols;m.map.cellSize_m;m.map.originXY_m(:); ...
                m.options.robotRadius_m;m.options.safetyMargin_m];
            obj.Controls.MapSettings.Data=[names,num2cell(values)];
            obj.Controls.Obstacles.Data=m.map.rectangles;
            if a.options.scaleTime
                obj.Controls.Scale.Text='当前：按速度与加速度约束缩放时间';
            else
                obj.Controls.Scale.Text='当前：使用输入运动时间';
            end
            clear cleanup
        end
        function finishRefresh(obj), obj.Refreshing=false; end
        function inputsChanged(obj,kind)
            if obj.Refreshing || obj.IsBusy, return; end
            previous=obj.Project;
            try
                if strcmp(kind,'arm')
                    data=obj.Controls.Joints.Data;
                    obj.Project.arm.start=deg2rad(data(:,2)');
                    obj.Project.arm.goal=deg2rad(data(:,3)');
                    obj.Project.arm.options.velocityLimits=data(:,4)';
                    obj.Project.arm.options.accelerationLimits=data(:,5)';
                    obj.Project.arm.options.duration_s=obj.Controls.Duration.Value;
                    obj.Project.arm.options.samplePeriod_s=obj.Controls.Sample.Value;
                    obj.Project.arm.options.collisionStep_rad=obj.Controls.CollisionStep.Value;
                    obj.Project.arm.options.boxes=obj.Controls.Boxes.Data;
                    obj.Project.arm.options.scaleTime=false;
                    obj.Controls.Scale.Text='当前：使用输入运动时间';
                else
                    values=cell2mat(obj.Controls.MapSettings.Data(:,2));
                    obj.Project.mobile.map.rows=values(1); obj.Project.mobile.map.cols=values(2);
                    obj.Project.mobile.map.cellSize_m=values(3);
                    obj.Project.mobile.map.originXY_m=values(4:5)';
                    obj.Project.mobile.options.robotRadius_m=values(6);
                    obj.Project.mobile.options.safetyMargin_m=values(7);
                    obj.Project.mobile.map.rectangles=obj.Controls.Obstacles.Data;
                    obj.Project.mobile.start=[obj.Controls.StartRow.Value,obj.Controls.StartCol.Value];
                    obj.Project.mobile.goal=[obj.Controls.GoalRow.Value,obj.Controls.GoalCol.Value];
                    obj.Project.mobile.options.smoothIterations=obj.Controls.Smoothing.Value;
                    obj.Project.mobile.options.referenceSpeed_m_s=obj.Controls.Speed.Value;
                    obj.Project.mobile.seed=obj.Controls.Seed.Value;
                end
                rtl.io.validateProject(obj.Project);
                obj.invalidate(kind); obj.refreshModel();
                obj.setStatus('参数已改变 · 当前结果已失效，请重新规划');
            catch exception
                obj.Project=previous; obj.syncControls();
                obj.invalidate(kind);
                obj.setStatus(['输入有误，已恢复上次参数：' exception.message]);
            end
        end
        function invalidate(obj,kind)
            obj.Stale.(kind)=true;
            if strcmp(kind,obj.Kind)
                obj.pause(); obj.IsStale=true; obj.refreshResults();
            end
        end
        function refreshModel(obj)
            robot=rtl.models.loadArm();
            limits=rtl.models.armPositionLimits(robot);
            obj.Controls.ModelInfo.Data=[(1:6)',rad2deg(limits)];
            preview=copy(robot);
            cla(obj.PreviewAxes);
            show(preview,obj.Project.arm.start,'Parent',obj.PreviewAxes,'Frames','off', ...
                'PreservePlot',false,'FastUpdate',false);
            hold(obj.PreviewAxes,'on'); obj.drawBoxes(obj.PreviewAxes,obj.Project.arm.options.boxes);
            hold(obj.PreviewAxes,'off'); view(obj.PreviewAxes,135,25); grid(obj.PreviewAxes,'on');
            title(obj.PreviewAxes,'UR5 · 起始配置');
            axtoolbar(obj.PreviewAxes,{'rotate','pan','zoomin','zoomout','restoreview'});
            obj.drawMap();
        end
        function modelTabChanged(obj,tab)
            if obj.Refreshing, return; end
            if tab==obj.Controls.ArmTab, obj.setKind('arm'); else, obj.setKind('mobile'); end
        end
        function drawMap(obj)
            [map,raw]=rtl.planning.buildMap(obj.Project.mobile.map);
            ax=obj.MapAxes; cla(ax); show(map,'Parent',ax); hold(ax,'on');
            m=obj.Project.mobile; h=m.map.cellSize_m;
            % 浅蓝轮廓表示足迹+安全裕量下的保守规划区域。
            inflated=copy(map);
            inflate(inflated,m.options.robotRadius_m+m.options.safetyMargin_m+h/sqrt(2));
            mask=occupancyMatrix(inflated)&~raw;
            [rr,cc]=find(mask);
            if ~isempty(rr)
                xy=grid2world(map,[rr cc]);
                scatter(ax,xy(:,1),xy(:,2),8,[0.75 0.82 0.9],'filled','HitTest','off');
            end
            for k=1:size(m.map.rectangles,1)
                box=m.map.rectangles(k,:);
                xy=grid2world(map,box(1:2));
                color=[0.24 0.34 0.46]; if k==obj.SelectedObstacle, color=[0.1 0.5 0.9]; end
                rectangle(ax,'Position',[xy(1)-h/2,xy(2)-(box(3)-0.5)*h,box(4)*h,box(3)*h], ...
                    'EdgeColor',color,'LineWidth',2,'ButtonDownFcn',@(~,~)obj.mapClicked());
            end
            for k=1:2
                if k==1, rc=m.start; color=[0.05 0.6 0.35]; else, rc=m.goal; color=[0.9 0.25 0.25]; end
                if all(rc>=1) && rc(1)<=m.map.rows && rc(2)<=m.map.cols
                    xy=grid2world(map,rc);
                    scatter(ax,xy(1),xy(2),85,color,'filled','HitTest','off');
                end
            end
            hold(ax,'off'); axis(ax,'equal'); title(ax,'地图编辑 · 起终点位于栅格中心');
            xlabel(ax,'X (m)'); ylabel(ax,'Y (m)');
            images=findobj(ax,'Type','Image');
            for k=1:numel(images), images(k).ButtonDownFcn=@(~,~)obj.mapClicked(); end
            ax.ButtonDownFcn=@(~,~)obj.mapClicked();
        end
        function mapClicked(obj)
            if obj.IsBusy, return; end
            p=obj.MapAxes.CurrentPoint; spec=obj.Project.mobile.map;
            [map,~]=rtl.planning.buildMap(spec); xy=p(1,1:2);
            if any(xy<spec.originXY_m) || any(xy>=spec.originXY_m+[spec.cols spec.rows]*spec.cellSize_m), return; end
            rc=world2grid(map,xy); mode=obj.Controls.MapMode.Value;
            if strcmp(mode,'设置起点')
                obj.Project.mobile.start=rc;
            elseif strcmp(mode,'设置终点')
                obj.Project.mobile.goal=rc;
            else
                rectangles=spec.rectangles; obj.SelectedObstacle=0;
                for k=size(rectangles,1):-1:1
                    b=rectangles(k,:);
                    if all(rc>=b(1:2)) && all(rc<b(1:2)+b(3:4))
                        obj.SelectedObstacle=k; obj.DragStart=rc; obj.DragRectangle=b; break;
                    end
                end
                if obj.SelectedObstacle>0
                    obj.Figure.WindowButtonMotionFcn=@(~,~)obj.mapDrag();
                    obj.Figure.WindowButtonUpFcn=@(~,~)obj.endDrag();
                end
            end
            obj.syncControls(); obj.invalidate('mobile'); obj.drawMap();
        end
        function mapDrag(obj)
            if isempty(obj.DragStart) || obj.SelectedObstacle<1, return; end
            [map,~]=rtl.planning.buildMap(obj.Project.mobile.map);
            p=obj.MapAxes.CurrentPoint;
            xy=max([map.XWorldLimits(1),map.YWorldLimits(1)], ...
                min([map.XWorldLimits(2),map.YWorldLimits(2)]-1e-9,p(1,1:2)));
            rc=world2grid(map,xy);
            b=obj.DragRectangle; next=b(1:2)+rc-obj.DragStart;
            limit=[obj.Project.mobile.map.rows,obj.Project.mobile.map.cols]-b(3:4)+1;
            b(1:2)=max([1 1],min(limit,next));
            obj.Project.mobile.map.rectangles(obj.SelectedObstacle,:)=b;
            obj.syncControls(); obj.invalidate('mobile'); obj.drawMap();
        end
        function endDrag(obj)
            obj.DragStart=[]; obj.Figure.WindowButtonMotionFcn=[]; obj.Figure.WindowButtonUpFcn=[];
        end
        function addObstacle(obj)
            m=obj.Project.mobile.map;
            obj.Project.mobile.map.rectangles(end+1,:)=[3 3 min(5,m.rows-2) min(5,m.cols-2)];
            obj.SelectedObstacle=size(obj.Project.mobile.map.rectangles,1);
            obj.syncControls(); obj.invalidate('mobile'); obj.guard(@()obj.drawMap());
        end
        function removeObstacle(obj)
            n=size(obj.Project.mobile.map.rectangles,1); if n==0, return; end
            index=obj.SelectedObstacle; if index<1||index>n, index=n; end
            obj.Project.mobile.map.rectangles(index,:)=[]; obj.SelectedObstacle=0;
            obj.syncControls(); obj.invalidate('mobile'); obj.guard(@()obj.drawMap());
        end
        function obstacleSelected(obj,event)
            if ~isempty(event.Indices), obj.SelectedObstacle=event.Indices(1); obj.guard(@()obj.drawMap()); end
        end
        function addBox(obj)
            obj.Project.arm.options.boxes(end+1,:)=[0.5 -0.4 0.3 0.15 0.15 0.4];
            obj.syncControls(); obj.invalidate('arm'); obj.guard(@()obj.refreshModel());
        end
        function removeBox(obj)
            n=size(obj.Project.arm.options.boxes,1); if n==0, return; end
            index=obj.SelectedBox; if index<1||index>n, index=n; end
            obj.Project.arm.options.boxes(index,:)=[]; obj.SelectedBox=0;
            obj.syncControls(); obj.invalidate('arm'); obj.guard(@()obj.refreshModel());
        end
        function boxSelected(obj,event)
            if ~isempty(event.Indices), obj.SelectedBox=event.Indices(1); end
        end
        function refreshResults(obj)
            result=obj.CurrentResult; cla(obj.PlanAxes,'reset');
            if isempty(result)
                obj.Controls.ResultSummary.Text='尚无运行结果'; obj.Controls.PlanningNotes.Value={'设置参数后执行规划。'};
            else
                prefix=''; if obj.IsStale, prefix='[参数已改变，结果失效] '; end
                obj.Controls.ResultSummary.Text=[prefix obj.statusName(result.status)];
                obj.Controls.PlanningNotes.Value=obj.resultNotes(result);
                if ~isempty(result.rawPath)
                    hold(obj.PlanAxes,'on');
                    if strcmp(obj.Kind,'arm')
                        plot3(obj.PlanAxes,result.rawPath(:,1),result.rawPath(:,2),result.rawPath(:,3), ...
                            '--','Color',[0.65 0.7 0.75],'LineWidth',1.5);
                        plot3(obj.PlanAxes,result.finalPath(:,1),result.finalPath(:,2),result.finalPath(:,3), ...
                            'Color',[0.1 0.45 0.8],'LineWidth',2); view(obj.PlanAxes,3); zlabel(obj.PlanAxes,'Z (m)');
                        title(obj.PlanAxes,'TCP 几何路径');
                    else
                        [map,~]=rtl.planning.buildMap(result.request.map); show(map,'Parent',obj.PlanAxes); hold(obj.PlanAxes,'on');
                        plot(obj.PlanAxes,result.rawPath(:,1),result.rawPath(:,2),'--','Color',[0.6 0.62 0.7]);
                        plot(obj.PlanAxes,result.finalPath(:,1),result.finalPath(:,2),'-','Color',[0.05 0.5 0.8],'LineWidth',2);
                        title(obj.PlanAxes,'灰色虚线：原始 / 蓝线：最终安全折线');
                    end
                    hold(obj.PlanAxes,'off'); axis(obj.PlanAxes,'equal');
                end
            end
            xlabel(obj.PlanAxes,'X (m)'); ylabel(obj.PlanAxes,'Y (m)'); grid(obj.PlanAxes,'on');
            obj.Controls.Play.Enable=~obj.IsStale && ~isempty(result) && strcmp(result.status,'success');
            obj.refreshAnalysis();
        end
        function refreshAnalysis(obj)
            for ax=obj.AnalysisAxes
                % 删除隐藏基线，但保留网格管理的坐标轴布局。
                cla(ax); delete(findall(ax,'Type','Line')); legend(ax,'off');
                hold(ax,'off'); view(ax,2); axis(ax,'normal');
                xlim(ax,'auto'); ylim(ax,'auto'); zlim(ax,'auto');
                xlabel(ax,''); ylabel(ax,''); zlabel(ax,''); title(ax,''); grid(ax,'on');
            end
            r=obj.CurrentResult;
            if isempty(r)
                obj.Controls.Metrics.Data=table(); obj.Controls.Diagnostics.Value={'尚无结果。'}; return;
            end
            obj.Controls.Metrics.Data=rtl.app.metricDisplay(r);
            obj.Controls.Diagnostics.Value=obj.resultNotes(r);
            t=r.trajectory;
            if ~isfield(t,'t') || isempty(t.t), return; end
            a=obj.AnalysisAxes;
            if strcmp(r.kind,'arm')
                fields={'q','qd','qdd'}; titles={'关节位置 (rad)','关节速度 (rad/s)','关节加速度 (rad/s²)'};
                colors=lines(6);
                for k=1:3
                    hold(a(k),'on');
                    for j=1:6
                        if isfield(r.baseline,'trajectory')
                            base=r.baseline.trajectory;
                            plot(a(k),base.t,base.(fields{k})(j,:),'--','Color',0.5+0.5*colors(j,:),'HandleVisibility','off');
                        end
                        plot(a(k),t.t,t.(fields{k})(j,:),'Color',colors(j,:),'LineWidth',1.1,'DisplayName',sprintf('J%d',j));
                    end
                    hold(a(k),'off'); title(a(k),titles{k}); xlabel(a(k),'时间 (s)');
                end
                legend(a(1),'Location','best','NumColumns',3);
                plot3(a(4),t.tcp(1,:),t.tcp(2,:),t.tcp(3,:),'LineWidth',1.5);
                title(a(4),'TCP 空间轨迹 · 时间缩放保持路径'); view(a(4),3); axis(a(4),'equal');
                xlabel(a(4),'X (m)'); ylabel(a(4),'Y (m)'); zlabel(a(4),'Z (m)');
            else
                plot(a(1),r.rawPath(:,1),r.rawPath(:,2),'--','Color',[0.6 0.65 0.72]); hold(a(1),'on');
                plot(a(1),r.finalPath(:,1),r.finalPath(:,2),'Color',[0.1 0.45 0.8],'LineWidth',2); hold(a(1),'off');
                title(a(1),'原始与最终路径'); xlabel(a(1),'X (m)'); ylabel(a(1),'Y (m)'); axis(a(1),'equal');
                lens=[sum(vecnorm(diff(r.rawPath),2,2)),sum(vecnorm(diff(r.finalPath),2,2))];
                bar(a(2),categorical({'原始','处理后'}),lens); title(a(2),'路径长度 (m)');
                distance=[0 cumsum(vecnorm(diff(t.position,1,2),2,1))];
                plot(a(3),t.t,distance,'LineWidth',1.5); title(a(3),'参考回放路程'); xlabel(a(3),'参考时间 (s)'); ylabel(a(3),'路程 (m)');
                angles=atan2(diff(r.finalPath(:,2)),diff(r.finalPath(:,1)));
                turns=atan2(sin(diff(angles)),cos(diff(angles)));
                stem(a(4),abs(turns),'filled'); title(a(4),'最终折线转角 (rad)'); xlabel(a(4),'内部节点');
            end
        end
        function refreshSimulation(obj)
            obj.pause(); cla(obj.SimAxes); obj.MobileTransform=[];
            if obj.IsStale || isempty(obj.CurrentResult) || ~isfield(obj.CurrentResult.trajectory,'t')
                title(obj.SimAxes,'请先生成有效的当前结果'); return;
            end
            r=obj.CurrentResult; ax=obj.SimAxes;
            if strcmp(r.kind,'arm')
                obj.Controls.SimTitle.Text='UR5 三维运动学仿真 · 固定关节路径';
                obj.SimModel=copy(rtl.models.loadArm());
                show(obj.SimModel,r.trajectory.q(:,1)','Parent',ax,'Frames','off', ...
                    'PreservePlot',false,'FastUpdate',true);
                hold(ax,'on');
                plot3(ax,r.finalPath(:,1),r.finalPath(:,2),r.finalPath(:,3), ...
                    'Color',[0.1 0.5 0.8],'LineWidth',1.5);
                obj.drawBoxes(ax,r.request.options.boxes); hold(ax,'off');
                axis(ax,'equal'); view(ax,135,25);
            else
                obj.Controls.SimTitle.Text='移动机器人 · 平面路径的三维展示 / 参考速度回放';
                spec=r.request.map; h=spec.cellSize_m; origin=spec.originXY_m;
                hold(ax,'on');
                patch(ax,'XData',origin(1)+[0 spec.cols spec.cols 0]*h, ...
                    'YData',origin(2)+[0 0 spec.rows spec.rows]*h, ...
                    'ZData',[0 0 0 0],'FaceColor',[0.91 0.94 0.97],'EdgeColor',[0.7 0.78 0.85]);
                boxes=zeros(size(spec.rectangles,1),6);
                for k=1:size(boxes,1)
                    b=spec.rectangles(k,:);
                    x=origin(1)+(b(2)-1+b(4)/2)*h;
                    y=origin(2)+(spec.rows-b(1)+1-b(3)/2)*h;
                    boxes(k,:)=[x y 0.2 b(4)*h b(3)*h 0.4];
                end
                obj.drawBoxes(ax,boxes);
                plot3(ax,r.rawPath(:,1),r.rawPath(:,2),0.025*ones(size(r.rawPath,1),1), ...
                    '--','Color',[0.55 0.6 0.68]);
                plot3(ax,r.finalPath(:,1),r.finalPath(:,2),0.03*ones(size(r.finalPath,1),1), ...
                    'LineWidth',2,'Color',[0.1 0.5 0.8]);
                obj.MobileTransform=hgtransform('Parent',ax);
                [x,y,z]=cylinder(r.request.options.robotRadius_m,32);
                surf(x,y,z*0.16+0.03,'Parent',obj.MobileTransform,'FaceColor',[0.1 0.55 0.7],'EdgeColor','none');
                patch('Parent',obj.MobileTransform,'XData',x(1,:),'YData',y(1,:), ...
                    'ZData',0.19*ones(1,size(x,2)),'FaceColor',[0.15 0.68 0.8],'EdgeColor','none');
                line('Parent',obj.MobileTransform,'XData',[0 r.request.options.robotRadius_m], ...
                    'YData',[0 0],'ZData',[0.2 0.2],'LineWidth',3,'Color',[1 1 1]);
                hold(ax,'off'); axis(ax,'equal');
                xlim(ax,origin(1)+[0 spec.cols*h]); ylim(ax,origin(2)+[0 spec.rows*h]); zlim(ax,[0 1]);
                view(ax,42,55);
            end
            grid(ax,'on'); xlabel(ax,'X (m)'); ylabel(ax,'Y (m)'); zlabel(ax,'Z (m)');
            axtoolbar(ax,{'rotate','pan','zoomin','zoomout','restoreview'});
            obj.drawFrame();
        end
        function drawFrame(obj)
            if obj.IsStale || isempty(obj.CurrentResult), return; end
            r=obj.CurrentResult;
            if ~isfield(r.trajectory,'t') || isempty(r.trajectory.t), return; end
            frame=rtl.simulation.sampleFrame(r,obj.PlaybackTime);
            if strcmp(r.kind,'arm')
                if ~isempty(obj.SimModel) && isvalid(obj.SimAxes)
                    show(obj.SimModel,frame.q,'Parent',obj.SimAxes,'Frames','off', ...
                        'PreservePlot',false,'FastUpdate',true);
                end
            elseif ~isempty(obj.MobileTransform) && isgraphics(obj.MobileTransform)
                obj.MobileTransform.Matrix=makehgtform('translate',[frame.position 0])*makehgtform('zrotate',frame.yaw);
            end
            d=obj.duration();
            obj.Controls.Progress.Value=min(1,max(0,obj.PlaybackTime/max(d,eps)));
            obj.Controls.Time.Text=sprintf('%.2f / %.2f s',obj.PlaybackTime,d);
        end
        function tick(obj)
            if ~isvalid(obj) || isempty(obj.Figure) || ~isvalid(obj.Figure), return; end
            elapsed=toc(obj.PlaybackClock)*obj.Controls.Rate.Value;
            obj.PlaybackTime=min(obj.duration(),obj.PlaybackOffset+elapsed);
            obj.drawFrame();
            if obj.PlaybackTime>=obj.duration(), obj.pause(); end
        end
        function value=duration(obj)
            value=0;
            if ~isempty(obj.CurrentResult) && isfield(obj.CurrentResult.trajectory,'t') && ...
                    ~isempty(obj.CurrentResult.trajectory.t)
                value=obj.CurrentResult.trajectory.t(end);
            end
        end
        function drawBoxes(~,ax,boxes)
            rtl.simulation.drawBoxes(ax,boxes);
        end
        function timerError(obj,event)
            obj.pause(); obj.setStatus('回放异常，计时器已停止。');
            rtl.io.appendLog(obj.Root,getReport(event.Data,'basic','hyperlinks','off'),'ERROR');
        end
        function refreshHistory(obj)
            n=numel(obj.History); data=cell(n,5);
            for k=1:n
                r=obj.History{k};
                data(k,:)={r.createdAt,obj.kindName(r.kind),r.algorithm,obj.statusName(r.status),r.id};
            end
            obj.Controls.History.Data=data;
            obj.Controls.HomeHistory.Data=data(max(1,n-5):n,1:4);
            obj.Controls.HistoryDetails.Value={sprintf('本会话已记录 %d 次运行。结果自动保存到项目 results 目录。',n), ...
                '规划时间、运动时间和参考回放时间分别统计；加载结果可恢复输入。'};
        end
        function historySelected(obj,event)
            if isempty(event.Indices), return; end
            obj.SelectedHistory=event.Indices(1); r=obj.History{obj.SelectedHistory};
            json=jsonencode(r.request,'PrettyPrint',true);
            obj.Controls.HistoryDetails.Value=[obj.resultNotes(r);cellstr(splitlines(json))];
        end
        function newProject(obj)
            obj.pause(); obj.Project=rtl.defaultProject();
            obj.Results=struct('arm',[],'mobile',[]); obj.Stale=struct('arm',true,'mobile',true);
            obj.CurrentResult=[]; obj.IsStale=true;
            obj.syncControls(); obj.setKind('arm'); obj.refreshModel();
            obj.setStatus('已新建默认项目 · 现有磁盘文件与实验记录保留');
        end
        function saveDialog(obj)
            [name,folder]=uiputfile('*.mat','保存项目配置',fullfile(obj.Root,'experiments','project.mat'));
            if isequal(name,0), return; end
            obj.guard(@()obj.saveProject(fullfile(folder,name)));
        end
        function openDialog(obj)
            [name,folder]=uigetfile('*.mat','打开项目配置',fullfile(obj.Root,'experiments'));
            if isequal(name,0), return; end
            obj.guard(@()obj.openProject(fullfile(folder,name)));
        end
        function resultDialog(obj)
            [name,folder]=uigetfile('*.mat','打开实验结果',fullfile(obj.Root,'results'));
            if isequal(name,0), return; end
            obj.guard(@()obj.importResult(fullfile(folder,name)));
        end
        function importResult(obj,path)
            result=rtl.io.loadResult(path); obj.History{end+1}=result;
            obj.refreshHistory(); obj.loadHistory(numel(obj.History));
        end
        function exportDialog(obj)
            if isempty(obj.CurrentResult)||obj.IsStale
                obj.setStatus('没有可导出的当前结果，请重新规划。'); return;
            end
            folder=uigetdir(fullfile(obj.Root,'results'),'选择结果导出目录');
            if isequal(folder,0), return; end
            obj.guard(@()obj.exportCurrent(fullfile(folder,obj.CurrentResult.id)));
        end
        function guard(obj,action)
            try
                action();
            catch exception
                obj.setStatus(['操作失败：' exception.message]);
                rtl.io.appendLog(obj.Root,getReport(exception,'extended','hyperlinks','off'),'ERROR');
                if strcmp(obj.Figure.Visible,'on')
                    uialert(obj.Figure,exception.message,'操作未完成','Icon','error');
                end
            end
        end
        function endBusy(obj)
            if ~isvalid(obj), return; end
            obj.IsBusy=false;
            if ~isempty(obj.Figure)&&isvalid(obj.Figure)
                for k=1:numel(obj.BusyControls)
                    if isvalid(obj.BusyControls(k)), obj.BusyControls(k).Enable=obj.BusyEnable{k}; end
                end
                obj.BusyControls=[]; obj.BusyEnable={};
                obj.Controls.Play.Enable=~obj.IsStale && ~isempty(obj.CurrentResult) && ...
                    strcmp(obj.CurrentResult.status,'success');
            end
        end
        function setStatus(obj,message)
            if ~isempty(obj.Figure)&&isvalid(obj.Figure), obj.Controls.Status.Text=message; end
        end
        function notes=resultNotes(obj,result)
            notes={[obj.statusName(result.status) ': ' result.message]};
            if obj.IsStale, notes{end+1}='参数已改变：此结果不能作为当前结果回放或导出。'; end
            c=result.constraints;
            if isfield(c,'velocitySatisfied')
                notes{end+1}=sprintf('速度约束：%s；加速度约束：%s。', ...
                    obj.checkName(c.velocitySatisfied),obj.checkName(c.accelerationSatisfied));
                if ~isempty(c.velocityViolationJoints)
                    notes{end+1}=['速度超限关节：' mat2str(c.velocityViolationJoints)];
                end
                if ~isempty(c.accelerationViolationJoints)
                    notes{end+1}=['加速度超限关节：' mat2str(c.accelerationViolationJoints)];
                end
            elseif isfield(c,'isSatisfied')
                notes{end+1}=['端点、边界与路径安全约束：' obj.checkName(c.isSatisfied)];
            end
            collision=result.collision;
            if isfield(collision,'isCollisionFree')
                notes{end+1}=['碰撞检查：' obj.checkName(collision.isCollisionFree)];
            end
            if isfield(collision,'sampleCount')
                notes{end+1}=sprintf('关节路径样本：%d；实际最大角步长：%.5g rad。', ...
                    collision.sampleCount,collision.actualStep_rad);
                if ~isempty(collision.firstPairs)
                    notes{end+1}=['首次碰撞配对：' char(strjoin(join(string(collision.firstPairs),' / ',2),'; '))];
                end
            elseif isfield(collision,'minClearanceLowerBound_m')
                notes{end+1}=sprintf('整条折线保守净空下界：%.5g m。',collision.minClearanceLowerBound_m);
            end
            notes=[notes(:);result.diagnostics(:)];
        end
        function text=checkName(~,passed)
            if passed, text='通过'; else, text='未通过 / 未完成'; end
        end
        function text=statusName(~,status)
            switch status
                case 'success', text='规划成功 / 检查通过';
                case 'no_path', text='无可行路径';
                case 'invalid_input', text='输入无效';
                case 'validation_failed', text='约束或安全检查未通过';
                otherwise, text='运行错误';
            end
        end
        function text=kindName(~,kind)
            if strcmp(kind,'arm'), text='六轴机械臂'; else, text='移动机器人'; end
        end
    end
end
