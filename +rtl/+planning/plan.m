function result = plan(request)
%PLAN 统一的无界面规划入口；错误返回明确状态和诊断。
try
    if ~isstruct(request) || ~isscalar(request) || ...
            ~all(isfield(request,{'kind','algorithm','start','goal','options','seed'}))
        error('RobotTrajectoryLab:InvalidInput','Incomplete planning request.');
    end
    validateattributes(request.seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
    switch request.kind
        case 'arm'
            result = rtl.planning.planArm(request);
        case 'mobile'
            result = rtl.planning.planMobile(request);
        otherwise
            error('RobotTrajectoryLab:InvalidInput','Unknown robot kind.');
    end
catch exception
    fallback = struct('kind','unknown','algorithm','unknown');
    if isstruct(request) && isscalar(request)
        if isfield(request,'kind'), fallback.kind=request.kind; end
        if isfield(request,'algorithm'), fallback.algorithm=request.algorithm; end
    end
    result = rtl.newResult(fallback);
    result.request = request;
    result.status = 'invalid_input';
    if ~startsWith(exception.identifier,'RobotTrajectoryLab:') && ...
            ~startsWith(exception.identifier,'MATLAB:')
        result.status = 'error';
    end
    result.message = exception.message;
    result.diagnostics = {getReport(exception,'extended','hyperlinks','off')};
end
end
