function frame = sampleFrame(result,time_s)
%SAMPLEFRAME 播放和测试都使用保存的同一份轨迹，不重新规划。
validateattributes(time_s,{'numeric'},{'scalar','real','finite'});
trajectory=result.trajectory;
t=trajectory.t;
time_s=max(t(1),min(t(end),time_s));
if strcmp(result.kind,'arm')
    if numel(t)==1, q=trajectory.q(:,1)';
    else, q=interp1(t,trajectory.q',time_s,'linear'); end
    frame=struct('q',q);
else
    if numel(t)==1
        position=trajectory.position(:,1)'; yaw=trajectory.yaw(1);
    else
        position=interp1(t,trajectory.position',time_s,'linear');
        yaw=interp1(t,trajectory.yaw,time_s,'previous');
    end
    frame=struct('position',position,'yaw',yaw);
end
end
