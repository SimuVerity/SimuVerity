function [DELTA]=msfplant(XP,UP)

% Plant
%{
Input:
    XP - State vector
    UP - Input Vector. UP = [B0 Tf Ws];

Output:
    DELTA - State Vector Derivative.

Index:
    UP vector:
        Bo - Recycle brine flow rate
        Tf - Sea water feed temperature
        Ws - Steam flow rate

%}

% Global Variables
%{
    dist - Vector with parameters [Us U Wf Rej Ts Wd LB LD]
    NREJ - Number of Heat Rejection stages
    NREC - Number of Heat Recovery stages
    Bd - Blowdown flow rate
    Wd - Distillate product flow rate
    sumLB - Accumulator used in the PI Controller that controls the
        Blowdown flow rate
    sumLD - Accumulator used in the PI Controller that controls the
        Distillate flow rate
%}
global dist NREJ NREC Bd Wd sumLB sumLD

% Number of stages (Rejection and Recovery)
NSTG=NREJ+NREC;

% Constants used in array access indices.
%{
N0: Brine Level Change
N1: Brine Temperature Change
N2: Condenser Temperature Change
N3+1: Brine Temperature in Brine Heater Change
%}
N0=0*NSTG;
N1=1*NSTG;
N2=2*NSTG;
N3=3*NSTG;
NN1=NSTG-NREJ+1;
   
% Brine Chamber Cross Section Area
AB=1260.0/22.0;
AD=63.0/22.0;
% Cross Section Area of Condenser Tube in Heat Recovery stage
AHC=77314.8/19.0;
% Cross Section Area of Condenser Tube in Heat Rejection stage
AHR=7919.1/3.0;
AS=3225.7;
% Orifice Width for Stage N
WN=3.0;
KD=1.0;
% Orifice Discharge coefficient
K=0.68;
% Orifice Contraction coefficient
C=0.625;
% Orifice Height
H=0.11;
% Gravitational Constant
G=9.81;
% Orifice Width
W=0.50;

% Reference Temperature. 0 degrees Celsius in Kelvin.
TREF=273.15;
% Recycle Brine Flow Rate
B0=UP(1)+0.0066667;
% Sea water feed temperature
TFEED=UP(2)+TREF;
% Steam flow rate
WS=UP(3)+0.074;
% Heat transfer coeff. of Brine Heater, kJ/min C m2
US=dist(1); 
% Heat transfer coeff. of tube, kJ/min C m2
U=dist(2);
% Sea Water feed rate, (ton/hr)
WF=dist(3);
% Reject flow rate, (ton/hr)
REJ=dist(4);
REC=0.0;
% Steam Temperature in degrees Celsius
TS=dist(5)+TREF; 
% Makeup Flow Rate
WMK=WF-REJ-REC;
% Initial condition for distillate flow rate
Wdss=dist(6);
% Initial condition for blowdown flow rate
Bdss=dist(7);
% Setpoint for brine level control
RLss=dist(8);
% Setpoint for distillate level control
RLDss=dist(11);
% Proportional Gain for [brine level, distilate level]
kc=[dist(9) dist(12)];
% Integral time for [brine level, distilate level]
ki=[dist(10) dist(13)];
   
% Update initial variables for each stage
for I=1:NSTG
    % Initial brine level in each stage
    RL(I)=XP(I);
    % Initial brine temperature in each stage
    TB(I)=XP(N1+I);
    % Initial condenser tube temperature
    TF(I)=XP(N2+I);
end

% Top Brine Temperature (+273.15 for Kelvin conversion)
TB0=XP(N3+1);
% Actual Distillate level
RLD=XP(N3+2);
% Brine temperature in final Heat Recovery Stage
TFREC=TB(NSTG);
% Temperature Delta used in energy balance equations.
DTS=TS-(TF(1)+TB0)*0.5;

% Calculate Physical Properties
% Calculate pressure for each stage
for I=1:NSTG
    PP=PRESS(TB(I));
    PB(I)=PP;
end

% Latent Heat for steam
HLV0 = LATENT(TS);
% Initial Pressure
PB0 = PRESS(TB0);

% Initial Brine Density
RHOB0=1016.0;
CPB0=1.00;
% Brine Density
RHOB=1032.4;
RHOF=1029.6;
% Heat Capacity of Brine in Flashing Chamber
CPB=1.00;
% Heat Capacity of Brine in Condenser Tube
CPF=1.00;
CPV=0.4865;
% Empirically Calculated Physical Property
BPR=2.192;
% Condenser Tube Liquid Holdup
FMW=23654.0;
% Latent Heat of Vaporization
HLV=563.7959;
HV=625.1971;
% Brine Heater Liquid Holdup
FMC=34736.09;
   
   
% Calculate the brine flow rate for each stage
for I=1:NSTG-1
    if I==1
        % Initial Stage Pressure
        DP=PB0-PB(I);
    else
        % Pressure difference between two consecutive stages
        DP=PB(I-1)-PB(I);
    end
    
    % Brine Level minus Orifice Contraction Coefficient * Orifice Height
    DH=RL(I)-C*H;
    
    % Last Stage specific values
    if I==NSTG
        DH=RL(I);
        WN=W;
    end
    
    % Brine level calculation
    DPDH=DP*1.01d5+G*RHOB*DH;
    BR(I)=WN*K*RL(I)*sqrt(max(0.0D0,DPDH*RHOB));
    BR(I)=BR(I)*60.0/1000.0;
end

% PI Controller - For adjusting the blowdown rate in the simulation
Bd=Bdss+kc(1)*(RLss-RL(22))+kc(1)*ki(1)*sumLB;
sumLB=sumLB+(RLss-RL(22));
  
% Calculate the Vapor Flow Rate for each stage
for I=1:NSTG
    
    % Calculate appropriate Temperature Delta term according to stage
    if(I==NREC)
        DT(I)=TB(I)-BPR/1.8-(TFREC+TF(I))*0.5;
    elseif(I==NSTG)
        DT(I)=TB(I)-BPR/1.8-(TFEED+TF(I))*0.5;
    else
        DT(I)=TB(I)-BPR/1.8-(TF(I+1)+TF(I))*0.5;
    end
    
    % Calculate Vapor Flow Rate according to stage
    if(I<=NREC)
        VR(I)=U*AHC*DT(I)/HLV/1000.0;
    else
        VR(I)=U*AHR*DT(I)/HLV/1000.0;
    end
end

% Calculate Distillate Mass for each stage
DL(1)=VR(1);
for I=2:NSTG-1
    DL(I)=DL(I-1)+VR(I);
end

% PI Controller - For adjusting the distillate flow rate in the simulation
Wd=Wdss+kc(2)*(RLDss-RLD)+kc(2)*ki(2)*sumLD;
sumLD=sumLD+(RLDss-RLD);

% State Equation Calculation
% Initial Stage
I=1;
% Brine Pool Mass Balance
DELTA(N0+I)=(B0-BR(I)-VR(I))*1000.0/RHOB/AB;

% Brine Poll Energy Balance
DELTA(N1+I)=B0*CPB*(TB0-TB(I));
DELTA(N1+I)=DELTA(N1+I)-VR(I)*(HV-CPB*(TB(I)-TREF));
DELTA(N1+I)=DELTA(N1+I)*1000.0/AB/RHOB/CPB/RL(I);

% Condenser Tube Energy Balance
DELTA(N2+I)=B0*CPF*(TF(I+1)-TF(I))*1000;
DELTA(N2+I)=DELTA(N2+I)+U*AHC*DT(I);
DELTA(N2+I)=DELTA(N2+I)/FMW/CPF;

% State Equations for Heat Recovery stages
for I=2:NREC
    % Mass Balance
    DELTA(N0+I)=(BR(I-1)-BR(I)-VR(I))*1000/RHOB/AB;
    
    % Energy Balance
    DELTA(N1+I)=BR(I-1)*CPB*(TB(I-1)-TB(I));
    DELTA(N1+I)=DELTA(N1+I)-VR(I)*(HV-CPB*(TB(I)-TREF));
    DELTA(N1+I)=DELTA(N1+I)*1000.0/AB/RHOB/CPB/RL(I);
    
    % Condenser Tube Energy Balance
    if(I==NREC)
        DELTA(N2+I)=B0*CPF*(TFREC-TF(I))*1000;
    else
        DELTA(N2+I)=B0*CPF*(TF(I+1)-TF(I))*1000;
    end
    DELTA(N2+I)=DELTA(N2+I)+U*AHC*DT(I);
    DELTA(N2+I)=DELTA(N2+I)/FMW/CPF;
end

% State Equations for Heat Rejection stages
for I=NREC+1:NSTG-1
    % Mass Balance
    DELTA(N0+I)=(BR(I-1)-BR(I)-VR(I))*1000/RHOB/AB;
    
    % Energy Balance
    DELTA(N1+I)=BR(I-1)*CPB*(TB(I-1)-TB(I));
    DELTA(N1+I)=DELTA(N1+I)-VR(I)*(HV-CPB*(TB(I)-TREF));
    DELTA(N1+I)=DELTA(N1+I)*1000.0/AB/RHOB/CPB/RL(I);	
    
    % Condenser Tube Energy Balance
    DELTA(N2+I)=WF*CPF*(TF(I+1)-TF(I))*1000;
    DELTA(N2+I)=DELTA(N2+I)+U*AHR*DT(I);
    DELTA(N2+I)=DELTA(N2+I)/FMW/CPF;
end

% Final Stage
I=NSTG;
% Mass Balance
DELTA(N0+I)=(BR(I-1)-Bd-VR(I)-B0+WMK)*1000/RHOB/AB;

% Energy Balance
DELTA(N1+I)=BR(I-1)*CPB*(TB(I-1)-TB(I));
DELTA(N1+I)=DELTA(N1+I)+WMK*CPB*(TF(NN1)-TB(I));
DELTA(N1+I)=DELTA(N1+I)-VR(I)*(HV-CPB*(TB(I)-TREF));
DELTA(N1+I)=DELTA(N1+I)*1000.0/AB/RHOB/CPB/RL(I);

% Condenser Tube Energy Balance
DELTA(N2+I)=WF*CPF*(TFEED-TF(I))*1000;
DELTA(N2+I)=DELTA(N2+I)+U*AHR*DT(I);
DELTA(N2+I)=DELTA(N2+I)/FMW/CPF;

% Brine Heater Equations
% Brine temperature in Brine heater
DTS=WS*HLV0/US/AS;
DELTA(N3+1)=(B0*(CPF*TF(1)-CPB0*TB0)*1000.0+US*AS*DTS)/FMC/CPF;

DELTA(N3+2)=(-Wd+DL(I-1)+VR(I))*1000/RHOB/AD;

return



