% Script to animate shaft speed

% Copyright 2023-2025 The MathWorks, Inc.

sm_cvt_power_split_pg_plot1speed(simlog_sm_cvt_power_split_pg,logsout_sm_cvt_power_split_pg,cvtPar)
axis([0 25 -80 80])
set(gcf,'Position',[910   155   574   499])
ax_sw = gca;
%ax_sw.YLabel.Units           = 'normalized';
%ax_sw.YLabel.Position        = [0.2171    0.9887         0];
%set(gcf,'Position',[899   304   533   580])
%ax_sw.YLabel.BackgroundColor = [1 1 1];
ax_sw.YAxis.FontSize         = 14;
ax_sw.YLabel.FontSize        = 18;
ax_sw.XAxis.FontSize         = 14;
ax_sw.XLabel.FontSize        = 16;
ax_sw.Title.FontSize         = 18;
%ax_sw.Legend.Position        = [0.5389    0.6364    0.3546    0.1957];
ax_sw.Legend.FontSize        = 16;

h = findobj('Type','line');
for i = 1:length(h)
    h(i).LineWidth = 3;
end
h(1).DisplayName = 'Output';
h(2).DisplayName = 'Input 2';
h(3).DisplayName = 'Input 1';

th = findobj('Type','text');
delete(th)

hold on
patch_w = 0.5;
patch_h = 80;

ptch_h = patch([-1 1 1 -1]*patch_w/2+14,[-1 -1 1 1]*patch_h,[127 215 247]/255,'FaceAlpha',0.7,'EdgeColor','none','DisplayName','Current');
hold off


sampleSize = 1/30;
animStopTime = 25;
sTime_interp = 0:sampleSize:animStopTime;
%sTime_interp = interp1(sTime_sim,animStopTime,interp_t);
%swAng_interp = interp1(sTime_sim,swAng_sim,interp_t);
%vehSp_interp = interp1(sTime_sim,vehSp_sim,interp_t);
saveVideo = true;

clear F
for i = 1:length(sTime_interp)-1

    % Update data for current point
    nowTime = sTime_interp(i);

    % Update now bar cursor
    ptch_h.XData = [-1 1 1 -1]*patch_w/2+nowTime;

    % Update figure    
    drawnow

    % If requested, save results for video
    if(saveVideo)
        F(i) = getframe(gcf); %#ok<AGROW>
    end
end

%%

if(saveVideo)
    now_string = datestr(now,'yymmdd_HHMM');
    cd(fileparts(which(mfilename)))
    v = VideoWriter(['sm_powersplit_animate_wShafts' now_string '.mp4'],'MPEG-4');
    open(v)
    writeVideo(v,F)
    close(v)
end