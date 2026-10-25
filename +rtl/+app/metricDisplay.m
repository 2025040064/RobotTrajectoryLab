function display = metricDisplay(result)
%METRICDISPLAY 仅界面翻译；持久化与 CSV 保持稳定的英文数值字段。
current=rtl.io.metricTable(result);
baseline=rtl.io.metricTable(struct('metrics',struct()));
if isfield(result.baseline,'metrics'), baseline=rtl.io.metricTable(result.baseline); end
count=height(current); labels=strings(count,1); before=strings(count,1); after=strings(count,1);
for k=1:count
    labels(k)=translate(current.Metric(k));
    match=find(baseline.Metric==current.Metric(k),1);
    before(k)="—";
    if ~isempty(match), before(k)=formatValue(baseline.Value(match)); end
    after(k)=formatValue(current.Value(k));
end
display=table(labels,before,after,current.Unit,'VariableNames',{'Metric','Baseline','Current','Unit'});
end

function text=formatValue(value)
if isnan(value), text="无可用值";
elseif isinf(value), text="无有限值";
else, text=string(sprintf('%.5g',value)); end
end

function text=translate(field)
names={ 'motionDuration_s','运动时间'; 'jointPathLength_rad','关节路径长度'; ...
    'tcpPathLength_m','末端路径长度'; 'peakJointVelocity_rad_s','最大关节速度'; ...
    'peakJointAcceleration_rad_s2','最大关节加速度'; 'peakJointJerk_rad_s3','最大关节冲击度'; ...
    'squaredJerkIntegral_rad2_s5','冲击度平方积分'; 'minimumObstacleSeparation_m','采样最小障碍间距'; ...
    'trajectoryGenerationTime_s','轨迹生成耗时'; 'collisionCheckTime_s','碰撞检查耗时'; ...
    'timeScalingTime_s','时间缩放耗时'; 'planningTime_s','规划计算耗时'; ...
    'pathLength_m','路径长度'; 'referenceTravelTime_s','参考回放时间'; ...
    'referenceSpeed_m_s','参考回放速度'; 'minClearanceLowerBound_m','最小净空下界'; ...
    'totalTurningAngle_rad','累计转角'; 'pathPointCount_count','路径点数'; ...
    'astarSearchCost_m','A* 搜索代价'; 'astarNodesExplored_count','A* 展开节点数'; ...
    'mapBuildTime_s','安全地图构建耗时'; 'processingTime_s','路径处理耗时'; ...
    'smoothingAccepted_count','圆角是否接纳'};
index=find(strcmp(names(:,1),field),1);
if isempty(index), text=field; else, text=string(names{index,2}); end
end
