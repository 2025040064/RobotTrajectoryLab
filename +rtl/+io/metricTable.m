function values = metricTable(result)
%METRICTABLE 将真实数值指标展平成 Metric/Value/Unit 表。
if ~isstruct(result) || ~isscalar(result) || ~isfield(result, 'metrics')
    error('RobotTrajectoryLab:InvalidResult', 'Result metrics are missing.');
end
[names, numbers, units] = metricRows(result.metrics, '');
values = table(names, numbers, units, 'VariableNames', {'Metric', 'Value', 'Unit'});
end

function [names, numbers, units] = metricRows(metrics, prefix)
names = strings(0, 1); numbers = zeros(0, 1); units = strings(0, 1);
if ~isstruct(metrics) || ~isscalar(metrics), return; end
fields = fieldnames(metrics);
for index = 1:numel(fields)
    field = fields{index};
    value = metrics.(field);
    label = [prefix field];
    if isstruct(value) && isscalar(value)
        [childNames, childNumbers, childUnits] = metricRows(value, [label '.']);
        names = [names; childNames]; %#ok<AGROW>
        numbers = [numbers; childNumbers]; %#ok<AGROW>
        units = [units; childUnits]; %#ok<AGROW>
    elseif (isnumeric(value) || islogical(value)) && isreal(value) && ~isempty(value)
        for element = 1:numel(value)
            elementLabel = label;
            if ~isscalar(value), elementLabel = sprintf('%s(%d)', label, element); end
            names(end + 1, 1) = string(elementLabel); %#ok<AGROW>
            numbers(end + 1, 1) = double(value(element)); %#ok<AGROW>
            units(end + 1, 1) = string(fieldUnit(field)); %#ok<AGROW>
        end
    end
end
end

function unit = fieldUnit(field)
suffixes = {'_rad2_s5', '_rad_s3', '_rad_s2', '_rad_s', '_m_s2', '_m_s', '_rad', '_deg', '_ms', '_s', '_m', '_cells', '_count'};
labels = {'rad^2/s^5', 'rad/s^3', 'rad/s^2', 'rad/s', 'm/s^2', 'm/s', 'rad', 'deg', 'ms', 's', 'm', 'cells', 'count'};
unit = '';
for index = 1:numel(suffixes)
    if endsWith(field, suffixes{index})
        unit = labels{index};
        return;
    end
end
end
