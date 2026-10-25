classdef TestIO < matlab.unittest.TestCase
    properties
        Folder
    end

    methods (TestMethodSetup)
        function createFolder(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            folder = fullfile(root, 'results', 'validation', 'tmp', 'test_io');
            if ~isfolder(folder), mkdir(folder); end
            testCase.Folder = tempname(folder);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() cleanTestFolder(testCase.Folder, folder));
        end
    end

    methods (Test)
        function projectRoundTripAndCreateDirectory(testCase)
            project = rtl.defaultProject();
            project.name = '中文实验项目';
            project.mobile.map.originXY_m = [-3 8];
            path = fullfile(testCase.Folder, 'nested', 'project.mat');
            rtl.io.saveProject(project, path);
            testCase.verifyEqual(rtl.io.loadProject(path), project);
        end

        function rejectUnknownSchema(testCase)
            project = rtl.defaultProject();
            project.schemaVersion = 2;
            path = fullfile(testCase.Folder, 'bad.mat');
            save(path, 'project');
            testCase.verifyError(@() rtl.io.loadProject(path), 'RobotTrajectoryLab:InvalidProject');
            testCase.verifyError(@() rtl.io.saveProject(project, path), 'RobotTrajectoryLab:InvalidProject');
        end

        function maximumSmoothingIterationsRoundTrip(testCase)
            project = rtl.defaultProject();
            project.mobile.options.smoothIterations = 4;
            path = fullfile(testCase.Folder, 'four_iterations.mat');
            rtl.io.saveProject(project, path);
            restored = rtl.io.loadProject(path);
            testCase.verifyEqual(restored.mobile.options.smoothIterations, 4);
            testCase.verifyEqual(restored, project);
            project.mobile.options.smoothIterations = 5;
            testCase.verifyError(@() rtl.io.saveProject(project, path), ...
                'RobotTrajectoryLab:InvalidProject');
        end

        function rejectIncompleteAndMalformedProject(testCase)
            project = rtl.defaultProject();
            project.arm.options = rmfield(project.arm.options, 'samplePeriod_s');
            testCase.verifyError(@() rtl.io.saveProject(project, fullfile(testCase.Folder, 'bad.mat')), ...
                'RobotTrajectoryLab:InvalidProject');
            project = rtl.defaultProject();
            project.mobile.goal = [0 3];
            testCase.verifyError(@() rtl.io.saveProject(project, fullfile(testCase.Folder, 'bad.mat')), ...
                'RobotTrajectoryLab:InvalidProject');
            project = rtl.defaultProject();
            project.arm.options.velocityLimits(2) = NaN;
            testCase.verifyError(@() rtl.io.saveProject(project, fullfile(testCase.Folder, 'bad.mat')), ...
                'RobotTrajectoryLab:InvalidProject');
            project = rtl.defaultProject();
            project.mobile.map.rectangles = [1 1 1000 2];
            testCase.verifyError(@() rtl.io.saveProject(project, fullfile(testCase.Folder, 'bad.mat')), ...
                'RobotTrajectoryLab:InvalidProject');
        end

        function rejectRuntimeObject(testCase)
            project = rtl.defaultProject();
            project.runtime = @sin;
            testCase.verifyError(@() rtl.io.saveProject(project, fullfile(testCase.Folder, 'object.mat')), ...
                'RobotTrajectoryLab:NonSerializableData');
        end

        function armResultAndCsvRoundTrip(testCase)
            result = armResult();
            files = rtl.io.exportResult(result, fullfile(testCase.Folder, 'arm'));
            reloaded = rtl.io.loadResult(files.mat);
            testCase.verifyEqual(reloaded, result);
            trajectory = readtable(files.trajectory);
            testCase.verifyEqual(trajectory.time_s, result.trajectory.t.');
            testCase.verifyEqual(trajectory.q2_rad, result.trajectory.q(2, :).');
            testCase.verifyEqual(trajectory.qd6_rad_s, result.trajectory.qd(6, :).');
            testCase.verifyEqual(trajectory.qdd1_rad_s2, result.trajectory.qdd(1, :).');
            testCase.verifyEqual(trajectory.tcp_z_m, result.trajectory.tcp(3, :).');
            summary = readtable(files.summary, 'TextType', 'string');
            testCase.verifyEqual(summary.TextValue(summary.Key == "status"), "success");
            testCase.verifyEqual(summary.NumericValue(summary.Key == "seed"), result.request.seed);
            testCase.verifyTrue(any(summary.Key == "architecture"));
        end

        function mobileCsvRoundTrip(testCase)
            project = rtl.defaultProject();
            result = rtl.newResult(project.mobile);
            result.status = 'success';
            result.trajectory = struct('t', [0 1 2], 'position', [1 2 3; 2 3 4], 'yaw', [0 0.5 1]);
            result.metrics = struct('pathLength_m', 2.82842712474619, 'referenceTime_s', 2);
            files = rtl.io.exportResult(result, fullfile(testCase.Folder, 'mobile'));
            trajectory = readtable(files.trajectory);
            testCase.verifyEqual(trajectory.Properties.VariableNames, {'time_s','x_m','y_m','yaw_rad'});
            testCase.verifyEqual(trajectory.x_m, [1; 2; 3]);
            testCase.verifyEqual(trajectory.yaw_rad, [0; 0.5; 1]);
            loaded = rtl.io.loadResult(files.mat);
            testCase.verifyEqual(loaded.request, result.request);
            testCase.verifyTrue(isfield(loaded, 'environment'));
        end

        function failedResultStillSaved(testCase)
            project = rtl.defaultProject();
            result = rtl.newResult(project.mobile);
            result.status = 'no_path';
            result.message = '没有安全路径';
            result.diagnostics = {'Blocked by obstacles.'};
            files = rtl.io.exportResult(result, fullfile(testCase.Folder, 'failed'));
            testCase.verifyEmpty(files.trajectory);
            testCase.verifyTrue(isfile(files.mat));
            testCase.verifyTrue(isfile(files.summary));
            loaded = rtl.io.loadResult(files.mat);
            testCase.verifyEqual(loaded.status, 'no_path');
            testCase.verifyEqual(loaded.message, result.message);
            result.trajectory = struct('t', [0 1], 'position', [1 2]);
            files = rtl.io.exportResult(result, fullfile(testCase.Folder, 'partial'));
            testCase.verifyEmpty(files.trajectory);
        end

        function invalidResultCannotMasqueradeAsSuccess(testCase)
            result = armResult();
            result.trajectory.q = zeros(5, 3);
            testCase.verifyError(@() rtl.io.exportResult(result, testCase.Folder), ...
                'RobotTrajectoryLab:InvalidTrajectory');
            result = armResult();
            result.schemaVersion = 99;
            testCase.verifyError(@() rtl.io.saveResult(result, fullfile(testCase.Folder, 'bad.mat')), ...
                'RobotTrajectoryLab:InvalidResult');
        end

        function metricUnitsAndVectorValues(testCase)
            result = struct('metrics', struct('motionTime_s', 3, ...
                'peakVelocity_rad_s', [1 2], 'peakAcceleration_rad_s2', 4, ...
                'nested', struct('distance_m', 8)));
            metrics = rtl.io.metricTable(result);
            testCase.verifyEqual(height(metrics), 5);
            testCase.verifyEqual(metrics.Unit(metrics.Metric == "motionTime_s"), "s");
            testCase.verifyEqual(metrics.Value(metrics.Metric == "peakVelocity_rad_s(2)"), 2);
            testCase.verifyEqual(metrics.Unit(metrics.Metric == "peakAcceleration_rad_s2"), "rad/s^2");
            testCase.verifyEqual(metrics.Unit(metrics.Metric == "nested.distance_m"), "m");
        end

        function metricJerkIntegralAndCountUnits(testCase)
            result = struct('metrics', struct('jerk_rad_s3', 3, ...
                'energy_rad2_s5', 4, 'count_count', 5));
            metrics = rtl.io.metricTable(result);
            testCase.verifyEqual(metrics.Unit(metrics.Metric == "jerk_rad_s3"), "rad/s^3");
            testCase.verifyEqual(metrics.Unit(metrics.Metric == "energy_rad2_s5"), "rad^2/s^5");
            testCase.verifyEqual(metrics.Unit(metrics.Metric == "count_count"), "count");
        end

        function logSavedInProjectAndOneLinePerMessage(testCase)
            rtl.io.appendLog(testCase.Folder, sprintf('Planning started\nrequest omitted.'), 'INFO');
            logs = dir(fullfile(testCase.Folder, 'logs', '*.log'));
            testCase.verifyNumElements(logs, 1);
            content = fileread(fullfile(logs(1).folder, logs(1).name));
            testCase.verifyTrue(contains(content, '[INFO]'));
            testCase.verifyEqual(count(string(content), newline), 1);
            testCase.verifyTrue(contains(content, 'Planning started request omitted.'));
        end
    end
end

function cleanTestFolder(path, expectedParent)
% 仅递归删除由本测试在固定项目目录下创建的唯一子目录。
if ~strcmp(fileparts(path), expectedParent) || ~startsWith(path, [expectedParent filesep])
    error('RobotTrajectoryLab:UnsafeCleanup', 'Refusing to remove a folder outside the test temporary directory.');
end
if isfolder(path), rmdir(path, 's'); end
end

function result = armResult()
project = rtl.defaultProject();
result = rtl.newResult(project.arm);
result.status = 'success';
result.environment = rtl.io.environmentInfo();
result.trajectory = struct('t', [0 1 2], 'q', reshape(1:18, 6, 3), ...
    'qd', reshape(21:38, 6, 3), 'qdd', reshape(41:58, 6, 3), 'tcp', reshape(1:9, 3, 3));
result.metrics = struct('motionTime_s', 2, 'computationTime_s', 0.125);
result.baseline = struct('metrics', struct('motionTime_s', 3));
end
