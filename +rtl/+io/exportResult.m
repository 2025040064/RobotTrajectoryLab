function files = exportResult(result, folder)
%EXPORTRESULT 导出 MAT、带单位的轨迹 CSV 和环境/指标摘要 CSV。
% 失败结果仍保存状态和诊断；只有形状完整的有效轨迹才导出 CSV。
validateResultData(result);
folder = scalarText(folder, 'folder');
if isempty(folder), error('RobotTrajectoryLab:InvalidInput', 'Export folder cannot be empty.'); end
if ~isfolder(folder), mkdir(folder); end
if ~isfield(result, 'environment'), result.environment = rtl.io.environmentInfo(); end
trajectory = trajectoryTable(result);
stem = regexprep(char(result.id), '[^A-Za-z0-9_-]', '_');
if isempty(stem), stem = 'result'; end
files = struct('mat', fullfile(folder, [stem '.mat']), ...
    'trajectory', '', 'summary', fullfile(folder, [stem '_summary.csv']));
rtl.io.saveResult(result, files.mat);
if ~isempty(trajectory)
    files.trajectory = fullfile(folder, [stem '_trajectory.csv']);
    writetable(trajectory, files.trajectory, 'Encoding', 'UTF-8');
end
writetable(summaryTable(result), files.summary, 'Encoding', 'UTF-8');
end

function output = trajectoryTable(result)
output = table();
trajectory = result.trajectory;
if isempty(fieldnames(trajectory)), return; end
try
    if ~isfield(trajectory, 't'), error('RobotTrajectoryLab:InvalidTrajectory', 'Missing time vector.'); end
    time = trajectory.t;
    validateattributes(time, {'numeric'}, {'vector','real','finite','nonempty','nonnegative'});
    if any(diff(time(:)) < 0), error('RobotTrajectoryLab:InvalidTrajectory', 'Time must be nondecreasing.'); end
    count = numel(time);
    if strcmp(result.kind, 'arm')
        requireArray(trajectory, 'q', [6 count]);
        requireArray(trajectory, 'qd', [6 count]);
        requireArray(trajectory, 'qdd', [6 count]);
        requireArray(trajectory, 'tcp', [3 count]);
        names = {'time_s'};
        for prefix = {'q', 'qd', 'qdd'}
            switch prefix{1}
                case 'q', unit = 'rad';
                case 'qd', unit = 'rad_s';
                otherwise, unit = 'rad_s2';
            end
            for joint = 1:6
                names{end + 1} = sprintf('%s%d_%s', prefix{1}, joint, unit); %#ok<AGROW>
            end
        end
        names = [names {'tcp_x_m', 'tcp_y_m', 'tcp_z_m'}];
        data = [time(:), trajectory.q.', trajectory.qd.', trajectory.qdd.', trajectory.tcp.'];
    elseif strcmp(result.kind, 'mobile')
        requireArray(trajectory, 'position', [2 count]);
        if ~isfield(trajectory, 'yaw'), error('RobotTrajectoryLab:InvalidTrajectory', 'Missing yaw.'); end
        validateattributes(trajectory.yaw, {'numeric'}, {'vector','real','finite','numel',count});
        names = {'time_s', 'x_m', 'y_m', 'yaw_rad'};
        data = [time(:), trajectory.position.', trajectory.yaw(:)];
    else
        return;
    end
    output = array2table(data, 'VariableNames', names);
catch exception
    if strcmp(result.status, 'success'), rethrow(exception); end
    % 失败结果可以只有路径或诊断，不生成会误导下游的残缺轨迹。
end
end

function requireArray(trajectory, name, shape)
if ~isfield(trajectory, name), error('RobotTrajectoryLab:InvalidTrajectory', 'Missing trajectory %s.', name); end
value = trajectory.(name);
if ~isnumeric(value) || ~isreal(value) || ~all(isfinite(value), 'all') || ~isequal(size(value), shape)
    error('RobotTrajectoryLab:InvalidTrajectory', 'Trajectory %s must be a finite %d-by-%d array.', name, shape(1), shape(2));
end
end

function output = summaryTable(result)
section = strings(0, 1); key = strings(0, 1); textValue = strings(0, 1);
numericValue = zeros(0, 1); unit = strings(0, 1);
append('metadata', 'schemaVersion', result.schemaVersion, '');
for field = {'id','kind','algorithm','status','message','createdAt','softwareVersion','matlabRelease'}
    append('metadata', field{1}, string(result.(field{1})), '');
end
if isstruct(result.request) && isscalar(result.request) && isfield(result.request, 'seed') && ...
        isnumeric(result.request.seed) && isscalar(result.request.seed) && isfinite(result.request.seed)
    append('metadata', 'seed', result.request.seed, '');
else
    append('metadata', 'seed', "unavailable", '');
end
environment = result.environment;
for field = {'matlabVersion','matlabRelease','architecture'}
    if isfield(environment, field{1})
        append('environment', field{1}, string(environment.(field{1})), '');
    end
end
if isfield(environment, 'toolboxes') && isstruct(environment.toolboxes)
    for index = 1:numel(environment.toolboxes)
        product = environment.toolboxes(index);
        if all(isfield(product, {'name','version','release'}))
            append('environment', ['toolbox.' char(product.name)], ...
                string(product.version) + " " + string(product.release), '');
        end
    end
end
metrics = rtl.io.metricTable(result);
for index = 1:height(metrics)
    append('metrics', metrics.Metric(index), metrics.Value(index), metrics.Unit(index));
end
if isfield(result.baseline, 'metrics')
    baseline = rtl.io.metricTable(struct('metrics', result.baseline.metrics));
    for index = 1:height(baseline)
        append('baseline', baseline.Metric(index), baseline.Value(index), baseline.Unit(index));
    end
end
if iscell(result.diagnostics) || isstring(result.diagnostics)
    for index = 1:numel(result.diagnostics)
        if iscell(result.diagnostics), detail = result.diagnostics{index}; else, detail = result.diagnostics(index); end
        if ischar(detail) || (isstring(detail) && isscalar(detail))
            append('diagnostics', sprintf('message%d', index), string(detail), '');
        end
    end
end
output = table(section, key, textValue, numericValue, unit, ...
    'VariableNames', {'Section', 'Key', 'TextValue', 'NumericValue', 'Unit'});

    function append(group, name, value, valueUnit)
        section(end + 1, 1) = string(group);
        key(end + 1, 1) = string(name);
        if isnumeric(value) || islogical(value)
            textValue(end + 1, 1) = "";
            numericValue(end + 1, 1) = double(value);
        else
            textValue(end + 1, 1) = string(value);
            numericValue(end + 1, 1) = NaN;
        end
        unit(end + 1, 1) = string(valueUnit);
    end
end
