function project = loadProject(path)
%LOADPROJECT 加载项目并在交给界面前校验全部必需参数。
loaded = load(path, 'project');
if ~isfield(loaded, 'project')
    error('RobotTrajectoryLab:InvalidProject', 'MAT file does not contain a project variable.');
end
project = loaded.project;
validateProjectData(project);
end
