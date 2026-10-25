classdef TestArm < matlab.unittest.TestCase
    %TESTARM 六自由度机械臂的数值正确性与约束验收。
    methods (Test)
        function officialModelHasSixJoints(testCase)
            robot = rtl.models.loadArm();
            testCase.verifyEqual(numel(homeConfiguration(robot)),6);
            testCase.verifyEqual(robot.DataFormat,'row');
            testCase.verifyTrue(any(strcmp(robot.BodyNames,'tool0')));
            limits = rtl.models.armPositionLimits(robot);
            testCase.verifySize(limits,[6 2]);
            testCase.verifyTrue(all(limits(:,1) < limits(:,2)));
        end

        function forwardMatchesIndependentChain(testCase)
            robot = rtl.models.loadArm();
            for index = 1:10
                q = 0.7*sin((1:6)*0.31 + index*0.2);
                actual = getTransform(robot,q,'tool0');
                reference = rtl.kinematics.forwardIndependent(robot,q,'tool0');
                testCase.verifyEqual(actual,reference,'AbsTol',1e-10);
                testCase.verifyEqual(actual(4,:),[0 0 0 1],'AbsTol',1e-12);
                rotation = actual(1:3,1:3);
                testCase.verifyEqual(rotation'*rotation,eye(3),'AbsTol',1e-10);
                testCase.verifyEqual(det(rotation),1,'AbsTol',1e-10);
            end
        end

        function jacobianMatchesCentralDifferences(testCase)
            robot = rtl.models.loadArm();
            step = 1e-6;
            for index = 1:10
                q = 0.7*sin((1:6)*0.31 + index*0.2);
                transform = getTransform(robot,q,'tool0');
                numeric = zeros(6,6);
                for joint = 1:6
                    offset = zeros(1,6);
                    offset(joint) = step;
                    plus = getTransform(robot,q + offset,'tool0');
                    minus = getTransform(robot,q - offset,'tool0');
                    numeric(4:6,joint) = (plus(1:3,4)-minus(1:3,4))/(2*step);
                    derivative = (plus(1:3,1:3)-minus(1:3,1:3))/(2*step);
                    skew = derivative*transform(1:3,1:3)';
                    skew = (skew-skew')/2;
                    numeric(1:3,joint) = [skew(3,2);skew(1,3);skew(2,1)];
                end
                official = geometricJacobian(robot,q,'tool0');
                testCase.verifyEqual(official(1:3,:),numeric(1:3,:),'AbsTol',1e-5);
                testCase.verifyEqual(official(4:6,:),numeric(4:6,:),'AbsTol',1e-5);
            end
        end

        function defaultExampleAndBoundaryConditions(testCase)
            project = rtl.defaultProject();
            result = rtl.planning.plan(project.arm);
            testCase.assertEqual(result.status,'success',result.message);
            trajectory = result.trajectory;
            testCase.verifyEqual(trajectory.q(:,1),project.arm.start','AbsTol',1e-10);
            testCase.verifyEqual(trajectory.q(:,end),project.arm.goal','AbsTol',1e-10);
            testCase.verifyEqual(trajectory.qd(:,[1 end]),zeros(6,2),'AbsTol',1e-9);
            testCase.verifyEqual(trajectory.qdd(:,[1 end]),zeros(6,2),'AbsTol',1e-9);
            testCase.verifyEqual(trajectory.t([1 end]),[0 project.arm.options.duration_s]);
            testCase.verifyLessThanOrEqual(max(diff(trajectory.t)), ...
                project.arm.options.samplePeriod_s + 1e-12);
            testCase.verifySize(trajectory.tcp,[3 numel(trajectory.t)]);
            testCase.verifyTrue(result.constraints.isSatisfied);
            testCase.verifyTrue(result.collision.isComplete);
            testCase.verifyTrue(result.collision.isCollisionFree);
        end

        function exactPeakCheckDoesNotDependOnSampleRate(testCase)
            project = rtl.defaultProject();
            request = project.arm;
            request.options.duration_s = 0.01;
            request.options.samplePeriod_s = 1;
            result = rtl.planning.plan(request);
            testCase.assertEqual(result.status,'validation_failed');
            testCase.verifySize(result.trajectory.q,[6 2]);
            difference = abs(request.goal-request.start);
            testCase.verifyEqual(result.constraints.peakVelocity_rad_s, ...
                15*difference/(8*request.options.duration_s),'RelTol',1e-12);
            testCase.verifyEqual(result.constraints.peakAcceleration_rad_s2, ...
                10*sqrt(3)*difference/(3*request.options.duration_s^2),'RelTol',1e-12);
            testCase.verifyFalse(result.constraints.isSatisfied);
        end

        function timeScalingSatisfiesLimitsAndPreservesPath(testCase)
            project = rtl.defaultProject();
            request = project.arm;
            request.options.duration_s = 0.1;
            request.options.scaleTime = true;
            result = rtl.planning.plan(request);
            testCase.assertEqual(result.status,'success',result.message);
            difference = abs(request.goal-request.start);
            required = max([15*difference./(8*request.options.velocityLimits), ...
                sqrt(10*sqrt(3)*difference./(3*request.options.accelerationLimits))]);
            testCase.verifyGreaterThanOrEqual(result.metrics.motionDuration_s,required);
            testCase.verifyLessThanOrEqual(result.metrics.motionDuration_s,required*(1+1e-6));
            testCase.verifyFalse(result.baseline.constraints.isSatisfied);
            testCase.verifyEqual(result.metrics.jointPathLength_rad, ...
                result.baseline.metrics.jointPathLength_rad,'AbsTol',1e-12);
            testCase.verifyEqual(result.metrics.tcpPathLength_m, ...
                result.baseline.metrics.tcpPathLength_m,'AbsTol',1e-12);
            testCase.verifyEqual(result.finalPath,result.rawPath,'AbsTol',1e-12);
            testCase.verifyEqual(result.trajectory.q(:,[1 end]), ...
                result.baseline.trajectory.q(:,[1 end]),'AbsTol',1e-10);
        end

        function shorteningTimeReportsIncreasedJerk(testCase)
            project = rtl.defaultProject();
            request = project.arm;
            request.options.duration_s = 5;
            request.options.scaleTime = true;
            result = rtl.planning.plan(request);
            testCase.assertEqual(result.status,'success',result.message);
            testCase.verifyLessThan(result.metrics.motionDuration_s, ...
                result.baseline.metrics.motionDuration_s);
            testCase.verifyGreaterThan(result.metrics.squaredJerkIntegral_rad2_s5, ...
                result.baseline.metrics.squaredJerkIntegral_rad2_s5);
        end

        function stationaryMotionIsFinite(testCase)
            project = rtl.defaultProject();
            request = project.arm;
            request.goal = request.start;
            request.options.scaleTime = true;
            result = rtl.planning.plan(request);
            testCase.assertEqual(result.status,'success',result.message);
            testCase.verifyEqual(result.metrics.motionDuration_s,request.options.duration_s);
            testCase.verifyEqual(result.metrics.jointPathLength_rad,0);
            testCase.verifyEqual(result.metrics.tcpPathLength_m,0,'AbsTol',1e-12);
            testCase.verifyEqual(result.trajectory.qd,zeros(size(result.trajectory.qd)), ...
                'AbsTol',1e-10);
            testCase.verifyEqual(result.trajectory.qdd,zeros(size(result.trajectory.qdd)), ...
                'AbsTol',1e-10);
            testCase.verifyEqual(result.metrics.squaredJerkIntegral_rad2_s5,0);
        end

        function environmentCollisionCannotBeFixedByTimeScaling(testCase)
            project = rtl.defaultProject();
            request = project.arm;
            request.options.boxes = [0 0 0 4 4 4];
            request.options.scaleTime = true;
            result = rtl.planning.plan(request);
            testCase.assertEqual(result.status,'validation_failed');
            testCase.verifyTrue(result.collision.environmentCollision);
            testCase.verifyFalse(result.collision.isCollisionFree);
            testCase.verifyTrue(result.collision.isComplete);
            testCase.verifyNotEmpty(result.collision.firstPairs);
            testCase.verifyFalse(result.constraints.isSatisfied);
        end

        function selfCollisionIsChecked(testCase)
            robot = rtl.models.loadArm();
            q = [0 0 pi 0 0 0];
            report = rtl.kinematics.checkArmPath(robot,q,q,0.02,zeros(0,6));
            testCase.verifyTrue(report.isComplete);
            testCase.verifyTrue(report.selfCollision);
            testCase.verifyFalse(report.isCollisionFree);
        end

        function missingMovingLinkGeometryIsNotCollisionFree(testCase)
            robot = copy(rtl.models.loadArm());
            for index = 1:numel(robot.Bodies)
                if ~strcmp(robot.Bodies{index}.Joint.Type,'fixed')
                    clearCollision(robot.Bodies{index});
                    break
                end
            end
            project = rtl.defaultProject();
            report = rtl.kinematics.checkArmPath(robot,project.arm.start, ...
                project.arm.goal,0.02,zeros(0,6));
            testCase.verifyFalse(report.isComplete);
            testCase.verifyFalse(report.isCollisionFree);
            testCase.verifyNotEmpty(report.missingBodies);
        end

        function collisionResolutionIsIndependentOfDuration(testCase)
            project = rtl.defaultProject();
            first = rtl.planning.plan(project.arm);
            request = project.arm;
            request.options.duration_s = 8;
            request.options.samplePeriod_s = 0.3;
            second = rtl.planning.plan(request);
            testCase.verifyEqual(first.collision.sampleCount,second.collision.sampleCount);
            testCase.verifyEqual(first.collision.isCollisionFree,second.collision.isCollisionFree);
            testCase.verifyLessThanOrEqual(first.collision.actualStep_rad,0.02+1e-12);
            testCase.verifyEqual(first.finalPath,second.finalPath,'AbsTol',1e-12);
        end

        function invalidInputsReturnExplicitStatus(testCase)
            project = rtl.defaultProject();
            invalid = cell(1,8);
            invalid{1}=project.arm; invalid{1}.start=[0 0];
            invalid{2}=project.arm; invalid{2}.goal(1)=NaN;
            invalid{3}=project.arm; invalid{3}.start(1)=1e6;
            invalid{4}=project.arm; invalid{4}.options.duration_s=0;
            invalid{5}=project.arm; invalid{5}.options.velocityLimits(2)=0;
            invalid{6}=project.arm; invalid{6}.options.boxes=[0 0 0 -1 1 1];
            invalid{7}=project.arm; invalid{7}.options.samplePeriod_s=1e-12;
            invalid{8}=project.arm; invalid{8}.options.collisionStep_rad=0;
            for index = 1:numel(invalid)
                result = rtl.planning.plan(invalid{index});
                testCase.verifyEqual(result.status,'invalid_input');
                testCase.verifyNotEmpty(result.message);
            end
        end

        function deterministicResultsSeparateMotionAndComputation(testCase)
            project = rtl.defaultProject();
            first = rtl.planning.plan(project.arm);
            second = rtl.planning.plan(project.arm);
            testCase.verifyEqual(first.trajectory,second.trajectory);
            testCase.verifyEqual(first.constraints,second.constraints);
            testCase.verifyEqual(first.collision,second.collision);
            testCase.verifyEqual(first.metrics.motionDuration_s,project.arm.options.duration_s);
            testCase.verifyGreaterThanOrEqual(first.metrics.planningTime_s,0);
            testCase.verifyGreaterThanOrEqual(first.metrics.collisionCheckTime_s,0);
            testCase.verifyGreaterThanOrEqual(first.metrics.trajectoryGenerationTime_s,0);
            testCase.verifyGreaterThanOrEqual(first.metrics.timeScalingTime_s,0);
        end
    end
end
