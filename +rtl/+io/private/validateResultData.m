function validateResultData(result)
%VALIDATERESULTDATA 保留失败输入，但校验可供回放和导出的结果外壳。
required = {'schemaVersion','id','kind','algorithm','status','message','request', ...
    'createdAt','softwareVersion','matlabRelease','rawPath','finalPath', ...
    'trajectory','baseline','metrics','constraints','collision','diagnostics'};
if ~isstruct(result) || ~isscalar(result) || ~all(isfield(result, required))
    error('RobotTrajectoryLab:InvalidResult', 'Result structure is incomplete.');
end
if ~isequal(result.schemaVersion, 1)
    error('RobotTrajectoryLab:InvalidResult', 'Unsupported result schemaVersion.');
end
for field = {'id','kind','algorithm','status','message','createdAt','softwareVersion','matlabRelease'}
    scalarText(result.(field{1}), field{1});
end
if ~ismember(char(result.status), {'success','no_path','invalid_input','validation_failed','error'})
    error('RobotTrajectoryLab:InvalidResult', 'Unknown result status.');
end
for field = {'trajectory','baseline','metrics','constraints','collision'}
    if ~isstruct(result.(field{1})) || ~isscalar(result.(field{1}))
        error('RobotTrajectoryLab:InvalidResult', '%s must be a scalar struct.', field{1});
    end
end
if isfield(result, 'environment') && (~isstruct(result.environment) || ~isscalar(result.environment))
    error('RobotTrajectoryLab:InvalidResult', 'environment must be a scalar struct.');
end
if ~(iscellstr(result.diagnostics) || (isstring(result.diagnostics) && all(~ismissing(result.diagnostics), 'all')))
    error('RobotTrajectoryLab:InvalidResult', 'diagnostics must contain text messages.');
end
assertPlainData(result);
end
