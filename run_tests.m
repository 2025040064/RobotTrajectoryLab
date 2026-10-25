function results = run_tests(options)
%RUN_TESTS 在真实 MATLAB 中运行并将报告保存在项目内。
arguments
    options.CoreOnly (1,1) logical = false
end
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','validation');
if ~isfolder(folder), mkdir(folder); end
logPath=fullfile(folder,'tests.log');
diary(logPath); cleanup=onCleanup(@()diary('off'));
fprintf('\nRobotTrajectoryLab validation: %s / %s\n',version,datestr(now,31));
if options.CoreOnly
    paths=fullfile(root,'tests',{'TestArm.m','TestMobile.m','TestIO.m'});
    results=runtests(paths);
else
    results=runtests(fullfile(root,'tests'),'IncludeSubfolders',true);
end
save(fullfile(folder,'test_results.mat'),'results');
summary=table(string({results.Name})',[results.Passed]',[results.Failed]', ...
    [results.Incomplete]',[results.Duration]', ...
    'VariableNames',{'Name','Passed','Failed','Incomplete','Duration_s'});
writetable(summary,fullfile(folder,'test_results.csv'));
disp(summary); assertSuccess(results);
clear cleanup
end
