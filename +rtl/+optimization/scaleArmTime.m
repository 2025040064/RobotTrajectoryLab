function report = scaleArmTime(difference,duration,velocityLimits,accelerationLimits,enabled)
%SCALEARMTIME 固定同步五次曲线的解析时间缩放，不改变几何路径。
requiredVelocity = 15*abs(difference)./(8*velocityLimits);
requiredAcceleration = sqrt(10*sqrt(3)*abs(difference)./(3*accelerationLimits));
required = max([requiredVelocity requiredAcceleration]);
selected = duration;
if enabled && any(difference ~= 0)
    selected = max(0.1,required*(1+1e-9));
end
report = struct('requestedDuration_s',duration,'requiredDuration_s',required, ...
    'selectedDuration_s',selected,'wasScaled',selected ~= duration, ...
    'minimumNumericalDuration_s',0.1,'method','fixed_path_quintic_time_scaling');
end
