function info = environmentInfo()
%ENVIRONMENTINFO 记录可复现实验所需的版本信息，不包含本机路径。
products = ver;
toolboxes = repmat(struct('name', '', 'version', '', 'release', ''), numel(products), 1);
for index = 1:numel(products)
    toolboxes(index).name = products(index).Name;
    toolboxes(index).version = products(index).Version;
    toolboxes(index).release = products(index).Release;
end
info = struct('matlabVersion', version, 'matlabRelease', version('-release'), ...
    'architecture', computer('arch'), 'toolboxes', toolboxes);
end
