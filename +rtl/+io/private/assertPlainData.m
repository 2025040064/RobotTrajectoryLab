function assertPlainData(value)
%ASSERTPLAINDATA 防止保存窗口、计时器、机器人模型或其他对象。
if isstruct(value)
    fields = fieldnames(value);
    for item = 1:numel(value)
        for index = 1:numel(fields)
            assertPlainData(value(item).(fields{index}));
        end
    end
elseif iscell(value)
    for index = 1:numel(value), assertPlainData(value{index}); end
elseif ~(isnumeric(value) || islogical(value) || ischar(value) || isstring(value))
    error('RobotTrajectoryLab:NonSerializableData', ...
        'Only numeric, logical, text, cell and struct data can be saved; found %s.', class(value));
end
end
