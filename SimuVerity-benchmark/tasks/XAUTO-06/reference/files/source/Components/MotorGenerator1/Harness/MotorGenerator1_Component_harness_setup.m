%% Setup Script for Motor Generator 1

% Copyright 2021-2022 The MathWorks, Inc.

defineBus_HighVoltage
defineBus_Rotational

MotorGenerator1_refsub_Basic_params

%% Block parameters

batteryHighVoltage.voltage_V = 650;
batteryHighVoltage.internal_R_Ohm = 0.1;

% Li-ion (3.5V-3.7V cell)
batteryHighVoltage.cellVoltage_V = 3.6;

batteryHighVoltage.capacity_kWh = 9;

batteryHighVoltage.charge_Ahr = batteryHighVoltage.capacity_kWh / batteryHighVoltage.cellVoltage_V * 1000;

%% Initial conditions

initial.hvBattery_Charge_Ahr = batteryHighVoltage.charge_Ahr * 0.6;

initial.engine_speed_rpm = 0;
