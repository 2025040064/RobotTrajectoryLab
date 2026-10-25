classdef TestMobile < matlab.unittest.TestCase
    %TESTMOBILE 官方搜索器之外独立验证地图、路径和安全边界。
    methods (Test)
        function coordinateRoundTrip(testCase)
            spec = TestMobile.emptyMap(3,7,0.2);
            spec.originXY_m = [-1 2];
            [map,raw] = rtl.planning.buildMap(spec);
            cells = [1 1; 1 7; 3 1; 3 7; 2 4];
            xy = grid2world(map,cells);
            testCase.verifyEqual(xy(1,:),[-0.9 2.5],'AbsTol',1e-12);
            testCase.verifyEqual(xy(4,:),[0.3 2.1],'AbsTol',1e-12);
            testCase.verifyEqual(world2grid(map,xy),cells);
            testCase.verifySize(raw,[3 7]);
            testCase.verifyFalse(any(raw,'all'));
        end

        function emptyMapHasShortestFourNeighborCost(testCase)
            request = TestMobile.request();
            request.start = [3 3];
            request.goal = [12 15];
            result = rtl.planning.planMobile(request);
            expected = sum(abs(request.goal-request.start))*request.map.cellSize_m;
            testCase.verifyEqual(result.status,'success');
            testCase.verifyEqual(result.baseline.metrics.pathLength_m,expected,'AbsTol',1e-10);
            testCase.verifyEqual(result.metrics.astarSearchCost_m,expected,'AbsTol',1e-10);
            testCase.verifyTrue(result.collision.isCollisionFree);
            testCase.verifyEqual(result.finalPath([1 end],:),result.rawPath([1 end],:));
            testCase.verifyEqual(result.trajectory.t(end), ...
                result.metrics.pathLength_m/request.options.referenceSpeed_m_s,'AbsTol',1e-10);
        end

        function searchCostKeepsWorldUnitsAtDifferentResolution(testCase)
            request = TestMobile.request();
            request.map.cellSize_m = 0.25;
            request.start = [3 3];
            request.goal = [12 15];
            result = rtl.planning.planMobile(request);
            expected = sum(abs(request.goal-request.start))*request.map.cellSize_m;
            testCase.assertEqual(result.status,'success');
            testCase.verifyEqual(result.metrics.astarSearchCost_m,expected,'AbsTol',1e-10);
            testCase.verifyEqual(result.metrics.astarSearchCost_m, ...
                result.baseline.metrics.pathLength_m,'AbsTol',1e-10);
        end

        function sealedWallHasNoPath(testCase)
            request = TestMobile.request();
            request.map.rectangles = [1 10 20 1];
            request.start = [10 4];
            request.goal = [10 17];
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'no_path');
            testCase.verifyEmpty(result.finalPath);
            testCase.verifyEmpty(fieldnames(result.trajectory));
        end

        function illegalEndpointsAreRejected(testCase)
            request = TestMobile.request();
            request.start = [0 4];
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'invalid_input');
            request = TestMobile.request();
            request.goal = [3.5 4];
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'invalid_input');
            request = TestMobile.request();
            request.map.rectangles = [3 3 2 2];
            request.start = [3 3];
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'invalid_input');
        end

        function identicalEndpointsHaveZeroLength(testCase)
            request = TestMobile.request();
            request.goal = request.start;
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'success');
            testCase.verifySize(result.finalPath,[1 2]);
            testCase.verifyEqual(result.metrics.pathLength_m,0);
            testCase.verifyEqual(result.trajectory.t,0);
        end

        function segmentMiddleCannotCrossObstacle(testCase)
            spec = TestMobile.emptyMap(10,10,1);
            spec.rectangles = [5 6 1 1];
            [map,raw] = rtl.planning.buildMap(spec);
            report = rtl.planning.checkMobilePath([2.5 5.5; 8.5 5.5],map,raw,0,0);
            testCase.verifyFalse(report.isCollisionFree);
            testCase.verifyEqual(report.invalidSegment,1);
            testCase.verifyEqual(report.reason,'obstacle');
        end

        function cellCornerAccountsForFullObstacleArea(testCase)
            spec = TestMobile.emptyMap(10,10,1);
            spec.rectangles = [5 6 1 1];
            [map,raw] = rtl.planning.buildMap(spec);
            report = rtl.planning.checkMobilePath([6.05 6.05],map,raw,0.1,0);
            testCase.verifyFalse(report.isCollisionFree);
            testCase.verifyEqual(report.reason,'obstacle');
        end

        function boundaryIncludesRobotFootprint(testCase)
            spec = TestMobile.emptyMap(10,10,1);
            [map,raw] = rtl.planning.buildMap(spec);
            touching = rtl.planning.checkMobilePath([0.1 2; 0.1 8],map,raw,0.1,0);
            free = rtl.planning.checkMobilePath([0.1001 2; 0.1001 8],map,raw,0.1,0);
            testCase.verifyFalse(touching.isCollisionFree);
            testCase.verifyEqual(touching.reason,'boundary');
            testCase.verifyTrue(free.isCollisionFree);
        end

        function unsafeSmoothingFallsBack(testCase)
            spec = TestMobile.emptyMap(10,10,1);
            spec.rectangles = [5 6 1 1];
            [map,raw] = rtl.planning.buildMap(spec);
            path = [3.5 5.5; 5.5 6.4; 7.5 5.5];
            before = rtl.planning.checkMobilePath(path,map,raw,0,0);
            testCase.assertTrue(before.isCollisionFree);
            [processed,info] = rtl.optimization.processMobilePath(path,map,raw,0,0,2);
            testCase.verifyTrue(info.smoothingRejected);
            testCase.verifyFalse(info.smoothingAccepted);
            testCase.verifyEqual(processed,path,'AbsTol',1e-12);
            after = rtl.planning.checkMobilePath(processed,map,raw,0,0);
            testCase.verifyTrue(after.isCollisionFree);
        end

        function smoothingSupportsZeroAndFourIterations(testCase)
            spec = TestMobile.emptyMap(10,10,1);
            spec.rectangles = [5 6 1 1];
            [map,raw] = rtl.planning.buildMap(spec);
            path = [3.5 5.5; 5.5 7.5; 7.5 5.5];
            [withoutSmoothing,zeroInfo] = rtl.optimization.processMobilePath(path,map,raw,0,0,0);
            testCase.verifyEqual(withoutSmoothing,path);
            testCase.verifyFalse(zeroInfo.smoothingRequested);
            [smoothed,fourInfo] = rtl.optimization.processMobilePath(path,map,raw,0,0,4);
            testCase.verifyTrue(fourInfo.smoothingAccepted);
            testCase.verifyEqual(fourInfo.iterations,4);
            testCase.verifyGreaterThan(size(smoothed,1),size(path,1));
            testCase.verifyEqual(smoothed([1 end],:),path([1 end],:));
            report = rtl.planning.checkMobilePath(smoothed,map,raw,0,0);
            testCase.verifyTrue(report.isCollisionFree);
            for iterations = [0 4]
                request = TestMobile.request();
                request.options.smoothIterations = iterations;
                result = rtl.planning.planMobile(request);
                testCase.verifyEqual(result.status,'success');
            end
            request.options.smoothIterations = 5;
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'invalid_input');
        end

        function repeatedPlanningIsDeterministic(testCase)
            project = rtl.defaultProject();
            first = rtl.planning.planMobile(project.mobile);
            second = rtl.planning.planMobile(project.mobile);
            testCase.assertEqual(first.status,'success');
            testCase.verifyEqual(second.status,'success');
            testCase.verifyEqual(first.rawPath,second.rawPath);
            testCase.verifyEqual(first.finalPath,second.finalPath);
            % 独立断言检查足迹外接圆，不复用产品碰撞检查函数。
            [map,raw] = rtl.planning.buildMap(project.mobile.map);
            [rows,cols] = find(raw);
            centers = grid2world(map,[rows cols]);
            threshold = project.mobile.options.robotRadius_m + ...
                project.mobile.options.safetyMargin_m + project.mobile.map.cellSize_m/sqrt(2);
            for index = 1:size(first.finalPath,1)-1
                a = first.finalPath(index,:);
                b = first.finalPath(index+1,:);
                vector = b-a;
                fractions = max(0,min(1,((centers-a)*vector')/sum(vector.^2)));
                distances = sqrt(sum((centers-(a+fractions.*vector)).^2,2));
                testCase.verifyGreaterThan(min(distances),threshold);
            end
        end

        function invalidMapAndSpeedAreRejected(testCase)
            request = TestMobile.request();
            request.map.rectangles = [19 19 4 4];
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'invalid_input');
            request = TestMobile.request();
            request.options.referenceSpeed_m_s = 0;
            result = rtl.planning.planMobile(request);
            testCase.verifyEqual(result.status,'invalid_input');
        end
    end

    methods (Static, Access = private)
        function spec = emptyMap(rows,cols,cellSize)
            spec = struct('rows',rows,'cols',cols,'cellSize_m',cellSize, ...
                'originXY_m',[0 0],'rectangles',zeros(0,4));
        end

        function request = request()
            project = rtl.defaultProject();
            request = project.mobile;
            request.map = TestMobile.emptyMap(20,20,0.1);
            request.start = [4 4];
            request.goal = [16 16];
            request.options.robotRadius_m = 0;
            request.options.safetyMargin_m = 0;
        end
    end
end
