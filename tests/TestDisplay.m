classdef TestDisplay < matlab.unittest.TestCase
    methods (Test)
        function labelsUnitsMissingValuesAndBaseline(testCase)
            r=rtl.newResult(struct('kind','arm','algorithm','quintic'));
            r.metrics=struct('motionDuration_s',2,'minimumObstacleSeparation_m',NaN);
            r.baseline=struct('metrics',struct('motionDuration_s',3));
            t=rtl.app.metricDisplay(r);
            testCase.verifyEqual(t.Metric,["运动时间";"采样最小障碍间距"]);
            testCase.verifyEqual(t.Baseline,["3";"—"]);
            testCase.verifyEqual(t.Current,["2";"无可用值"]);
            testCase.verifyEqual(t.Unit,["s";"m"]);
        end
    end
end
