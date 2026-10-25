classdef TestApp < matlab.unittest.TestCase
    properties
        App
        Folder
    end
    methods (TestMethodSetup)
        function createApplication(testCase)
            root=fileparts(fileparts(mfilename('fullpath')));
            addpath(root);
            testCase.App=main(Visible="off");
            parent=fullfile(root,'results','validation','tmp','test_app');
            if ~isfolder(parent), mkdir(parent); end
            testCase.Folder=tempname(parent); mkdir(testCase.Folder);
        end
    end
    methods (TestMethodTeardown)
        function releaseApplication(testCase)
            if ~isempty(testCase.App)&&isvalid(testCase.App), delete(testCase.App); end
            if ~isempty(testCase.Folder)&&isfolder(testCase.Folder)
                parent=fileparts(testCase.Folder);
                root=fileparts(fileparts(mfilename('fullpath')));
                if strcmp(parent,fullfile(root,'results','validation','tmp','test_app'))
                    rmdir(testCase.Folder,'s');
                end
            end
        end
    end
    methods (Test)
        function initializationAndResponsivePages(testCase)
            app=testCase.App;
            testCase.verifyTrue(isvalid(app.Figure));
            pages={'home','model','planning','simulation','analysis','history'};
            for screenSize=[1280 1920;800 1080]
                app.Figure.Position=[50 50 screenSize'];
                for k=1:numel(pages), app.selectPage(pages{k}); drawnow; end
                expected=app.Controls.Content.InnerPosition(3:4);
                for panel=app.Controls.PageHost.Children'
                    testCase.verifyEqual(panel.Position(3:4),expected,'AbsTol',2);
                end
            end
            testCase.verifyEqual(char(app.Controls.Kind.Value),'arm');
            testCase.verifyEqual(size(app.Controls.Joints.Data),[6 5]);
        end
        function armWorkflowOptimizationPlaybackAndExport(testCase)
            app=testCase.App; result=app.runPlanning();
            testCase.assertEqual(result.status,'success',result.message);
            scaled=app.applyOptimization();
            testCase.assertEqual(scaled.status,'success',scaled.message);
            testCase.verifyLessThanOrEqual(scaled.metrics.motionDuration_s,result.metrics.motionDuration_s);
            app.selectPage('simulation'); app.seek(scaled.trajectory.t(end));
            testCase.verifyEqual(app.Controls.Progress.Value,1,'AbsTol',1e-12);
            app.play(); testCase.verifyEqual(app.PlaybackTimer.Running,'on');
            app.pause(); testCase.verifyEqual(app.PlaybackTimer.Running,'off');
            app.resetPlayback(); testCase.verifyEqual(app.PlaybackTime,0);
            files=app.exportCurrent(testCase.Folder);
            testCase.verifyTrue(isfile(files.mat));
            testCase.verifyTrue(isfile(files.trajectory));
            loaded=rtl.io.loadResult(files.mat);
            testCase.verifyEqual(loaded.trajectory.q,scaled.trajectory.q);
        end
        function mobileWorkflowSaveReloadAndLastFrame(testCase)
            app=testCase.App; app.setKind('mobile');
            result=app.runPlanning(); testCase.assertEqual(result.status,'success',result.message);
            app.selectPage('simulation'); app.seek(result.trajectory.t(end));
            frame=rtl.simulation.sampleFrame(result,result.trajectory.t(end));
            testCase.verifyEqual(frame.position,result.finalPath(end,:),'AbsTol',1e-10);
            path=fullfile(testCase.Folder,'project.mat'); app.saveProject(path); app.openProject(path);
            testCase.verifyTrue(app.IsStale);
            app.loadHistory(1); testCase.verifyFalse(app.IsStale);
            testCase.verifyEqual(app.CurrentResult.finalPath,result.finalPath);
            files=app.exportCurrent(testCase.Folder);
            csv=readtable(files.trajectory);
            testCase.verifyEqual(height(csv),numel(result.trajectory.t));
        end
        function editedParametersInvalidateResults(testCase)
            app=testCase.App; r=app.runPlanning(); testCase.assertEqual(r.status,'success');
            request=app.Project.arm; request.options.duration_s=4;
            app.setRequest(request); testCase.verifyTrue(app.IsStale);
            testCase.verifyEqual(char(app.Controls.Play.Enable),'off');
            testCase.verifyError(@()app.exportCurrent(testCase.Folder),'RobotTrajectoryLab:NoCurrentResult');
        end
        function illegalInputIsVisibleAndSavedAsFailure(testCase)
            app=testCase.App; request=app.Project.arm; request.options.duration_s=-1;
            app.setRequest(request); r=app.runPlanning();
            testCase.verifyEqual(r.status,'invalid_input');
            testCase.verifyNotEmpty(app.Controls.PlanningNotes.Value);
            testCase.verifyFalse(app.IsBusy);
            testCase.verifyEqual(char(app.Controls.Play.Enable),'off');
        end
        function closingApplicationReleasesTimer(testCase)
            app=testCase.App; timerHandle=app.PlaybackTimer; figureHandle=app.Figure;
            delete(app);
            testCase.verifyFalse(isvalid(timerHandle)); testCase.verifyFalse(isvalid(figureHandle));
        end
        function malformedMapCellRollsBackVisibleParameters(testCase)
            app=testCase.App; app.setKind('mobile');
            original=app.Project.mobile;
            data=app.Controls.MapSettings.Data; data{1,2}='bad'; app.Controls.MapSettings.Data=data;
            app.Controls.MapSettings.CellEditCallback([],[]);
            testCase.verifyEqual(app.Controls.MapSettings.Data{1,2},original.map.rows);
            testCase.verifyEqual(app.Project.mobile,original);
        end
        function malformedFailureHistoryPreservesProject(testCase)
            app=testCase.App; original=app.Project;
            request=struct('kind','arm','algorithm','quintic');
            failed=rtl.planning.plan(request);
            path=fullfile(testCase.Folder,'failure.mat'); rtl.io.saveResult(failed,path);
            app.openResult(path);
            testCase.verifyEqual(app.Project,original);
            testCase.verifyEqual(numel(app.History),1);
        end
        function closeDuringPlanningStartupCancelsCleanly(testCase)
            app=testCase.App;
            closer=timer('StartDelay',0,'TimerFcn',@(~,~)delete(app));
            cleanup=onCleanup(@()delete(closer)); start(closer);
            result=app.runPlanning();
            testCase.verifyEmpty(result);
            testCase.verifyFalse(isvalid(app));
            clear cleanup
        end
        function switchingRobotClearsAnalysisTraces(testCase)
            app=testCase.App; r=app.runPlanning(); testCase.assertEqual(r.status,'success');
            app.applyOptimization(); app.setKind('mobile'); app.runPlanning(); app.selectPage('analysis');
            ax=app.Controls.AnalysisAxes;
            testCase.verifyEqual(numel(findall(ax(1),'Type','Line')),2);
            testCase.verifyEqual(ax(4).View,[0 90],'AbsTol',1e-10);
            testCase.verifyEqual(numel(app.Controls.Progress.MajorTicks),5);
            app.Figure.Position=[50 50 1280 800]; app.selectPage('model'); drawnow;
            testCase.verifyGreaterThanOrEqual(app.Controls.Obstacles.Position(4),100);
            app.Figure.Position=[10 10 1920 1080]; app.selectPage('analysis'); drawnow;
            bounds=ax(1).Parent.Position(3:4);
            for k=1:4
                box=ax(k).OuterPosition;
                testCase.verifyLessThanOrEqual(box(1)+box(3),bounds(1)+2);
                testCase.verifyLessThanOrEqual(box(2)+box(4),bounds(2)+2);
            end
        end
        function collisionFailureRemainsDiagnosable(testCase)
            app=testCase.App; request=app.Project.arm;
            request.options.boxes=[0 0 0 1 1 1]; app.setRequest(request);
            result=app.runPlanning();
            testCase.verifyEqual(result.status,'validation_failed');
            testCase.verifyTrue(result.collision.environmentCollision);
            testCase.verifyNotEmpty(app.Controls.PlanningNotes.Value);
            testCase.verifyEqual(char(app.Controls.Play.Enable),'off');
        end
    end
end
