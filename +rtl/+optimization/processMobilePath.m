function [finalPath,info] = processMobilePath(path,map,rawOccupancy,robotRadius_m,safetyMargin_m,iterations)
%PROCESSMOBILEPATH 安全直连简化，再尝试至多四轮 Chaikin 圆角。
validateattributes(iterations,{'numeric'},{'real','finite','scalar','integer','>=',0,'<=',4});
check = @(candidate) rtl.planning.checkMobilePath(candidate,map,rawOccupancy,robotRadius_m,safetyMargin_m);
initial = check(path);
if ~initial.isCollisionFree
    error('RobotTrajectoryLab:UnsafePath','原始路径未通过连续安全检查，不能执行平滑。');
end
path = removeDuplicates(path);
simplified = path(1,:);
current = 1;
while current < size(path,1)
    next = size(path,1);
    while next > current+1
        segmentReport = check(path([current next],:));
        if segmentReport.isCollisionFree
            break;
        end
        next = next-1;
    end
    simplified(end+1,:) = path(next,:); %#ok<AGROW>
    current = next;
end
info = struct('smoothingRequested',iterations > 0,'smoothingAccepted',false, ...
    'smoothingRejected',false,'iterations',iterations,'simplifiedPath',simplified, ...
    'candidatePath',simplified,'message','已完成安全直连简化。');
finalPath = simplified;
if iterations == 0 || size(simplified,1) < 3
    return;
end
candidate = simplified;
for iteration = 1:iterations
    first = 0.75*candidate(1:end-1,:)+0.25*candidate(2:end,:);
    second = 0.25*candidate(1:end-1,:)+0.75*candidate(2:end,:);
    rounded = zeros(2*size(first,1)+2,2);
    rounded(1,:) = candidate(1,:);
    rounded(2:2:end-1,:) = first;
    rounded(3:2:end-1,:) = second;
    rounded(end,:) = candidate(end,:);
    candidate = removeDuplicates(rounded);
end
info.candidatePath = candidate;
candidateReport = check(candidate);
if candidateReport.isCollisionFree
    finalPath = candidate;
    info.smoothingAccepted = true;
    info.message = '直连简化与 Chaikin 圆角后的完整折线已通过连续安全检查。';
else
    info.smoothingRejected = true;
    info.message = 'Chaikin 圆角未通过安全检查，已回退至安全直连简化路径。';
end
end

function path = removeDuplicates(path)
if size(path,1) > 1
    path = path([true; any(diff(path,1,1) ~= 0,2)],:);
end
end
