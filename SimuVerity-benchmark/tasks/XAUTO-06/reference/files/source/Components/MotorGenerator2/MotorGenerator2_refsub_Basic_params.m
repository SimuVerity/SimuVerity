%% Parameters for Motor Generator 2

% Copyright 2021-2022 The MathWorks, Inc.

defineBus_HighVoltage
defineBus_Rotational

%% Block parameters

motorGenerator2.trqMax_Nm = 163;  % P610
% motorGenerator2.spdMax_rpm = 17000;  % P610
motorGenerator2.powerMax_kW = 53;  % P610
motorGenerator2.responseTime_s = 0.02;

motorGenerator2.efficiency_pct = 98;
motorGenerator2.spd_eff_rpm = 2000;
motorGenerator2.trq_eff_Nm = 50;

motorGenerator2.thermalMass_J_perK = 5000;

% motorGenerator2.dampSpringStiffness_Nm_per_rad = 10000;
% motorGenerator2.dampSpringFriction_Nm_per_rpm = 100;
motorGenerator2.dampSpringStiffness_Nm_per_rad = 1000;
motorGenerator2.dampSpringFriction_Nm_per_rpm = 10000;

smoothing.MG2_dampSpringVelTol_rpm = 0.1;

%% Initial conditions

initial.MG2_Temperature_K = 273.15 + 20;

initial.MG2_AirTemp_K = 273.15 + 20;
