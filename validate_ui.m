function validate_ui()
%VALIDATE_UI 可见窗口验收与截图。生成的图片必须人工查看。
root=fileparts(mfilename('fullpath'));
folder=fullfile(root,'results','validation','screenshots');
if ~isfolder(folder), mkdir(folder); end
app=main(); cleanup=onCleanup(@()delete(app));
tester=matlab.uitest.TestCase.forInteractiveUse;
app.Figure.Position=[50 50 1280 800]; drawnow;
exportapp(app.Figure,fullfile(folder,'01_home_1280.png'));
app.selectPage('model'); drawnow; exportapp(app.Figure,fullfile(folder,'02_model_1280.png'));
app.selectPage('planning'); drawnow; tester.press(app.Controls.Run);
r=app.CurrentResult; assert(strcmp(r.status,'success'),r.message);
drawnow; exportapp(app.Figure,fullfile(folder,'03_arm_planning_1280.png'));
app.selectPage('simulation'); tester.press(app.Controls.Play); pause(0.3); drawnow; app.pause();
exportapp(app.Figure,fullfile(folder,'04_arm_simulation_1280.png'));
app.selectPage('analysis'); drawnow; tester.press(app.Controls.Optimize);
drawnow; exportapp(app.Figure,fullfile(folder,'05_arm_analysis_1280.png'));
app.setKind('mobile'); app.selectPage('model'); drawnow;
exportapp(app.Figure,fullfile(folder,'06_mobile_map_1280.png'));
app.selectPage('planning'); drawnow; tester.press(app.Controls.Run);
r=app.CurrentResult; assert(strcmp(r.status,'success'),r.message);
app.selectPage('simulation'); app.seek(r.trajectory.t(end)/2); drawnow;
exportapp(app.Figure,fullfile(folder,'07_mobile_simulation_1280.png'));
app.selectPage('history'); drawnow; exportapp(app.Figure,fullfile(folder,'08_history_1280.png'));
app.Figure.Position=[10 10 1920 1080]; app.selectPage('analysis'); drawnow;
pause(1); drawnow; % 等待 Web UI 完成大窗口布局，再采集图像。
exportapp(app.Figure,fullfile(folder,'09_mobile_analysis_1920.png'));
app.setKind('arm'); app.selectPage('planning'); drawnow;
exportapp(app.Figure,fullfile(folder,'10_arm_planning_1920.png'));
fprintf('Visible UI walkthrough and screenshots completed: %s\n',folder);
clear cleanup
end
