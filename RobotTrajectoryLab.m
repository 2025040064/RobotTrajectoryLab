function RobotTrajectoryLab(varargin)
%ROBOTTRAJECTORYLAB 独立程序入口；等待窗口关闭，避免启动后立即退出。
mode='--gui';
if ~isempty(varargin), mode=char(varargin{1}); end
if numel(varargin)>=2
    root=char(varargin{2});
else
    if isdeployed
        root=fullfile(getenv('USERPROFILE'),'RobotTrajectoryLab_Data');
    else
        root=fullfile(pwd,'RobotTrajectoryLab_Data');
    end
end
if ~isfolder(root), mkdir(root); end
if ismember(mode,{'--gui','--startup-check'})
    startGui(root,strcmp(mode,'--startup-check'));
elseif ismember(mode,{'--selftest','--gui-smoke'})
    report=struct('success',false,'isDeployed',isdeployed,'version',version, ...
        'release',version('-release'),'runtimeRoot',matlabroot, ...
        'softwareVersion','1.0.1','mode',mode,'message','');
    try
        project=rtl.defaultProject();
        arm=rtl.planning.plan(project.arm); assert(strcmp(arm.status,'success'),arm.message);
        project.arm.options.scaleTime=true;
        scaled=rtl.planning.plan(project.arm); assert(strcmp(scaled.status,'success'),scaled.message);
        mobile=rtl.planning.plan(project.mobile); assert(strcmp(mobile.status,'success'),mobile.message);
        rtl.io.exportResult(arm,fullfile(root,'arm'));
        rtl.io.exportResult(scaled,fullfile(root,'arm_scaled'));
        rtl.io.exportResult(mobile,fullfile(root,'mobile'));
        rtl.io.saveProject(project,fullfile(root,'project.mat'));
        restored=rtl.io.loadProject(fullfile(root,'project.mat')); assert(isequal(restored,project));
        report.armDuration_s=arm.metrics.motionDuration_s;
        report.scaledDuration_s=scaled.metrics.motionDuration_s;
        report.mobilePathLength_m=mobile.metrics.pathLength_m;
        if strcmp(mode,'--gui-smoke')
            fprintf('GUI_SMOKE_START\n');
            app=main(DataRoot=string(root)); cleanup=onCleanup(@()delete(app));
            timerHandle=app.PlaybackTimer; fprintf('GUI_INITIALIZED\n');
            result=app.runPlanning(); assert(strcmp(result.status,'success'),result.message);
            app.selectPage('simulation'); app.play(); pause(0.25); app.pause(); drawnow;
            app.seek(result.trajectory.t(end)/2); pause(1); drawnow;
            exportapp(app.Figure,fullfile(root,'standalone_arm.png'));
            app.setKind('mobile'); result=app.runPlanning(); assert(strcmp(result.status,'success'),result.message);
            app.selectPage('simulation'); app.seek(result.trajectory.t(end)/2); pause(1); drawnow;
            exportapp(app.Figure,fullfile(root,'standalone_mobile.png'));
            clear cleanup
            assert(~isvalid(timerHandle),'Playback timer was not released.');
            report.guiAndTimerReleased=true;
        end
        report.success=true; report.message='UR5, time scaling, A*, MAT/CSV round-trip passed.';
    catch exception
        report.message=getReport(exception,'extended','hyperlinks','off');
        writeReport(root,report); rethrow(exception);
    end
    writeReport(root,report); fprintf('ROBOTTRAJECTORYLAB_SELFTEST_OK\n');
else
    error('RobotTrajectoryLab:InvalidInput','Usage: RobotTrajectoryLab [--gui|--startup-check|--selftest|--gui-smoke] [data-folder]');
end
end
function startGui(root,checkOnly)
% Exercise the same cold GUI startup for normal launch and deployment checks.
clock=tic;
report=struct('success',false,'phase','initializing','softwareVersion','1.0.1', ...
    'isDeployed',isdeployed,'runtimeRoot',matlabroot,'elapsed_s',0,'message','');
writeJson(fullfile(root,'startup_report.json'),report);
app=[];
try
    app=main(DataRoot=string(root));
    cleanup=onCleanup(@()delete(app));
    app.Figure.Visible='on'; drawnow; figure(app.Figure); drawnow;
    report.success=true; report.phase='ready'; report.elapsed_s=toc(clock);
    report.windowVisible=strcmp(app.Figure.Visible,'on');
    report.windowTitle=app.Figure.Name;
    writeJson(fullfile(root,'startup_report.json'),report);
    if checkOnly
        pause(1); drawnow;
        exportapp(app.Figure,fullfile(root,'startup.png'));
        timerHandle=app.PlaybackTimer;
        clear cleanup
        assert(~isvalid(timerHandle),'Playback timer was not released.');
        report.guiAndTimerReleased=true;
        writeJson(fullfile(root,'startup_report.json'),report);
    else
        waitfor(app.Figure);
        clear cleanup
    end
catch exception
    if ~isempty(app)&&isvalid(app), delete(app); end
    report.success=false; report.phase='failed'; report.elapsed_s=toc(clock);
    report.message=getReport(exception,'extended','hyperlinks','off');
    writeJson(fullfile(root,'startup_report.json'),report);
    if checkOnly, rethrow(exception); end
    dialog=errordlg({'软件启动失败，请查看启动诊断文件：', ...
        fullfile(root,'startup_report.json'),exception.message},'RobotTrajectoryLab 启动失败','modal');
    waitfor(dialog);
end
end
function writeReport(root,report)
writeJson(fullfile(root,'selftest_report.json'),report);
end
function writeJson(file,report)
fid=fopen(file,'w','n','UTF-8');
if fid<0, error('RobotTrajectoryLab:FileWriteFailed','Cannot write self-test report.'); end
cleanup=onCleanup(@()fclose(fid)); fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true));
end
