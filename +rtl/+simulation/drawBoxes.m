function handles = drawBoxes(ax,boxes)
%DRAWBOXES 将中心/尺寸表渲染为箱体，与碰撞场景使用同一参数。
faces=[1 2 3 4;5 6 7 8;1 2 6 5;2 3 7 6;3 4 8 7;4 1 5 8];
signs=[-1 -1 -1;1 -1 -1;1 1 -1;-1 1 -1;-1 -1 1;1 -1 1;1 1 1;-1 1 1];
handles=gobjects(size(boxes,1),1);
for k=1:size(boxes,1)
    vertices=signs.*(boxes(k,4:6)/2)+boxes(k,1:3);
    handles(k)=patch(ax,'Vertices',vertices,'Faces',faces, ...
        'FaceColor',[0.48 0.57 0.7],'FaceAlpha',0.7,'EdgeColor',[0.3 0.4 0.53]);
end
end
