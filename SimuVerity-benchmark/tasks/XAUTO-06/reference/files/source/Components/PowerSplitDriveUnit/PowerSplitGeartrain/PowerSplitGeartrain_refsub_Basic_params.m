%% Set-up Script for Power Split Geartrain

% Copyright 2021-2022 The MathWorks, Inc.

defineBus_Rotational

powerSplit.reducer_counterDriveGearRatio = 53/65;  % 53/65 = 0.8154  P610
powerSplit.reducer_MG2GearRatio = 53/17;  % 53/17 = 3.1176  P610 motor reduction gear ratio
powerSplit.reducer_differentialGearRatio = 21/73;  % HEV
powerSplit.reducer_efficiency = 0.98;
powerSplit.reducer_friction_Nm_per_rpm = [0.001 0.001];  % Base and Follower
powerSplit.reducer_inertia_kg_m2 = 0.001;

powerSplit.planetary_ringToSunGearRatio = 78/30;
powerSplit.planetary_efficiencies = [0.98, 0.98];  % Sun-Planet, Ring-Planet
powerSplit.planetary_frictions_Nm_per_rpm = [0.001, 0.001];  % Sun-Carrier, Planet-Carrier frictions
powerSplit.planetary_planetGearInertia_kg_m2 = 0.001;
powerSplit.planetary_ringInertia_kg_m2 = 0.001;

%% Smoothing parameters

smoothing.planetary_meshing_loss_thresholds_W = [10, 10];

smoothing.gear_meshing_loss_threshold_W = 10;
