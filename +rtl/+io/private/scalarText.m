function text = scalarText(value, name)
%SCALARTEXT 只接受单个字符向量或非缺失字符串。
if isstring(value) && isscalar(value) && ~ismissing(value)
    text = char(value);
elseif ischar(value) && (isrow(value) || isempty(value))
    text = value;
else
    error('RobotTrajectoryLab:InvalidInput', '%s must be scalar text.', name);
end
end
