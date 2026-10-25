function robot = loadArm()
%LOADARM UR5 只读缓存；独立程序优先加载随包模型，不依赖开发机路径。
persistent cachedRobot
if isempty(cachedRobot)
    root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
    resource=fullfile(root,'assets','models','universalUR5.mat');
    if isfile(resource)
        loaded=load(resource,'robot'); cachedRobot=loaded.robot;
    elseif isdeployed
        error('RobotTrajectoryLab:ModelError','Bundled UR5 model resource is missing.');
    else
        cachedRobot=loadrobot('universalUR5','DataFormat','row','Gravity',[0 0 -9.81]);
    end
    if numel(homeConfiguration(cachedRobot))~=6 || ~any(strcmp(cachedRobot.BodyNames,'tool0'))
        error('RobotTrajectoryLab:ModelError','The official UR5/tool0 model is invalid.');
    end
end
robot=cachedRobot;
end
