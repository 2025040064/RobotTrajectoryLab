function result = loadResult(path)
%LOADRESULT 加载并校验规划结果，失败状态原样保留。
loaded = load(path, 'result');
if ~isfield(loaded, 'result')
    error('RobotTrajectoryLab:InvalidResult', 'MAT file does not contain a result variable.');
end
result = loaded.result;
validateResultData(result);
end
