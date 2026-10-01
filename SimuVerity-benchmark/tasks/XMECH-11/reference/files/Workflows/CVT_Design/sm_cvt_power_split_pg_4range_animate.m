function sm_cvt_power_split_pg_4range_animate(HMPST,logsout_data,varargin)
% sm_cvt_power_split_pg_4range_animate  Animate simulation results from 
%                                       model sm_cvt_power_split_pg_4range.slx 

% Copyright 2023-2025 The MathWorks, Inc.

saveVideo    = false;
videoSpeedup = 1;
if(nargin>=3)
    saveVideo = varargin{1};
end
if(nargin>=4)
    videoSpeedup = varargin{2};
end

%% Plot current control settings

% Two sets of hardcoded values below are for targets,
% not needed for plotting actual results.
[~, ~, ax_sw] = cvtCalcSwashControl(...
    [0 3 6.4 14.2 30],...                  % tgtVSpdRanges...
    HMPST.Tire.Rad,...                     % rWhl
    HMPST.OutputTransferGearPair.Ratio,... % nGearCVTOut
    HMPST.Differential.Ratio,...           % nDiff
    HMPST.FinalDrive.Ratio,...             % nFinalDrive
    HMPST.Eng.wTarget,...                  % wEng
    HMPST.HydroUnit.Pump.SpeedLimit,...    % wPumpNom
    HMPST.HydroUnit.Pump.Disp /...         % nHSPumpMotor
    HMPST.HydroUnit.Motor.Disp,...
    0.7317,...                             % maxPumpDispPct
    HMPST.GearTrain.PG1.Ring.TeethNum,...  % nTRing
    [HMPST.GearTrain.PG1.Sun.TeethNum ...  % nTSuns
    HMPST.GearTrain.PG2.Sun.TeethNum ...
    HMPST.GearTrain.PG3.Sun.TeethNum ...
    HMPST.GearTrain.PG4.Sun.TeethNum],...
    HMPST.GearTrain.Gear5.TeethNum/...     % nGearHSOut
    HMPST.GearTrain.Gear4.TeethNum,...
    HMPST.HydroUnit.Pump.volEffNominal,... % pumpVolEff
    'plot');

% Resize figure content
% Remove target line, possible line
tgtLine_h = findobj(ax_sw,'Tag','Target');
delete(tgtLine_h)
posLine_h = findobj(ax_sw,'Tag','Possible');
delete(posLine_h)
sm_cvt_power_split_pg_4range_animate_format(ax_sw);

%% Extract data from simulation results
swAng_sim = logsout_data.get('SwashCtrl_I').Values.Data;
vehSp_sim = logsout_data.get('Vehicle Speed').Values.Data;
sTime_sim = logsout_data.get('Vehicle Speed').Values.Time;

%% Interpret data for animation
sampleSize = videoSpeedup/30;
interp_t = 0:sampleSize:sTime_sim(end);
sTime_interp = interp1(sTime_sim,sTime_sim,interp_t);
swAng_interp = interp1(sTime_sim,swAng_sim,interp_t);
vehSp_interp = interp1(sTime_sim,vehSp_sim,interp_t);

%% Add objects for animation
hold on
xPt_h = plot(0,0,'o','Color',[0.2 0.6 0.2],'LineWidth',3,'MarkerSize',20,...
    'DisplayName','Current State');
vSp_h = patch([0.95 1 1 0.95],[0 0 max(eps,vehSp_interp(1))*[1 1]],[1 0.6 0],...
    'EdgeColor','none','FaceAlpha',0.4,'DisplayName','Vehicle Speed');
pSw_h = patch([0.95 1 1 0.95],[0 0 max(eps,vehSp_interp(1))*[1 1]],[0.2 0.6 0.2],...
    'EdgeColor','none','FaceAlpha',0.4,'DisplayName','Swash Ratio');
hold off

%% Loop over results 
for i = 1:length(sTime_interp)-1

    % Update data for current point
    xPt_h.XData = swAng_interp(i);
    xPt_h.YData = vehSp_interp(i);

    % Update vehicle speed bar
    vSp_h.YData = [0 0 max(eps,vehSp_interp(i))*[1 1]];
    halfWid = 0.035;
    vSp_h.XData = [swAng_interp(i)-halfWid swAng_interp(i)+halfWid...
        swAng_interp(i)+halfWid swAng_interp(i)-halfWid];

    % Update swash ratio bar
    pSw_h.XData = [0 0 swAng_interp(i) swAng_interp(i)];
    halfWid = 0.5;
    pSw_h.YData = [vehSp_interp(i)-halfWid vehSp_interp(i)+halfWid...
    vehSp_interp(i)+halfWid vehSp_interp(i)-halfWid];

    % Update figure    
    drawnow

    % If requested, save results for video
    if(saveVideo)
        F(i) = getframe(gcf); %#ok<AGROW>
    end
end

% If requested write video
if(saveVideo)
    now_string = datestr(now,'yymmdd_HHMM');
    cd(fileparts(which(mfilename)))
    v = VideoWriter(['sm_cvt_animate' now_string '.mp4'],'MPEG-4');
    open(v)
    writeVideo(v,F)
    close(v)
end

end