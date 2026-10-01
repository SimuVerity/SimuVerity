%% Parameters for Motor Generator 1

% Copyright 2021-2022 The MathWorks, Inc.

%% Block parameters

motorGenerator1.trqMax_Nm = 40;  % P610
% motorGenerator1.spdMax_rpm = 10000;  % P610
motorGenerator1.powerMax_kW = 23;  % P610
motorGenerator1.responseTime_s = 0.02;

motorGenerator1.efficiency_pct = 95;
motorGenerator1.spd_eff_rpm = 2000;
motorGenerator1.trq_eff_Nm = 20;

motorGenerator1.thermalMass_J_perK = 5000;

% motorGenerator1.dampSpringStiffness_Nm_per_rad = 10000;
% motorGenerator1.dampSpringFriction_Nm_per_rpm = 100;
motorGenerator1.dampSpringStiffness_Nm_per_rad = 1000;
motorGenerator1.dampSpringFriction_Nm_per_rpm = 10000;

smoothing.MG1_dampSpringVelTol_rpm = 0.1;

%% Initial conditions

initial.MG1_Temperature_K = 273.15 + 20;

initial.MG1_AirTemp_K = 273.15 + 20;
