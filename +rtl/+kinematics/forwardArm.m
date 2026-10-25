function tcp = forwardArm(robot,q,endEffector)
%FORWARDARM 关节样本为 6×N，返回基坐标系下的 TCP 位置 3×N，单位米。
validateattributes(q,{'numeric'},{'real','finite','2d','nrows',6});
tcp = zeros(3,size(q,2));
for index = 1:size(q,2)
    transform = getTransform(robot,q(:,index)',endEffector);
    tcp(:,index) = transform(1:3,4);
end
end
