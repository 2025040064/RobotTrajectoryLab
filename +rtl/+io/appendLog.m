function appendLog(root, message, level)
%APPENDLOG 将不含请求正文的运行消息追加到项目目录的 logs 中。
if nargin < 3, level = 'INFO'; end
root = scalarText(root, 'root');
message = scalarText(message, 'message');
level = upper(scalarText(level, 'level'));
if ~ismember(level, {'INFO', 'WARN', 'ERROR', 'DEBUG'})
    error('RobotTrajectoryLab:InvalidInput', 'Unknown log level.');
end
folder = fullfile(root, 'logs');
if ~isfolder(folder), mkdir(folder); end
stamp = datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''');
day = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd'));
file = fullfile(folder, [day '.log']);
[fid, detail] = fopen(file, 'a', 'n', 'UTF-8');
if fid < 0, error('RobotTrajectoryLab:FileWriteFailed', '%s', detail); end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
% 一条消息一行，避免换行将原始内容伪装成另一条日志。
message = regexprep(message, '[\r\n]+', ' ');
fprintf(fid, '%s [%s] %s\n', char(stamp), level, message);
end
