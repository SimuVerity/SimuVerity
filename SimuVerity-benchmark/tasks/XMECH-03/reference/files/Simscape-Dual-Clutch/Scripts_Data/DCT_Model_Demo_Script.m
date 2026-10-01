%% DCT Model Demo Script
%
% <html>
% <span style="font-family:Arial">
% <span style="font-size:10pt">
% <tr><b><u>Model</u></b><br>
% <tr>1.  <a href="matlab:open_system('Dual_Clutch_Trans');">Open Dual Clutch Transmission Model</a><br>
% <tr>2.  <a href="matlab:Test_DCT_Model_Short;">Run Drive Cycles</a><br>
% <tr>3.  <a href="matlab:cd([DCT_Model_HomeDir '/Fuel_Consumption']);edit Create_Fuel_Consumption_LUT;">Estimate Fuel Economy With Measured Data</a><br>
% <tr>4.  Shift Map Animation:<a href="matlab:Shift_Map_Sim_Movie('stored');">Drive Cycle 7</a>, <a href="matlab:Shift_Map_Sim_Movie('lastrun');">Previous Simulation</a><br>
% <tr>5.  Model Abstraction:<br>
% <tr>....a.  Vehicle Dynamics: <a href="matlab:open_system('Vehicle_Dynamics_Testrig');">Vehicle Dynamics</a><br>
% <tr>....b.  Transmission: <a href="matlab:cd([DCT_Model_HomeDir '/Tune_Abstr_Model']);open_system('Dual_Clutch_Trans_SDO');">Parameter Tuning</a>, <a href="matlab:Dual_Clutch_Trans_winopen_file(which('Tune_Abstr_Model.wmv'));">Video</a><br>
% <tr>....c.  <a href="matlab:Compare_Detailed_Abstracted_SimResults">Plot Comparing Simulation Results</a><br>
% <br>
% <tr><b><u>Simulate</u></b><br>
% <tr>6.  Parameter Sweep:<br>
% <tr>....a.  Shift Map Parameterization: <a href="matlab:cd(fileparts(which('ShiftMapParamGUI.m')));ShiftMapParamGUI;">Shift Map Parameterization GUI</a><br>
% <tr>....b.  1-D Parameter Sweep (Parallel): <a href="matlab:cd(fileparts(which('DCT_Parameter_Sweep_1D.m')));edit DCT_Parameter_Sweep_1D;">Run Parameter Sweep (1D)</a>, <a href="matlab:web('DCT_Parameter_Sweep_1D.html');">Results</a><br>
% <tr>....c.  2-D Parameter Sweep (Series): <a href="matlab:cd(fileparts(which('DCT_Parameter_Sweep_2D.m')));edit DCT_Parameter_Sweep_2D_series;">Run Parameter Sweep (2D)</a>, <a href="matlab:web('DCT_Parameter_Sweep_2D_series.html');">Results</a><br>
% <tr>....d.  2-D Parameter Sweep (Parallel): <a href="matlab:cd(fileparts(which('DCT_Parameter_Sweep_2D.m')));edit DCT_Parameter_Sweep_2D_para;">Run Parameter Sweep (2D)</a>, <a href="matlab:web('DCT_Parameter_Sweep_2D_para.html');">Results</a><br>
% <tr>....e.  <a href="matlab:Compare_Det_Abs_Models_2DSweep;">Compare Detailed/Abstracted Models</a><br>
% <tr>7.  Optimization: <br>
% <tr>....a.  1-D Optimization: <a href="matlab:edit find_min_fuel_1D;">MATLAB Code</a>, <a href="matlab:Dual_Clutch_Trans_winopen_file(which('OptFm1D.wmv'));">Video</a>, <a href="matlab:web('find_min_fuel_1D.html');">Results</a><br>
% <tr>....b.  2-D Opt., fminsearch: <a href="matlab:edit find_min_fuel_2D;">MATLAB Code</a>, <a href="matlab:Dual_Clutch_Trans_winopen_file(which('OptFm2D.wmv'));">Video</a>, <a href="matlab:open('find_min_fuel_2D.html');">Results</a><br>
% <tr>....c.  2-D Opt., patternsearch: <a href="matlab:edit find_min_fuel_ps2D;">MATLAB Code</a>, <a href="matlab:Dual_Clutch_Trans_winopen_file(which('OptPS2D.wmv'));">Video</a>, <a href="matlab:open('find_min_fuel_ps2D.html');">Results</a><br>
% <tr>....d.  Full Opt., patternsearch (Series): <a href="matlab:edit find_min_fuel_psMX_series;">MATLAB Code</a>, <a href="matlab:open('find_min_fuel_psMX_series.html');">Results</a><br>
% <tr>....e.  Full Opt., patternsearch (Parallel): <a href="matlab:edit find_min_fuel_psMX_para;">MATLAB Code</a>, <a href="matlab:Dual_Clutch_Trans_winopen_file(which('OptPSMX.wmv'));">Video</a>, <a href="matlab:open('find_min_fuel_psMX_para.html');">Results</a><br>
% <tr>8.  Analyze and Document: <a href="matlab:open('DCT_Model_Report_SHORT.html');">View Report</a>, <a href="matlab:cd([DCT_Model_HomeDir '/Reports']);open('DCT_Model_Report_SHORT.rpt');">Generate Report</a><br>
% <br>
% <tr><b><u>Deploy</u></b><br>
% <tr>9. <a href="matlab:cd(fileparts(which('Dual_Clutch_Trans_SLRT.m')));edit Dual_Clutch_Trans_SLRT;">Real-Time Simulation</a><br>
% </style>
% </style>
% </html>
% 
% Copyright 2011-2025 The MathWorks(TM), Inc.


