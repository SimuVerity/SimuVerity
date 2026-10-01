function out = calcHeatEnergy(slog)


% Condenser heat dissipated to the air in Wh (positive if refrigerant temperature decreases)
condHeatEnergy = cumtrapz(slog.get('hflwCond').Values.Time,slog.get('hflwCond').Values.Data)/3600;

% Evaporator heat energy taken away from the cabin (positive if cabin temperature decreases)
evapHeatEnergy =  cumtrapz(slog.get('hflwEvap').Values.Time,slog.get('hflwEvap').Values.Data)/3600;

% Heat Energy taken away from the electric machine (positive if the machine temperature decreases)
EMHeatEnergy   =  cumtrapz(slog.get('hflwEM').Values.Time,slog.get('hflwEM').Values.Data)/3600;

% Heat that is taken from the coolant to the refrigerant with the chiller (positive if refrigerant temperature increases)
chillHeatEnergy = cumtrapz(slog.get('hflwChiller').Values.Time,slog.get('hflwChiller').Values.Data)/3600;

% Heat that is taken from the battery (positive if the battery temperature decreases)
battHeatEnergy = cumtrapz(slog.get('hflwBatt').Values.Time,slog.get('hflwBatt').Values.Data)/3600;

% How much energy the battery gives to the plate (positive if the battery cools down)
battHeatEnergyPlate = cumtrapz(slog.get('hflBattPlate').Values.Time,slog.get('hflBattPlate').Values.Data)/3600;

% Heat that is taken from the radiator (positive if the coolant temperature decreases)
radHeatEnergy  = cumtrapz(slog.get('hflwRad').Values.Time,slog.get('hflwRad').Values.Data)/3600;

%% Outputs
out.condEnergyToAir          = condHeatEnergy(end);     % Total heat energy dissipated to the ambient in Wh;
out.evapEnergyFromCabin      = evapHeatEnergy(end);     % Total heat energy taken from the cabin in Wh;
out.EMEnergyToCoolant        = EMHeatEnergy(end);       % Total heat energy taken away from the motor in Wh
out.chillerEnergyFromCoolant = chillHeatEnergy(end);    % Total heat energy taken away from the coolant in Wh
out.battEnergyToCoolant      = battHeatEnergy(end);     % Total heat energy given to the coolant in Wh
out.radiatEnergyFromCoolant  = radHeatEnergy(end);      % Total heat energy dissipated from the coolant in Wh
out.battEnergyToPlate        = battHeatEnergyPlate(end);% Total heat energy dissipated to the plate in Wh
end