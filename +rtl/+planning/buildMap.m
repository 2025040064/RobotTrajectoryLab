function [map,occupancy] = buildMap(mapSpec)
%BUILDMAP 矩形编辑源生成地图；第一行位于地图顶部，单位为米。
required = {'rows','cols','cellSize_m','originXY_m','rectangles'};
if ~isstruct(mapSpec) || ~isscalar(mapSpec) || ~all(isfield(mapSpec,required))
    error('RobotTrajectoryLab:InvalidMap','地图定义缺少必需字段。');
end
validateattributes(mapSpec.rows,{'numeric'},{'real','finite','scalar','integer','positive'});
validateattributes(mapSpec.cols,{'numeric'},{'real','finite','scalar','integer','positive'});
validateattributes(mapSpec.cellSize_m,{'numeric'},{'real','finite','scalar','positive'});
validateattributes(mapSpec.originXY_m,{'numeric'},{'real','finite','vector','numel',2});
rectangles = mapSpec.rectangles;
if ~isnumeric(rectangles) || ~isreal(rectangles) || size(rectangles,2) ~= 4 || ...
        ndims(rectangles) ~= 2 || any(~isfinite(rectangles),'all') || ...
        any(rectangles ~= round(rectangles),'all') || any(rectangles < 1,'all')
    error('RobotTrajectoryLab:InvalidMap','障碍矩形必须是 N×4 正整数 [row col height width]。');
end
if any(rectangles(:,1)+rectangles(:,3)-1 > mapSpec.rows) || ...
        any(rectangles(:,2)+rectangles(:,4)-1 > mapSpec.cols)
    error('RobotTrajectoryLab:InvalidMap','障碍矩形超出地图边界。');
end
occupancy = false(mapSpec.rows,mapSpec.cols);
for index = 1:size(rectangles,1)
    rectangle = rectangles(index,:);
    occupancy(rectangle(1):rectangle(1)+rectangle(3)-1, ...
        rectangle(2):rectangle(2)+rectangle(4)-1) = true;
end
map = binaryOccupancyMap(occupancy,1/mapSpec.cellSize_m);
map.GridLocationInWorld = reshape(mapSpec.originXY_m,1,2);
end
