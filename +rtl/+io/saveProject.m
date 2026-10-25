function saveProject(project, path)
%SAVEPROJECT 保存 schemaVersion=1 的普通项目结构。
validateProjectData(project);
writeMat(path, 'project', project);
end
