function ELoss= calcPowerLossCVT(simlog_pwr,varargin)
% Calculate power loss across continuously variable transmission (CVT)
% Relies on Rotational Mechanical Power sensors in model

% Copyright 2023-2025 The MathWorks, Inc.


p1e   = simlog_pwr.Power_Sensor1_Engine_Out.Power_Sensor.P.series.values('kW');
p2c   = simlog_pwr.Power_Sensor2_CVT_Out.Power_Sensor.P.series.values('kW');
ptime = simlog_pwr.Power_Sensor2_CVT_Out.Power_Sensor.P.series.time;

if(nargin==2)
    timeStaEnd = varargin{1};
    timeInd1 = find(ptime>=timeStaEnd(1),1);
    timeInd2 = find(ptime>=timeStaEnd(2),1);
else
    timeInd1 = 1;
    timeInd2 = length(ptime);
end

energyCml.engOut = cumtrapz(ptime(timeInd1:timeInd2),p1e(timeInd1:timeInd2));
energyCml.CVTOut = cumtrapz(ptime(timeInd1:timeInd2),p2c(timeInd1:timeInd2));

ELoss = (energyCml.engOut(end)-energyCml.CVTOut(end))/3600;
