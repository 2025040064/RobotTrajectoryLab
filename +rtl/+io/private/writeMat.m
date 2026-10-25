function writeMat(path, name, value)
%WRITEMAT 同目录临时文件写入完成后再替换目标。
path = scalarText(path, 'path');
if isempty(path), error('RobotTrajectoryLab:InvalidInput', 'File path cannot be empty.'); end
assertPlainData(value);
folder = fileparts(path);
if isempty(folder), folder = pwd; end
if ~isfolder(folder), mkdir(folder); end
temporary = [tempname(folder) '.mat'];
cleaner = onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
payload = struct();
payload.(name) = value;
save(temporary, '-struct', 'payload', '-v7');
[ok, detail] = movefile(temporary, path, 'f');
if ~ok, error('RobotTrajectoryLab:FileWriteFailed', '%s', detail); end
end

function removeTemporary(path)
if isfile(path), delete(path); end
end
