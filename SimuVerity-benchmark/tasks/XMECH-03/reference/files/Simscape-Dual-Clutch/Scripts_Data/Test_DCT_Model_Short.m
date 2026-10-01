% SCRIPT TO RUN TWO SHORT TESTS AND DISPLAY REPORT
% Copyright 2011-2025 The MathWorks, Inc.
model = 'Dual_Clutch_Trans';
open_system(model);
set_param(model,'StopTime','30');
set_param(model,'SimulationMode','normal');

Drive_Cycle_Num = 6;
sim(model);

Drive_Cycle_Num = 7;
sim(model);

open('DCT_Model_Report_SHORT.html');
