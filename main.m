function application = main(options)
%MAIN 启动 RobotTrajectoryLab；main(Visible="off") 用于自动化检查。
arguments
    options.Visible (1,1) string {mustBeMember(options.Visible,["on","off"])} = "on"
    options.DataRoot (1,1) string = ""
end
root = fileparts(mfilename('fullpath'));
if ~isdeployed, addpath(root); end
if strlength(options.DataRoot)>0, root=char(options.DataRoot); end
if ~isfolder(root), mkdir(root); end
application = rtl.app.MainApp(root,char(options.Visible));
end
