function validateProjectData(project)
%VALIDATEPROJECTDATA 严格检查界面必需字段；额外普通结构字段可保留。
identifier = 'RobotTrajectoryLab:InvalidProject';
try
    requireFields(project, {'schemaVersion', 'name', 'arm', 'mobile'});
    if ~isequal(project.schemaVersion, 1)
        error(identifier, 'Unsupported project schemaVersion.');
    end
    if isempty(scalarText(project.name, 'name')), error(identifier, 'Project name cannot be empty.'); end
    validateArm(project.arm);
    validateMobile(project.mobile);
    assertPlainData(project);
catch exception
    if strcmp(exception.identifier, 'RobotTrajectoryLab:NonSerializableData'), rethrow(exception); end
    error(identifier, '%s', exception.message);
end
end

function validateArm(request)
requireFields(request, {'kind','algorithm','model','endEffector','start','goal','seed','options'});
if ~strcmp(scalarText(request.kind, 'kind'), 'arm') || ...
        ~strcmp(scalarText(request.algorithm, 'algorithm'), 'quintic') || ...
        ~strcmp(scalarText(request.model, 'model'), 'universalUR5') || ...
        ~strcmp(scalarText(request.endEffector, 'endEffector'), 'tool0')
    error('RobotTrajectoryLab:InvalidProject', 'Unsupported arm request.');
end
vector(request.start, 6); vector(request.goal, 6); seed(request.seed);
options = request.options;
requireFields(options, {'duration_s','samplePeriod_s','velocityLimits','accelerationLimits', ...
    'scaleTime','collisionStep_rad','boxes'});
positive(options.duration_s); positive(options.samplePeriod_s); positive(options.collisionStep_rad);
vector(options.velocityLimits, 6); vector(options.accelerationLimits, 6);
if any(options.velocityLimits <= 0) || any(options.accelerationLimits <= 0)
    error('RobotTrajectoryLab:InvalidProject', 'Arm limits must be positive.');
end
validateattributes(options.scaleTime, {'numeric','logical'}, {'scalar','real','finite'});
if ~ismember(options.scaleTime, [0 1]), error('RobotTrajectoryLab:InvalidProject', 'scaleTime must be logical.'); end
matrix(options.boxes, 6);
if any(options.boxes(:, 4:6) <= 0, 'all')
    error('RobotTrajectoryLab:InvalidProject', 'Box dimensions must be positive.');
end
end

function validateMobile(request)
requireFields(request, {'kind','algorithm','map','start','goal','seed','options'});
if ~strcmp(scalarText(request.kind, 'kind'), 'mobile') || ...
        ~strcmp(scalarText(request.algorithm, 'algorithm'), 'astar')
    error('RobotTrajectoryLab:InvalidProject', 'Unsupported mobile request.');
end
seed(request.seed);
map = request.map;
requireFields(map, {'rows','cols','cellSize_m','originXY_m','rectangles'});
validateattributes(map.rows, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(map.cols, {'numeric'}, {'scalar','real','finite','integer','positive'});
positive(map.cellSize_m); vector(map.originXY_m, 2); matrix(map.rectangles, 4);
rectangles = map.rectangles;
if any(rectangles < 1 | rectangles ~= fix(rectangles), 'all') || ...
        any(rectangles(:, 1) + rectangles(:, 3) - 1 > map.rows) || ...
        any(rectangles(:, 2) + rectangles(:, 4) - 1 > map.cols)
    error('RobotTrajectoryLab:InvalidProject', 'Rectangles must be positive integer cells inside the map.');
end
for point = {request.start, request.goal}
    vector(point{1}, 2);
    if any(point{1} ~= fix(point{1})) || any(point{1} < 1) || any(point{1} > [map.rows map.cols])
        error('RobotTrajectoryLab:InvalidProject', 'Start and goal must be cells inside the map.');
    end
end
options = request.options;
requireFields(options, {'robotRadius_m','safetyMargin_m','smoothIterations','referenceSpeed_m_s'});
validateattributes(options.robotRadius_m, {'numeric'}, {'scalar','real','finite','nonnegative'});
validateattributes(options.safetyMargin_m, {'numeric'}, {'scalar','real','finite','nonnegative'});
validateattributes(options.smoothIterations, {'numeric'}, {'scalar','real','finite','integer','>=',0,'<=',4});
positive(options.referenceSpeed_m_s);
end

function requireFields(value, fields)
if ~isstruct(value) || ~isscalar(value) || ~all(isfield(value, fields))
    error('RobotTrajectoryLab:InvalidProject', 'Project structure is incomplete.');
end
end

function vector(value, count)
validateattributes(value, {'numeric'}, {'real','finite','size',[1 count]});
end

function matrix(value, count)
validateattributes(value, {'numeric'}, {'real','finite','2d'});
if size(value, 2) ~= count
    error('RobotTrajectoryLab:InvalidProject', 'Expected a matrix with %d columns.', count);
end
end

function positive(value)
validateattributes(value, {'numeric'}, {'scalar','real','finite','positive'});
end

function seed(value)
validateattributes(value, {'numeric'}, {'scalar','real','finite','integer','>=',0,'<=',2^32-1});
end
