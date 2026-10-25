function transform = forwardIndependent(robot,q,endEffector)
%FORWARDINDEPENDENT 独立连乘固定变换及 Rodrigues 旋转，不调用 getTransform。
validateattributes(q,{'numeric'},{'real','finite','vector','numel',6});
q = reshape(q,1,6);
bodyCount = numel(robot.Bodies);
transforms = repmat(eye(4),1,1,bodyCount);
jointIndex = 0;
for index = 1:bodyCount
    body = robot.Bodies{index};
    motion = eye(4);
    switch body.Joint.Type
        case 'revolute'
            jointIndex = jointIndex + 1;
            axis = body.Joint.JointAxis(:);
            skew = [0 -axis(3) axis(2); axis(3) 0 -axis(1); -axis(2) axis(1) 0];
            angle = q(jointIndex);
            motion(1:3,1:3) = eye(3) + sin(angle)*skew + (1-cos(angle))*(skew*skew);
        case 'fixed'
        otherwise
            error('RobotTrajectoryLab:ModelError','Only fixed and revolute joints are supported.');
    end
    local = body.Joint.JointToParentTransform*motion*body.Joint.ChildToJointTransform;
    parentName = body.Parent.Name;
    if strcmp(parentName,robot.BaseName)
        transforms(:,:,index) = local;
    else
        parentIndex = find(strcmp(robot.BodyNames,parentName),1);
        if isempty(parentIndex) || parentIndex >= index
            error('RobotTrajectoryLab:ModelError','The model is not in parent-first order.');
        end
        transforms(:,:,index) = transforms(:,:,parentIndex)*local;
    end
end
targetIndex = find(strcmp(robot.BodyNames,endEffector),1);
if isempty(targetIndex)
    error('RobotTrajectoryLab:InvalidInput','The end-effector body does not exist.');
end
transform = transforms(:,:,targetIndex);
end
