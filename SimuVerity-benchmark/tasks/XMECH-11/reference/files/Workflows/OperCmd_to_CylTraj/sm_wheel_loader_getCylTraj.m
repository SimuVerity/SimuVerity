function results = sm_wheel_loader_getCylTraj(simlog_lnk)
% Code to plot simulation results from sm_wheel_loader
%
% Copyright 2023-2025 The MathWorks, Inc.


%% Get simulation results
results.time      = simlog_lnk.Linkage.Lift.p.Time;
results.pLift.values  = squeeze(simlog_lnk.Linkage.Lift.p.Data);
results.pTilt.values  = squeeze(simlog_lnk.Linkage.Tilt.p.Data);
results.pStr.values   = squeeze(simlog_lnk.Steer.p.Data);
