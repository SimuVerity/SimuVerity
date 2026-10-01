%% Set-up Script for Power Split Drive Unit

% Copyright 2021-2022 The MathWorks, Inc.

defineBus_Rotational
defineBus_HighVoltage

%% Power split geartrain

PowerSplitGeartrain_refsub_Basic_params

%% Motor generator 2

motorGenerator2.trqMax_Nm = 163;  % P610
% motorGenerator2.spdMax_rpm = 17000;  % P610
motorGenerator2.powerMax_kW = 53;  % P610
motorGenerator2.responseTime_s = 0.02;

motorGenerator2.efficiency_pct = 98;
motorGenerator2.spd_eff_rpm = 2000;
motorGenerator2.trq_eff_Nm = 50;

motorGenerator2.thermalMass_J_perK = 5000;

motorGenerator2.dampSpringStiffness_Nm_per_rad = 10000;
motorGenerator2.dampSpringFriction_Nm_per_rpm = 100;

smoothing.MG2_dampSpringVelTol_rpm = 0.1;

%% Motor generator 1

motorGenerator1.trqMax_Nm = 40;  % P610
% motorGenerator1.spdMax_rpm = 10000;  % P610
motorGenerator1.powerMax_kW = 23;  % P610
motorGenerator1.responseTime_s = 0.02;

motorGenerator1.efficiency_pct = 95;
motorGenerator1.spd_eff_rpm = 2000;
motorGenerator1.trq_eff_Nm = 20;

motorGenerator1.thermalMass_J_perK = 5000;

motorGenerator1.dampSpringStiffness_Nm_per_rad = 10000;
motorGenerator1.dampSpringFriction_Nm_per_rpm = 100;

smoothing.MG1_dampSpringVelTol_rpm = 0.1;

%% Engine

engine.trqMax_Nm = 145;
engine.trqMaxSpd_rpm = 3500;
engine.powerMax_kW = 75;
% engine.powerMaxSpd_rpm = 6000;
engine.maxSpd_rpm = 7000;
engine.stallSpd_rpm = 500;
engine.smoothing_rpm = 100;

engine.lag_s = 0.1;

engine.inertia_kg_m2 = 0.02;

engine.damping_Nm_per_rpm = 0.02;

engine.dampSpringStiffness_Nm_per_rad = 10000;
engine.dampSpringFriction_Nm_per_rpm = 100;

%% Initial conditions

% MG2
initial.MG2_Temperature_K = 273.15 + 20;
initial.MG2_AirTemp_K = 273.15 + 20;

% MG1
initial.MG1_Temperature_K = 273.15 + 20;
initial.MG1_AirTemp_K = 273.15 + 20;

% Engine
initial.engine_speed_rpm = 0;
