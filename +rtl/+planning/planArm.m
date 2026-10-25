function result = planArm(request)
%PLANARM 官方 UR5 的同步五次关节轨迹、解析约束与采样碰撞检查。
validateRequest(request);
robot = rtl.models.loadArm();
limits = rtl.models.armPositionLimits(robot);
if any(request.start < limits(:,1)' | request.start > limits(:,2)') || ...
        any(request.goal < limits(:,1)' | request.goal > limits(:,2)')
    error('RobotTrajectoryLab:InvalidInput','Joint endpoints exceed the official position limits.');
end
result = rtl.newResult(request);
planningClock = tic;
options = request.options;
difference = request.goal-request.start;
scalingClock = tic;
scaling = rtl.optimization.scaleArmTime(difference,options.duration_s, ...
    options.velocityLimits,options.accelerationLimits,options.scaleTime);
scalingTime = toc(scalingClock);
validateSampleCount(scaling.selectedDuration_s,options.samplePeriod_s);

% 路径与碰撞使用固定几何参数，时间缩放前后共用同一份空间结果。
collisionClock = tic;
collision = rtl.kinematics.checkArmPath(robot,request.start,request.goal, ...
    options.collisionStep_rad,options.boxes);
collisionTime = toc(collisionClock);
pathSegments = max(100,ceil(max(abs(difference))/min(0.01,options.collisionStep_rad)));
if pathSegments > 100000
    error('RobotTrajectoryLab:InvalidInput','Geometric path sampling exceeds 100001 configurations.');
end
pathFraction = linspace(0,1,pathSegments+1);
pathQ = request.start' + difference'*pathFraction;
tcpPath = rtl.kinematics.forwardArm(robot,pathQ,request.endEffector);
tcpLength = sum(vecnorm(diff(tcpPath,1,2),2,1));

baselineClock = tic;
baselineTrajectory = makeTrajectory(robot,request,options.duration_s);
baselineGenerationTime = toc(baselineClock);
baselineConstraints = checkConstraints(difference,options.duration_s,options,collision);
baselineMetrics = calculateMetrics(difference,options.duration_s,tcpLength,collision);
baselineMetrics.trajectoryGenerationTime_s = baselineGenerationTime;
result.baseline = struct('trajectory',baselineTrajectory,'metrics',baselineMetrics, ...
    'constraints',baselineConstraints);

generationTime = baselineGenerationTime;
if scaling.wasScaled
    generationClock = tic;
    result.trajectory = makeTrajectory(robot,request,scaling.selectedDuration_s);
    generationTime = toc(generationClock);
else
    result.trajectory = baselineTrajectory;
end
result.rawPath = tcpPath';
result.finalPath = tcpPath';
result.constraints = checkConstraints(difference,scaling.selectedDuration_s,options,collision);
result.collision = collision;
result.metrics = calculateMetrics(difference,scaling.selectedDuration_s,tcpLength,collision);
result.metrics.trajectoryGenerationTime_s = generationTime;
result.metrics.collisionCheckTime_s = collisionTime;
result.metrics.timeScalingTime_s = scalingTime;
result.metrics.planningTime_s = toc(planningClock);
result.timeScaling = scaling;
result.diagnostics = {collision.message, ...
    '速度与加速度上限是用户设置的仿真约束，不代表厂家额定参数。', ...
    '本结果为运动学仿真；时间缩放不改变路径，不涉及动力学或轨迹跟踪。'};
if scaling.wasScaled
    result.diagnostics{end+1} = '已按固定五次曲线解析缩放时间；未进行全局路径优化。';
end
if result.constraints.isSatisfied
    result.status = 'success';
    result.message = '五次关节轨迹已生成，速度、加速度与采样碰撞检查通过。';
else
    result.status = 'validation_failed';
    reasons = {};
    if ~result.constraints.velocitySatisfied || ~result.constraints.accelerationSatisfied
        reasons{end+1} = '关节速度或加速度超限，可执行时间缩放';
    end
    if ~collision.isCollisionFree
        reasons{end+1} = collision.message;
    end
    result.message = ['轨迹已生成，但约束检查未通过：' strjoin(reasons,'；')];
end
end

function validateRequest(request)
required = {'kind','algorithm','model','endEffector','start','goal','options','seed'};
if ~isstruct(request) || ~isscalar(request) || ~all(isfield(request,required)) || ...
        ~strcmp(request.kind,'arm') || ~strcmp(request.algorithm,'quintic') || ...
        ~strcmp(request.model,'universalUR5') || ~strcmp(request.endEffector,'tool0')
    error('RobotTrajectoryLab:InvalidInput','UR5/tool0 with the quintic planner is required.');
end
validateattributes(request.start,{'numeric'},{'real','finite','size',[1 6]});
validateattributes(request.goal,{'numeric'},{'real','finite','size',[1 6]});
validateattributes(request.seed,{'numeric'},{'real','finite','integer','nonnegative','scalar'});
fields = {'duration_s','samplePeriod_s','velocityLimits','accelerationLimits', ...
    'scaleTime','collisionStep_rad','boxes'};
options = request.options;
if ~isstruct(options) || ~isscalar(options) || ~all(isfield(options,fields))
    error('RobotTrajectoryLab:InvalidInput','The arm trajectory options are incomplete.');
end
validateattributes(options.duration_s,{'numeric'},{'real','finite','positive','scalar'});
validateattributes(options.samplePeriod_s,{'numeric'},{'real','finite','positive','scalar'});
validateattributes(options.velocityLimits,{'numeric'},{'real','finite','positive','size',[1 6]});
validateattributes(options.accelerationLimits,{'numeric'},{'real','finite','positive','size',[1 6]});
validateattributes(options.collisionStep_rad,{'numeric'},{'real','finite','positive','scalar'});
validateattributes(options.scaleTime,{'logical','numeric'},{'scalar','real','finite'});
if ~ismember(options.scaleTime,[0 1])
    error('RobotTrajectoryLab:InvalidInput','scaleTime must be logical.');
end
validateattributes(options.boxes,{'numeric'},{'real','finite','2d','ncols',6});
if any(options.boxes(:,4:6)<=0,'all')
    error('RobotTrajectoryLab:InvalidInput','Box dimensions must be positive.');
end
validateSampleCount(options.duration_s,options.samplePeriod_s);
end

function validateSampleCount(duration,samplePeriod)
segments = ceil(duration/samplePeriod);
if ~isfinite(segments) || segments>100000
    error('RobotTrajectoryLab:InvalidInput','Trajectory sampling exceeds 100001 samples.');
end
end

function trajectory = makeTrajectory(robot,request,duration)
segments = max(1,ceil(duration/request.options.samplePeriod_s));
t = linspace(0,duration,segments+1);
% 在归一化时间上调用官方轨迹函数，避免极端 T 使多项式系数病态。
[q,qd,qdd] = quinticpolytraj([request.start' request.goal'],[0 1],t/duration, ...
    'VelocityBoundaryCondition',zeros(6,2),'AccelerationBoundaryCondition',zeros(6,2));
qd = qd/duration;
qdd = qdd/duration^2;
if any(~isfinite(q),'all') || any(~isfinite(qd),'all') || any(~isfinite(qdd),'all')
    error('RobotTrajectoryLab:InvalidInput','The requested duration is numerically too small.');
end
trajectory = struct('t',t,'q',q,'qd',qd,'qdd',qdd, ...
    'tcp',rtl.kinematics.forwardArm(robot,q,request.endEffector));
end

function report = checkConstraints(difference,duration,options,collision)
velocity = 15*abs(difference)/(8*duration);
acceleration = 10*sqrt(3)*abs(difference)/(3*duration^2);
velocityRatio = velocity./options.velocityLimits;
accelerationRatio = acceleration./options.accelerationLimits;
velocitySatisfied = all(velocityRatio<=1+1e-9);
accelerationSatisfied = all(accelerationRatio<=1+1e-9);
report = struct('isSatisfied',velocitySatisfied && accelerationSatisfied && ...
    collision.isComplete && collision.isCollisionFree,'positionSatisfied',true, ...
    'velocitySatisfied',velocitySatisfied,'accelerationSatisfied',accelerationSatisfied, ...
    'collisionSatisfied',collision.isComplete && collision.isCollisionFree, ...
    'peakVelocity_rad_s',velocity,'peakAcceleration_rad_s2',acceleration, ...
    'velocityLimits_rad_s',options.velocityLimits, ...
    'accelerationLimits_rad_s2',options.accelerationLimits, ...
    'velocityRatio',velocityRatio,'accelerationRatio',accelerationRatio, ...
    'velocityViolationJoints',find(velocityRatio>1+1e-9), ...
    'accelerationViolationJoints',find(accelerationRatio>1+1e-9));
end

function metrics = calculateMetrics(difference,duration,tcpLength,collision)
metrics = struct('motionDuration_s',duration,'jointPathLength_rad',norm(difference), ...
    'tcpPathLength_m',tcpLength,'peakJointVelocity_rad_s',max(15*abs(difference)/(8*duration)), ...
    'peakJointAcceleration_rad_s2',max(10*sqrt(3)*abs(difference)/(3*duration^2)), ...
    'peakJointJerk_rad_s3',max(60*abs(difference)/duration^3), ...
    'squaredJerkIntegral_rad2_s5',720*sum(difference.^2)/duration^5, ...
    'minimumObstacleSeparation_m',collision.minimumEnvironmentSeparation_m);
end
