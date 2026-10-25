function report = checkMobilePath(path,map,rawOccupancy,robotRadius_m,safetyMargin_m)
%CHECKMOBILEPATH 连续线段对占用格外接圆的保守解析安全检查。
% 该检查覆盖整条折线，不使用有限间隔采样。净空为保守下界。
validateattributes(path,{'numeric'},{'real','finite','2d','nonempty','ncols',2});
validateattributes(robotRadius_m,{'numeric'},{'real','finite','scalar','nonnegative'});
validateattributes(safetyMargin_m,{'numeric'},{'real','finite','scalar','nonnegative'});
if ~islogical(rawOccupancy) || ~isequal(size(rawOccupancy),map.GridSize)
    error('RobotTrajectoryLab:InvalidMap','原始占用矩阵必须是与地图同尺寸的 logical 矩阵。');
end
cellSize = 1/map.Resolution;
guard = cellSize/sqrt(2);
rho = robotRadius_m+safetyMargin_m;
xLimits = map.XWorldLimits;
yLimits = map.YWorldLimits;
tolerance = max(1e-10,64*eps(max([1 abs(xLimits) abs(yLimits) rho])));
report = struct('isCollisionFree',false,'method','occupied-cell circumscribed circles; analytic segments', ...
    'effectiveRadius_m',rho,'obstacleGuard_m',guard,'tolerance_m',tolerance, ...
    'minClearanceLowerBound_m',Inf,'invalidSegment',0,'reason','', ...
    'boundarySatisfied',false,'obstacleSatisfied',false);
boundaryDistances = [path(:,1)-xLimits(1); xLimits(2)-path(:,1); ...
    path(:,2)-yLimits(1); yLimits(2)-path(:,2)];
report.minClearanceLowerBound_m = min(boundaryDistances)-robotRadius_m;
report.boundarySatisfied = all(boundaryDistances > rho+tolerance);
if ~report.boundarySatisfied
    report.reason = 'boundary';
    badPoint = find(path(:,1) <= xLimits(1)+rho+tolerance | ...
        path(:,1) >= xLimits(2)-rho-tolerance | ...
        path(:,2) <= yLimits(1)+rho+tolerance | ...
        path(:,2) >= yLimits(2)-rho-tolerance,1);
    report.invalidSegment = max(1,badPoint-1);
    return;
end
[rows,cols] = find(rawOccupancy);
centers = zeros(0,2);
if ~isempty(rows)
    centers = grid2world(map,[rows cols]);
end
threshold = rho+guard+tolerance;
for index = 1:max(1,size(path,1)-1)
    a = path(index,:);
    b = path(min(index+1,size(path,1)),:);
    vector = b-a;
    squaredLength = sum(vector.^2);
    if isempty(centers)
        break;
    elseif squaredLength == 0
        distances = sqrt(sum((centers-a).^2,2));
    else
        fractions = max(0,min(1,((centers-a)*vector')/squaredLength));
        closest = a+fractions.*vector;
        distances = sqrt(sum((centers-closest).^2,2));
    end
    nearestDistance = min(distances);
    report.minClearanceLowerBound_m = min(report.minClearanceLowerBound_m, ...
        nearestDistance-guard-robotRadius_m);
    if nearestDistance <= threshold && report.invalidSegment == 0
        report.invalidSegment = index;
    end
end
report.obstacleSatisfied = report.invalidSegment == 0;
if ~report.obstacleSatisfied
    report.reason = 'obstacle';
    return;
end
report.isCollisionFree = true;
report.reason = 'clear';
end
