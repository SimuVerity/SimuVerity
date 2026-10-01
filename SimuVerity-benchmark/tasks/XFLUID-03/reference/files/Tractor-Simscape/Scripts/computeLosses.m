function [inputEnergyTotal,lossFrontMotor,lossRearMotor,lossPump,lossChargePump,lossAux] = computeLosses(logsout)
%   COMPUTELOSSES This function computes & plots the energy losses of various
%   components of a tractor.
%   logsout contains simulation output of logged
%   signals. This function computes energy loss of front motor, rear motor
%   and pump using the simulation output data.

% Copyright 2024 The MathWorks, Inc.

% Obtain values of logged signals from simulation output
time = logsout{1}.Values.Engine.engineSpeed.Time;
dispPump = logsout{1}.Values.Pump_Displacement.Data;
wEngine = logsout{1}.Values.Engine.engineSpeed.Data;

tPump = logsout{1}.Values.Transmission.Main_Pump.trq__N_m_.Data;
qPump = logsout{1}.Values.Transmission.Main_Pump.q__m_3_s_.Data;

pAPipeA = logsout{1}.Values.Transmission.Pipe_A.pA__bar_.Data;
pBPipeA = logsout{1}.Values.Transmission.Pipe_A.pB__bar_.Data;

pAPipeB = logsout{1}.Values.Transmission.Pipe_B.pA__bar_.Data;
pBPipeB = logsout{1}.Values.Transmission.Pipe_B.pB__bar_.Data;

tChargePump = logsout{1}.Values.Transmission.Charge_Pump.trq__N_m_.Data;
pBChargePump = logsout{1}.Values.Transmission.Charge_Pump.P__bar_.Data;
qChargePump = logsout{1}.Values.Transmission.Charge_Pump.q__m_3_s_.Data;

wFrontMotor = logsout{1}.Values.Transmission.Front_Motor.w__rpm_.Data;
tFrontMotor = logsout{1}.Values.Transmission.Front_Motor.trq__N_m_.Data;
qFrontMotor = logsout{1}.Values.Transmission.Front_Motor.q__m_3_s_.Data;

wRearMotor = logsout{1}.Values.Transmission.Rear_Motor.w__rpm_.Data;
tRearMotor = logsout{1}.Values.Transmission.Rear_Motor.trq__N_m_.Data;
qRearMotor = logsout{1}.Values.Transmission.Rear_Motor.q__m_3_s_.Data;

qReliefValveA = logsout{1}.Values.Transmission.Flow_Relief_A.q__m_3_s_.Data;
qReliefValveB = logsout{1}.Values.Transmission.Flow_Relief_B.q__m_3_s_.Data;

%% Calculate input & output energy for various components
diffTime = diff(time);
% Calculate Pump Input Energy (kJ)
[inEnergyPumpForward,inEnergyPumpReverse] = computeMechEnergy(time,dispPump,wEngine,tPump);
inEnergyPumpTotal = inEnergyPumpForward + inEnergyPumpReverse;

% Calculate Pump Output Energy (kJ)
[outEnergyPumpForward,outEnergyPumpReverse] = computeHydEnergy(time,dispPump,pAPipeB,pAPipeA,qPump);
outEnergyPumpTotal = outEnergyPumpForward + outEnergyPumpReverse;

% Calculate Charge Pump Input Energy (kJ)
[inEnergyChargePumpForward,inEnergyChargePumpReverse] = computeMechEnergy(time,dispPump,wEngine,tChargePump);
inEnergyChargePumpTotal = inEnergyChargePumpForward + inEnergyChargePumpReverse;

% Calculate Charge Pump Output Energy (kJ)
pAChargePump = 1.01325; % Sump pressure
[outEnergyChargePumpForward,outEnergyChargePumpReverse] = computeHydEnergy(time,dispPump,pBChargePump,pAChargePump,qChargePump);
outEnergyChargePumpTotal = outEnergyChargePumpForward + outEnergyChargePumpReverse;

% Calculate Front Motor Input Energy (kJ)
[inEnergyFrontMotorForward,inEnergyFrontMotorReverse] = computeHydEnergy(time,dispPump,pBPipeB,pBPipeA,qFrontMotor);
inEnergyFrontMotorTotal = inEnergyFrontMotorForward + inEnergyFrontMotorReverse;

% Calculate Front Motor Output Energy (kJ)
[outEnergyFrontMotorForward,outEnergyFrontMotorReverse] = computeMechEnergy(time,dispPump,wFrontMotor,tFrontMotor);
outEnergyFrontMotorTotal = outEnergyFrontMotorForward + outEnergyFrontMotorReverse;

% Calculate Rear Motor Input Energy (kJ)
[inEnergyRearMotorForward,inEnergyRearMotorReverse] = computeHydEnergy(time,dispPump,pBPipeB,pBPipeA,qRearMotor);
inEnergyRearMotorTotal = inEnergyRearMotorForward + inEnergyRearMotorReverse;

% Calculate Rear Motor Output Energy (kJ)
[outEnergyRearMotorForward,outEnergyRearMotorReverse] = computeMechEnergy(time,dispPump,wRearMotor,tRearMotor);
outEnergyRearMotorTotal = outEnergyRearMotorForward + outEnergyRearMotorReverse;

% Calculate Relief Valves A Input Energy (kJ)
inEnergyReliefValveA = computeHydEnergy(time,dispPump,pBPipeA,0,qReliefValveA);

% Calculate Relief Valve A Output Energy (kJ)
outEnergyReliefValveA = computeHydEnergy(time,dispPump,pBPipeB,0,qReliefValveA);

% Calculate Relief Valve B Input Energy (kJ)
inEnergyReliefValveB = computeHydEnergy(time,dispPump,pBPipeB,0,qReliefValveB);

% Calculate Relief Valve B Output Energy (kJ)
outEnergyReliefValveB = computeHydEnergy(time,dispPump,pBPipeA,0,qReliefValveB);

% Calculate total input energy to the system
inputEnergyTotal = inEnergyPumpTotal;

%% Calculate losses encountered in various components
% You can set minimum energy lost in a component to avoid numerical error
disp('Calculating the energy losses for various components of tractor')
lossFrontMotor = max((inEnergyFrontMotorTotal - outEnergyFrontMotorTotal),1e-3); 
lossRearMotor = max((inEnergyRearMotorTotal - outEnergyRearMotorTotal),1e-3);
lossPump = max((inEnergyPumpTotal - outEnergyPumpTotal),1e-3);
lossChargePump = max((inEnergyChargePumpTotal - outEnergyChargePumpTotal),1e-3);
lossReliefValveA = max((inEnergyReliefValveA - outEnergyReliefValveA),0.5e-3);
lossReliefValveB = max((inEnergyReliefValveB - outEnergyReliefValveB),0.5e-3);
lossAux = lossReliefValveA + lossReliefValveB;
efficiency = 100*(inputEnergyTotal - (lossPump+lossChargePump+...
    lossFrontMotor+lossRearMotor+lossReliefValveA+lossReliefValveB))...
    /inputEnergyTotal;

%% Function to calculate shaft rotational mechanical energy in kJ
    function[mechEnergyForward,mechEnergyReverse] = computeMechEnergy(time,disp,rpm,torque)
        forwardGear = disp>= 0;
        reverseGear = disp<0;
        
        mechPowerForward = 1e-3*abs((rpm*2*pi/60).*torque).*forwardGear;
        mechPowerReverse = 1e-3*abs((rpm*2*pi/60).*torque).*reverseGear;
        
        diffMechPowerForward = diff(mechPowerForward);
        diffMechPowerReverse = diff(mechPowerReverse);
        diffTime = diff(time);

        mechPowerForward = mechPowerForward(1:end-1);
        mechPowerReverse = mechPowerReverse(1:end-1);

        mechEnergyForward = sum((mechPowerForward + 0.5*diffMechPowerForward).*diffTime);
        mechEnergyReverse = sum((mechPowerReverse + 0.5*diffMechPowerReverse).*diffTime);
    end

%% Function to calculate pump or motor's hydraulic energy in kJ
    function[hydEnergyForward,hydEnergyReverse] = computeHydEnergy(time,disp,pUpstream,pDownstream,flow)
        forwardGear = disp>= 0;
        reverseGear = disp<0;
        
        hydPowerForward = 1e-3*abs((pDownstream-pUpstream).*flow*1e5).*forwardGear;
        hydPowerReverse = 1e-3*abs((pDownstream-pUpstream).*flow*1e5).*reverseGear;
        
        diffHydPowerForward = diff(hydPowerForward);
        diffHydPowerReverse = diff(hydPowerReverse);
        diffTime = diff(time);

        hydPowerForward = hydPowerForward(1:end-1);
        hydPowerReverse = hydPowerReverse(1:end-1);

        hydEnergyForward = sum((hydPowerForward + 0.5*diffHydPowerForward).*diffTime);
        hydEnergyReverse = sum((hydPowerReverse + 0.5*diffHydPowerReverse).*diffTime);
    end

end
