function result = planMobile(request)
%PLANMOBILE 官方四邻域 A*、保守足迹检查和几何路径处理。
result = rtl.newResult(struct('kind','mobile','algorithm','astar'));
result.request = request;
phase = 'input';
try
    validateRequest(request);
    mapTimer = tic;
    [map,rawOccupancy] = rtl.planning.buildMap(request.map);
    options = request.options;
    validateEndpoint(request.start,map.GridSize,'起点');
    validateEndpoint(request.goal,map.GridSize,'终点');
    rho = options.robotRadius_m+options.safetyMargin_m;
    guard = request.map.cellSize_m/sqrt(2);
    planningMap = binaryOccupancyMap(rawOccupancy,map.Resolution);
    planningMap.GridLocationInWorld = map.GridLocationInWorld;
    inflate(planningMap,rho+guard);
    inflated = logical(occupancyMatrix(planningMap));
    [rows,cols] = ndgrid(1:request.map.rows,1:request.map.cols);
    centers = grid2world(map,[rows(:) cols(:)]);
    tolerance = max(1e-10,64*eps(max([1 abs(map.XWorldLimits) abs(map.YWorldLimits) rho])));
    inside = centers(:,1) > map.XWorldLimits(1)+rho+tolerance & ...
        centers(:,1) < map.XWorldLimits(2)-rho-tolerance & ...
        centers(:,2) > map.YWorldLimits(1)+rho+tolerance & ...
        centers(:,2) < map.YWorldLimits(2)-rho-tolerance;
    inflated(~reshape(inside,size(inflated))) = true;
    validateFreeEndpoint(request.start,inflated,'起点');
    validateFreeEndpoint(request.goal,inflated,'终点');
    planningMap = binaryOccupancyMap(inflated,map.Resolution);
    planningMap.GridLocationInWorld = map.GridLocationInWorld;
    mapBuildTime = toc(mapTimer);
    phase = 'planning';
    planner = plannerAStarGrid(planningMap);
    planner.DiagonalSearch = 'off';
    planner.GCost = 'Manhattan';
    planner.HCost = 'Manhattan';
    planner.TieBreaker = 'off';
    searchTimer = tic;
    if isequal(request.start,request.goal)
        gridPath = request.start;
        searchInfo = struct('PathCost',0,'NumNodesExplored',1);
    else
        [gridPath,searchInfo] = plan(planner,request.start,request.goal);
    end
    planningTime = toc(searchTimer);
    if isempty(gridPath)
        result.status = 'no_path';
        result.message = '当前足迹、安全距离和地图条件下没有找到路径。';
        result.metrics = struct('mapBuildTime_s',mapBuildTime,'planningTime_s',planningTime);
        result.diagnostics = {'保守膨胀可能阻塞窄通道；系统不会自动缩小机器人或安全距离。'};
        return;
    end
    result.rawPath = grid2world(map,gridPath);
    rawReport = rtl.planning.checkMobilePath(result.rawPath,map,rawOccupancy, ...
        options.robotRadius_m,options.safetyMargin_m);
    if ~rawReport.isCollisionFree
        result.status = 'validation_failed';
        result.message = 'A* 候选路径未通过独立连续安全检查。';
        result.collision = rawReport;
        return;
    end
    processTimer = tic;
    [candidate,processInfo] = rtl.optimization.processMobilePath(result.rawPath,map, ...
        rawOccupancy,options.robotRadius_m,options.safetyMargin_m,options.smoothIterations);
    finalReport = rtl.planning.checkMobilePath(candidate,map,rawOccupancy, ...
        options.robotRadius_m,options.safetyMargin_m);
    processingTime = toc(processTimer);
    if ~finalReport.isCollisionFree || ~isequal(candidate([1 end],:),result.rawPath([1 end],:))
        result.status = 'validation_failed';
        result.message = '处理后的路径未通过安全检查或端点一致性检查。';
        result.collision = finalReport;
        return;
    end
    result.finalPath = candidate;
    result.trajectory = pathTrajectory(candidate,options.referenceSpeed_m_s);
    result.baseline = struct('trajectory',pathTrajectory(result.rawPath,options.referenceSpeed_m_s), ...
        'metrics',pathMetrics(result.rawPath,rawReport,options.referenceSpeed_m_s));
    result.metrics = pathMetrics(candidate,finalReport,options.referenceSpeed_m_s);
    % R2025a 官方 PathCost 已按地图分辨率转换为世界坐标单位（米）。
    result.metrics.astarSearchCost_m = double(searchInfo.PathCost);
    result.metrics.astarNodesExplored_count = double(searchInfo.NumNodesExplored);
    result.metrics.mapBuildTime_s = mapBuildTime;
    result.metrics.planningTime_s = planningTime;
    result.metrics.processingTime_s = processingTime;
    result.metrics.smoothingAccepted_count = double(processInfo.smoothingAccepted);
    result.constraints = struct('isSatisfied',true,'boundarySatisfied',true, ...
        'startGoalPreserved',true,'dynamicsChecked',false);
    result.collision = finalReport;
    result.collision.rawPathIsCollisionFree = rawReport.isCollisionFree;
    result.diagnostics = {processInfo.message, ...
        '四邻域 A* 使用 Manhattan 代价；随机种子仅留档，算法不消耗随机数。', ...
        '安全检查采用占用单元格外接圆，可能保守拒绝窄通道；净空报告为保守下界。', ...
        '参考行驶时间由路径长度/参考速度计算，不包含动力学、加减速或跟踪控制。'};
    result.status = 'success';
    result.message = 'A* 规划及路径处理完成，最终折线已通过连续安全检查。';
catch exception
    if strcmp(phase,'input')
        result.status = 'invalid_input';
    else
        result.status = 'error';
    end
    result.message = exception.message;
    result.diagnostics = {getReport(exception,'extended','hyperlinks','off')};
end
end

function validateRequest(request)
fields = {'kind','algorithm','map','start','goal','options','seed'};
if ~isstruct(request) || ~isscalar(request) || ~all(isfield(request,fields)) || ...
        ~strcmp(request.kind,'mobile') || ~strcmp(request.algorithm,'astar')
    error('RobotTrajectoryLab:InvalidInput','移动机器人请求必须指定 mobile、astar 和完整参数。');
end
validateattributes(request.seed,{'numeric'},{'real','finite','scalar','integer','nonnegative'});
options = request.options;
required = {'robotRadius_m','safetyMargin_m','smoothIterations','referenceSpeed_m_s'};
if ~isstruct(options) || ~isscalar(options) || ~all(isfield(options,required))
    error('RobotTrajectoryLab:InvalidInput','移动规划选项不完整。');
end
validateattributes(options.robotRadius_m,{'numeric'},{'real','finite','scalar','nonnegative'});
validateattributes(options.safetyMargin_m,{'numeric'},{'real','finite','scalar','nonnegative'});
validateattributes(options.referenceSpeed_m_s,{'numeric'},{'real','finite','scalar','positive'});
validateattributes(options.smoothIterations,{'numeric'},{'real','finite','scalar','integer','>=',0,'<=',4});
end

function validateEndpoint(point,gridSize,label)
validateattributes(point,{'numeric'},{'real','finite','row','numel',2,'integer','positive'});
if point(1) > gridSize(1) || point(2) > gridSize(2)
    error('RobotTrajectoryLab:InvalidInput','%s超出地图栅格范围。',label);
end
end

function validateFreeEndpoint(point,inflated,label)
if inflated(point(1),point(2))
    error('RobotTrajectoryLab:InvalidInput','%s位于障碍物、保守膨胀区域或边界安全区域内。',label);
end
end

function trajectory = pathTrajectory(path,speed)
distances = sqrt(sum(diff(path,1,1).^2,2));
time = [0; cumsum(distances)]/speed;
if size(path,1) < 2
    yaw = 0;
else
    vector = diff(path,1,1);
    headings = unwrap(atan2(vector(:,2),vector(:,1)));
    yaw = [headings; headings(end)]';
end
trajectory = struct('t',time','position',path','yaw',yaw);
end

function metrics = pathMetrics(path,report,speed)
length_m = sum(sqrt(sum(diff(path,1,1).^2,2)));
if size(path,1) < 3
    turning = 0;
else
    vector = diff(path,1,1);
    headings = unwrap(atan2(vector(:,2),vector(:,1)));
    turning = sum(abs(diff(headings)));
end
metrics = struct('pathLength_m',length_m,'referenceTravelTime_s',length_m/speed, ...
    'referenceSpeed_m_s',speed,'minClearanceLowerBound_m',report.minClearanceLowerBound_m, ...
    'totalTurningAngle_rad',turning,'pathPointCount_count',size(path,1));
end
