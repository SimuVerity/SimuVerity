% Parameter file for residential building heating example using PV charged sand
% thermal energy storage. 

% Copyright 2023 - 2024 The MathWorks, Inc.

residentialUnitSetParam;
ThermalBatterySetParam;
resUnitParams.eqPow = 1000*resUnitParams.avgPowConsumption/3600; 
PVpanel.ratedPow = PVpanel.power*PVpanel.geometry.nPrlStr;
TES.eqCoilRes = TES.heaterRes/(TES.numCoilX*TES.numCoilY);
resUnitParams.eqCircuitRes = (PVpanel.ratedPow-resUnitParams.eqPow)*TES.eqCoilRes/resUnitParams.eqPow;
PVpanel.MPPTRes = (TES.eqCoilRes*resUnitParams.eqCircuitRes)/(TES.eqCoilRes + resUnitParams.eqCircuitRes);