initial.hvBattery_SOC_pct = batteryHV_InputData.Options.InitialSOC_pct;
initial.hvBattery_Charge_Ahr =  batteryHV_InputData.Options.InitialCharge_Ahr;

%% High Voltage Battery - Essential
batteryHV.nominalVoltage_V = 350;
batteryHV.internalResistance_Ohm = 0.01;
batteryHV.nominalCapacity_kWh = 4;
batteryHV.voltagePerCell_V = 3.7;  % Open Circuit Voltage. 3.5V to 3.7V assuming Lithium-ion
batteryHV.nominalCharge_Ahr = ...
  batteryHV.nominalCapacity_kWh / batteryHV.nominalVoltage_V * 1000;

% Initial conditions
initial.hvBattery_SOC_pct = 70;
initial.hvBattery_Charge_Ahr = batteryHV.nominalCharge_Ahr * initial.hvBattery_SOC_pct/100;

%% With Finite Capacity
% At SOC 50%, voltage is 90% of the nominal.
batteryHV.measuredCharge_Ahr = batteryHV.nominalCharge_Ahr * 0.5;
batteryHV.measuredVoltage_V = batteryHV.nominalVoltage_V * 0.9;

%% Thermal model parameters
ambient.mass_t = 10000;
ambient.SpecificHeat_J_per_Kkg = 1000;
ambient.temp_K = 273.15 + 20;

initial.ambientTemp_K = ambient.temp_K;

batteryHV.RadiationArea_m2 = 1;
batteryHV.RadiationCoeff_W_per_K4m2 = 5e-10;

batteryHV.thermalMass_kJ_per_K = 0.1;

initial.hvBattery_Temperature_K = ...
  273.15 + batteryHV_InputData.Options.InitialTemperature_degC;

%% More Thermal model parameters
batteryHV.measurementTemperature_K = 273.15 + 25;
batteryHV.secondMeasurementTemperature_K = 273.15 + 0;

batteryHV.secondNominalVoltage_V = batteryHV.nominalVoltage_V * 0.95;
batteryHV.secondInternalResistance_Ohm = batteryHV.internalResistance_Ohm * 2;
batteryHV.secondMeasuredVoltage_V = batteryHV.nominalVoltage_V * 0.9;
