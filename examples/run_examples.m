function outputs = run_examples()
%RUN_EXAMPLES 从可复现默认输入生成真实结果，不依赖 GUI。
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
project=rtl.defaultProject();
outputs.arm=rtl.planning.plan(project.arm);
assert(strcmp(outputs.arm.status,'success'),outputs.arm.message);
project.arm.options.scaleTime=true;
outputs.armScaled=rtl.planning.plan(project.arm);
assert(strcmp(outputs.armScaled.status,'success'),outputs.armScaled.message);
outputs.mobile=rtl.planning.plan(project.mobile);
assert(strcmp(outputs.mobile.status,'success'),outputs.mobile.message);
names=fieldnames(outputs);
for k=1:numel(names)
    rtl.io.exportResult(outputs.(names{k}),fullfile(root,'results','examples',names{k}));
end
rtl.io.saveProject(project,fullfile(root,'experiments','example_project.mat'));
fprintf('Three reproducible examples exported to results/examples.\n');
end
