function sm_cvt_power_split_pg_4range_animate_format(ax_sw)
% Copyright 2023-2025 The MathWorks, Inc.

% Adjustments for video
ax_sw.YLabel.Units           = 'normalized';
ax_sw.YLabel.Position        = [0.2171    0.9887         0];
set(gcf,'Position',[899   304   533   580])
ax_sw.YLabel.BackgroundColor = [1 1 1];
ax_sw.YAxis.FontSize         = 14;
ax_sw.YLabel.FontSize        = 18;
ax_sw.XAxis.FontSize         = 14;
ax_sw.XLabel.FontSize        = 16;
ax_sw.Title.FontSize         = 18;
ax_sw.Legend.Position        = [0.5389    0.6364    0.3546    0.1957];
ax_sw.Legend.FontSize        = 16;

% For deleting
%{
ax_sw = gca;
tgtLine_h = findobj(ax_sw,'Tag','Target');
delete(tgtLine_h)
posLine_h = findobj(ax_sw,'Tag','Possible');
delete(posLine_h)
ctrLine_h = findobj(ax_sw,'Tag','Control');
delete(ctrLine_h)
legend('Location','Best')

ax_sw = gca;
posLine_h = findobj(ax_sw,'Tag','Possible');
delete(posLine_h)
tgtLine_h = findobj(ax_sw,'Tag','Target');
tgtLine_h.LineWidth = 2;
tgtLine_h.MarkerSize = 16
set(gca,'YLim',[0 37])
legend('Location','Best')
ax_sw.Legend.Position = [0.551630708425026   0.717870690348847 ...
0.212007501223745   0.053448274474719];

ctrLine_h = findobj(ax_sw,'Tag','Control');
delete(ctrLine_h)

%}