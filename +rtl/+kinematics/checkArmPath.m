function report = checkArmPath(robot,start,goal,step,boxes)
%CHECKARMPATH 与播放帧率无关的关节路径采样；不构成连续碰撞证明。
validateattributes(start,{'numeric'},{'real','finite','size',[1 6]});
validateattributes(goal,{'numeric'},{'real','finite','size',[1 6]});
validateattributes(step,{'numeric'},{'real','finite','scalar','positive'});
validateattributes(boxes,{'numeric'},{'real','finite','2d','ncols',6});
if any(boxes(:,4:6) <= 0,'all')
    error('RobotTrajectoryLab:InvalidInput','Box dimensions must be positive.');
end
report = struct('isComplete',false,'isCollisionFree',false, ...
    'selfCollision',false,'environmentCollision',false,'sampleCount',0, ...
    'requestedStep_rad',step,'actualStep_rad',0,'method','sampled_joint_path', ...
    'skippedSelfCollisions','parent','firstCollisionFraction',NaN, ...
    'firstCollisionConfiguration',[],'firstPairs',{cell(0,2)}, ...
    'missingBodies',{{}},'minimumEnvironmentSeparation_m',NaN, ...
    'minimumSelfSeparation_m',NaN,'message','');
for index = 1:numel(robot.Bodies)
    body = robot.Bodies{index};
    if ~strcmp(body.Joint.Type,'fixed') && isempty(body.Collisions)
        report.missingBodies{end+1} = body.Name;
    end
end
if ~isempty(report.missingBodies)
    report.message = '运动连杆缺少碰撞几何，未完成碰撞检查。';
    return
end
world = cell(1,size(boxes,1));
for index = 1:size(boxes,1)
    object = collisionBox(boxes(index,4),boxes(index,5),boxes(index,6));
    pose = eye(4);
    pose(1:3,4) = boxes(index,1:3)';
    object.Pose = pose;
    world{index} = object;
end
difference = goal-start;
segments = ceil(max(abs(difference))/step);
if ~isfinite(segments) || segments > 100000
    error('RobotTrajectoryLab:InvalidInput','Collision sampling exceeds 100001 configurations.');
end
if segments == 0
    fractions = 0;
else
    fractions = linspace(0,1,segments+1);
    report.actualStep_rad = max(abs(difference))/segments;
end
bodyNames = [robot.BodyNames {robot.BaseName}];
bodyCount = numel(bodyNames);
selfMinimum = Inf;
environmentMinimum = Inf;
for index = 1:numel(fractions)
    configuration = start+fractions(index)*difference;
    [flags,distances] = checkCollision(robot,configuration,world, ...
        'Exhaustive','on','SkippedSelfCollisions','parent');
    selfCollision = logical(flags(1));
    environmentCollision = numel(flags)>1 && logical(flags(2));
    report.selfCollision = report.selfCollision || selfCollision;
    report.environmentCollision = report.environmentCollision || environmentCollision;
    selfDistances = distances(:,1:bodyCount);
    finiteSelf = selfDistances(isfinite(selfDistances));
    if ~isempty(finiteSelf)
        selfMinimum = min(selfMinimum,min(finiteSelf));
    end
    if ~isempty(world)
        environmentDistances = distances(:,bodyCount+1:end);
        finiteEnvironment = environmentDistances(isfinite(environmentDistances));
        if ~isempty(finiteEnvironment)
            environmentMinimum = min(environmentMinimum,min(finiteEnvironment));
        end
    end
    if (selfCollision || environmentCollision) && isnan(report.firstCollisionFraction)
        report.firstCollisionFraction = fractions(index);
        report.firstCollisionConfiguration = configuration;
        [rows,columns] = find(isnan(distances));
        for pair = 1:numel(rows)
            left = bodyNames{rows(pair)};
            if columns(pair) <= bodyCount
                right = bodyNames{columns(pair)};
                if rows(pair)>=columns(pair)
                    continue
                end
            else
                right = sprintf('box_%d',columns(pair)-bodyCount);
            end
            report.firstPairs(end+1,:) = {left,right};
        end
    end
end
report.sampleCount = numel(fractions);
report.isComplete = true;
report.isCollisionFree = ~report.selfCollision && ~report.environmentCollision;
if ~report.selfCollision && isfinite(selfMinimum)
    report.minimumSelfSeparation_m = selfMinimum;
end
if ~report.environmentCollision && isfinite(environmentMinimum)
    report.minimumEnvironmentSeparation_m = environmentMinimum;
end
if report.isCollisionFree
    report.message = '关节路径采样碰撞检查通过；该结果不是连续碰撞证明。';
else
    report.message = '关节路径采样检查发现碰撞；时间缩放不能改变碰撞结果。';
end
end
