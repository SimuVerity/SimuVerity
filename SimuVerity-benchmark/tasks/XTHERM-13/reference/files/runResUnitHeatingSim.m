% This function sets up the Thermal energy storage parameters and runs the
% simulation ResidentialBuildingTESandPVcell.slx

% Copyright 2023 - 2024 The MathWorks, Inc.

function [optionsRunSummary] = runResUnitHeatingSim(PV,SandBat,amb,designCombination, designAttributeTbl,yearRunFlg, simTm,Unit,varargin)

simObject = load_system('ResidentialBuildingTESandPVcell');
resetHouseParams(Unit);
eqPow = 1000*Unit.monthlyPow/3600;
ratedPow = PV.Pm*PV.numPVpanel;
set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Sand TES', 'coilShape', "layoutShape.HelicalCoil");
set_param('ResidentialBuildingTESandPVcell/Photovoltaic panel/Solar Cell', 'N_series', num2str(PV.nSeries), 'N_parallel', num2str(PV.numPVpanel));
set_param('ResidentialBuildingTESandPVcell/Photovoltaic panel/MPPT converter', 'Vm', num2str(PV.Vm));
set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Sand TES', 'numCoilX', num2str(SandBat.numCoilsX), 'numCoilY', num2str(SandBat.numCoilsY));
set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Sand TES', 'coilDepthHeater', num2str(SandBat.heaterCoilDepth), 'coilDepthCooler', num2str(SandBat.airCoilDepth));
set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Sand TES', 'nturnsHeater', num2str(SandBat.coilTurns), 'nturnsCooler', num2str(SandBat.coilTurns));
set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Ground/Ground insulation','area',num2str(SandBat.groundConductionArea));
set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Heater protection switch/Max Heater T/','Value',num2str(SandBat.heaterMaxT)); % Set temperature limit for the heating coil

if yearRunFlg == 0
    % Initialize the arrays, in which you store system response and component cost:
    storeHeat = zeros(size(designCombination, 1), 1); % Initialize Thermal energy storage at zero heat storage (J)
    filamentTemp = ones(size(designCombination, 1), 1); % Initialize heater filament temperature to room temperature (degC)
    heatLoss = zeros(size(designCombination, 1), 1); % Initialize heat lost vactor (J)
    TESCost = zeros(size(designCombination, 1), 1); % Initialize total cost vactor (USD $)
    designOptArr = string(designCombination); % Intialize cell array for option names
    set_param(simObject, "FastRestart", "on")
end

for nCase = 1:size(designCombination, 1)
    % Set parameters for the Thermal energy storage and heater
    set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Sand TES', ...
        'pipeHydraulicDia', string(designAttributeTbl.pipe.("Pipe Diameter (m)")(designCombination(nCase,2))),'heaterRes', string(designAttributeTbl.heater.("Electrical Resistance (ohm)")(designCombination(nCase,1))));
    % Set insulation thermal conductivity
    set_param('ResidentialBuildingTESandPVcell/Thermal energy storage/Ground/Ground insulation','th_cond',string(designAttributeTbl.insulation.("Thermal conductivity (W/m-K)")(designCombination(nCase,3))),'thickness',string(designAttributeTbl.insulation.("Sheet Thickness (m)")(designCombination(nCase,3))))
    eqCoilRes = designAttributeTbl.heater.("Electrical Resistance (ohm)")(designCombination(nCase,1))/(SandBat.numCoilsX*SandBat.numCoilsY);
    eqCircuitRes = (ratedPow-eqPow)*eqCoilRes/eqPow;
    MPPTRes = (eqCoilRes*eqCircuitRes)/(eqCoilRes + eqCircuitRes);
    set_param('ResidentialBuildingTESandPVcell/Residential unit/Domestic load/','R',num2str(eqCircuitRes));
    set_param('ResidentialBuildingTESandPVcell/Photovoltaic panel/MPPT converter', 'Rload', num2str(MPPTRes));
    if yearRunFlg == 0

        % Run the simulation
        simRes = sim('ResidentialBuildingTESandPVcell', 'StopTime', string(simTm));

        % Get time series data for power loss
        tm = simRes.simlogResidentialBuildingTESandPVcell.Thermal_energy_storage.Ground.Ground_insulation.Q.series.time;
        powLoss = simRes.simlogResidentialBuildingTESandPVcell.Thermal_energy_storage.Ground.Ground_insulation.Q.series.values;
        % Calculate time integral of power loss to get total energy loss (Joule)
        heatLoss(nCase) = trapz(tm, powLoss);
        % Get heat stored and maximum filament temperature
        sHn = simRes.simlogResidentialBuildingTESandPVcell.Thermal_energy_storage.Sand_TES.hPotential.series.values;
        storeHeat(nCase) = sHn(end);
        filamentTemp(nCase) = max(simRes.simlogResidentialBuildingTESandPVcell.Thermal_energy_storage.Sand_TES.filamentTemp.series.values);
        % Calculate total cost
        TESCost(nCase) = calcComponentCost(designAttributeTbl, designCombination(nCase,1), SandBat.airCoilDepth, designCombination(nCase,2), SandBat.heaterCoilDepth, designCombination(nCase,3), SandBat.groundConductionArea);
        designOptArr(nCase,3) = designAttributeTbl.insulation.("Insulation Material")(designCombination(nCase,3));
        designOptArr(nCase,2) = designAttributeTbl.pipe.("Pipe Grade")(designCombination(nCase,2));
        designOptArr(nCase,1) = designAttributeTbl.heater.("Element Type")(designCombination(nCase,1));
    end
    if yearRunFlg == 1
        allVar = cell2mat(varargin);
        set_param('ResidentialBuildingTESandPVcell/Control/Temperature Controller/Air flow control/', 'upperSaturationLimit', string(allVar(1))); % Set upper limit for the fan
        set_param('ResidentialBuildingTESandPVcell/Room set temp', 'Value', string(Unit.roomTemperatureSetpoint)); % Set value for the room set point temperature
        hrs2sec = transpose(3600*amb.hourlyData.("Time(hrs)")); % Convert hours column from table to seconds vector
        [maxIrradiation, maxInd] = max(amb.hourlyData.("Total Solar Irradiation(W/m^2)"));
        radiation = transpose([amb.hourlyData.("Total Solar Irradiation(W/m^2)")(maxInd:end,:);amb.hourlyData.("Total Solar Irradiation(W/m^2)")(1:maxInd-1,:)]); % Convert total solar irradiation column to vector
        temperature = transpose([amb.hourlyData.("Ambient Temperature(degC)")(maxInd:end,:);amb.hourlyData.("Ambient Temperature(degC)")(1:maxInd-1,:)]);
        set_param('ResidentialBuildingTESandPVcell/Solar irradiation', 'rep_seq_t', mat2str(hrs2sec), 'rep_seq_y', mat2str(radiation));
        set_param('ResidentialBuildingTESandPVcell/Amb T', 'rep_seq_t', mat2str(hrs2sec), 'rep_seq_y', mat2str(temperature));
        % Run the simulation
        simRes = sim('ResidentialBuildingTESandPVcell', 'StopTime', string(simTm));
    end

end

if yearRunFlg == 0
    set_param(simObject, "FastRestart", "off");
    close_system(simObject, 0);
    tableVarNames1 = ["Sand Battery Cost (USD)", "Heat Stored (J)", "Heat Lost (J)", "Heating Coil Temperature (degC)"];
    tableVarNames2 = ["Heater Element Type" "Pipe Grade" "Insulation Material"];
    ResultTable = array2table([TESCost, storeHeat, heatLoss, filamentTemp],"VariableNames",tableVarNames1);
    OptionTable = array2table(designOptArr,"VariableNames",tableVarNames2);
    optionsRunSummary = [OptionTable,ResultTable];
    save('TEScombinationsResults','optionsRunSummary');
end

if yearRunFlg == 1
    avgRoomTemp = simRes.simlogResidentialBuildingTESandPVcell.Residential_unit.Room_4.Air_thermal_mass.T.series.values;
    powLoss = simRes.simlogResidentialBuildingTESandPVcell.Thermal_energy_storage.Ground.Ground_insulation.Q.series.values;
    hotWaterTemp = simRes.simlogResidentialBuildingTESandPVcell.Hot_water_tank.H.T.series.values;
    heatHouse = (simRes.simlogResidentialBuildingTESandPVcell.Heat_exchanger.HEX.thermal_liquid.Q.series.values) + simRes.simlogResidentialBuildingTESandPVcell.Conductive_Heat_Transfer1.Q.series.values;
    pumpPower = (simRes.simlogResidentialBuildingTESandPVcell.Heat_exchanger.Air_blower.power.series.values) + (simRes.simlogResidentialBuildingTESandPVcell.Water_pump.power.series.values);
    heatStored = simRes.simlogResidentialBuildingTESandPVcell.Thermal_energy_storage.Sand_TES.hPotential.series.values;
    time = simRes.simlogResidentialBuildingTESandPVcell.Hot_water_tank.H.T.series.time;
    save ('verificationResults','avgRoomTemp','hotWaterTemp','heatHouse','powLoss','heatStored','pumpPower','time')
    close_system(simObject, 0);
end
end
