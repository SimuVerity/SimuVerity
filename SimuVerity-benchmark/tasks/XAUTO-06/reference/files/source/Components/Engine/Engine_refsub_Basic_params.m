%% Parameters for Engine component

% Copyright 2022 The MathWorks, Inc.

defineBus_Rotational

%% Block Parameters

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

%% Initial values

initial.engine_speed_rpm = 1000;
