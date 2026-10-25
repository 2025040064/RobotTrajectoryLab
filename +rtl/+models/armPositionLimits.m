function limits = armPositionLimits(robot)
%ARMPOSITIONLIMITS 按 rigidBodyTree 的配置顺序取得六关节位置范围。
limits = zeros(6,2);
joint = 0;
for index = 1:numel(robot.Bodies)
    body = robot.Bodies{index};
    if ~strcmp(body.Joint.Type,'fixed')
        joint = joint + 1;
        if joint > 6 || ~strcmp(body.Joint.Type,'revolute')
            error('RobotTrajectoryLab:ModelError','A six-revolute-joint model is required.');
        end
        limits(joint,:) = body.Joint.PositionLimits;
    end
end
if joint ~= 6
    error('RobotTrajectoryLab:ModelError','A six-revolute-joint model is required.');
end
end
