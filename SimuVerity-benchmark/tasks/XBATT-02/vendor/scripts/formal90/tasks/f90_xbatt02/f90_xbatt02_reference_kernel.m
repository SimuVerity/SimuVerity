function [pack_state,module_state,cooling_state,thermal_flux] = fcn( ...
    t,ambient_temperature,coolant_inlet_temperature,initial_soc, ...
    current_demand,module_resistance_spread,coolant_maldistribution, ...
    load_step_time,regen_start_time)
%#codegen
persistent soc temp pol
dt = 0.05;
ns = [12 12 12 16 16 12 12 12];
np = 3;
capAh = 20*np;
cp = 4180;
cth = [18000 18000 18000 24000 24000 18000 18000 18000];
spreadShape = [-1 -.7 -.3 .2 .7 1 .5 -.5];
flowShape = [0 .2 .55 1 1 .55 .2 0];

if isempty(soc) || t < 0.5*dt
    soc = min(max(initial_soc,0),1)*ones(1,8);
    temp = ambient_temperature*ones(1,8);
    pol = zeros(1,8);
end

if t < load_step_time
    requested = .55*current_demand;
elseif t < regen_start_time
    requested = 1.20*current_demand;
elseif t < regen_start_time+30
    requested = -.35*current_demand;
else
    requested = .80*current_demand;
end

minSoc = min(soc);
maxTemp = max(temp);
socAuthority = clip((minSoc-.08)/.05,0,1);
tempAuthority = clip((318-maxTemp)/4,0,1);
ocvCell = 3.0+1.2*soc-.04*exp(-18*soc);
temperatureFactor = clip(1+.004*(298-temp),.75,1.35);
rCell = .0032*(1+.8*(1-soc)).*temperatureFactor;
r0 = (ns/np).*rCell.* ...
    (1+module_resistance_spread*spreadShape);
if requested > 0
    voltageSafeCurrent = max(min( ...
        (ns.*ocvCell-pol-ns*2.78)./max(r0,1e-6))-5,0);
    voltageAuthority = clip( ...
        voltageSafeCurrent/max(requested,1),0,1);
    authority = min([ ...
        socAuthority,tempAuthority,voltageAuthority]);
else
    authority = 1;
end
tractionCurrent = requested*authority;
limiting = double(requested > 0 && authority < .999);

thermalDrive = max(maxTemp-coolant_inlet_temperature,0);
pumpCommand = clip(.08+.13*thermalDrive+.12*limiting,0,1);
branchFlow = .06*pumpCommand* ...
    (1-coolant_maldistribution*flowShape);
branchFlow = max(branchFlow,0);
pumpPower = 500*pumpCommand^2;

baseVoltage = sum(ns.*ocvCell-tractionCurrent*r0-pol);
resistanceSum = sum(r0);
pumpDiscriminant = max( ...
    baseVoltage^2-4*resistanceSum*pumpPower,0);
pumpCurrent = 2*pumpPower/max( ...
    baseVoltage+sqrt(pumpDiscriminant),100);
packCurrent = tractionCurrent+pumpCurrent;
moduleVoltage = ns.*ocvCell-packCurrent*r0-pol;
packVoltage = sum(moduleVoltage);

rPolarization = (ns/np)*.0015;
qGeneration = packCurrent^2*r0+abs(packCurrent*pol);
qCooling = .72*branchFlow*cp.* ...
    (temp-coolant_inlet_temperature);
outletTemperature = temp;
flowActive = branchFlow > 1e-9;
outletTemperature(flowActive) = ...
    coolant_inlet_temperature+ ...
    qCooling(flowActive)./(branchFlow(flowActive)*cp);
passiveAmbient = 2.5*(temp-ambient_temperature);
dSoc = -(packCurrent/(capAh*3600))*ones(1,8);
dTemp = (qGeneration-qCooling-passiveAmbient)./cth;
dPol = (packCurrent*rPolarization-pol)/18;

pack_state = [requested tractionCurrent pumpCurrent packCurrent ...
    packVoltage minSoc maxTemp limiting];
module_state = [moduleVoltage soc temp];
cooling_state = [pumpCommand pumpPower coolant_inlet_temperature ...
    branchFlow outletTemperature];
thermal_flux = [qGeneration qCooling];

soc = min(max(soc+dt*dSoc,0),1);
temp = min(max(temp+dt*dTemp,250),360);
pol = pol+dt*dPol;
end

function y = clip(x,lo,hi)
y = min(max(x,lo),hi);
end
