function sm_four_bar_optim_center_plot(ax_h,factor)
% Copyright 2017-2025 MathWorks, Inc.

% Extend range of axes by (current range*factor)
% and leave plot centered

currXLim = get(ax_h,'XLim'); currXLimRange = currXLim(2)-currXLim(1);
currYLim = get(ax_h,'YLim'); currYLimRange = currYLim(2)-currYLim(1);
newXLim = currXLim + [-1 1]*currXLimRange*factor;
newYLim = currYLim + [-1 1]*currYLimRange*factor;
set(ax_h,'XLim',newXLim,'YLim',newYLim);