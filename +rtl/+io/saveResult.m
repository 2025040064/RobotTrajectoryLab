function saveResult(result, path)
%SAVERESULT 保存成功或失败结果，避免持久化运行时对象。
validateResultData(result);
if ~isfield(result, 'environment')
    result.environment = rtl.io.environmentInfo();
end
writeMat(path, 'result', result);
end
