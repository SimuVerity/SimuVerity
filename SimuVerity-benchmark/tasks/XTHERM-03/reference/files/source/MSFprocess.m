function [sys, x0] = MSFprocess(t,x,u,flag,param,fname)

% MSF - a Simuling S-Function
%{
Input:
    t,x,u,flag - Supplied by Simulink as per the S-Function specification
    t - Time
    x - State vector
    u - Input Vector. u = [B0 Tf Ws];
    flag - S-Function operation mode
    param - Input parameters vector on MSF block.
            param=[Us U Wf Rej Ts Wd LB LD N];
    fname - File containing initial condition of the states. 
            This is x68.inc in the included example.

Output:
    sys - Generic output vector. If flag is set to 3, sys is set to the
        System Output Vector. sys = [LB22, TB22, TB0, LD22, BD, Wd];
        Else if flag = 0, sys is set to the derivative of the state
        vector, a 68x1 vector.
    x0 - Initial State Values.

Index:
    u vector:
        Bo - Recycle brine flow rate
        Tf - Sea water feed temperature
        Ws - Steam flow rate

    param and dist vector:
        Us - Heat transfer coeff. of Brine Heater, kJ/min C m2
        U - Heat transfer coeff. of tube, kJ/min C m2
        Wf - Sea Water feed rate, (ton/hr)
        Rej - Reject flow rate, (ton/hr)
        Ts - Steam Temperature, (C)
        Wd - Initial condition for Distillate product and Blowdown. 
            1x2 vector.
        LB - Setpoint, proporional gain, integral time  for Brine level 
            control. 1x3 vector.
        LD - Setpoint, proportional gain, integral time for distillate 
            level control. 1x3 vector.
        N - Number of rejection and recovery stages. 1x2 vector.

    sys as an output vector:
        LB22 - Final stage brine level
        TB22 - Final stage brine temperature
        TB0 - Initial brine temperature
        LD22 - Final stage distillate level
        Bd - Blow down flow rate
        Wd - Distillate product flow rate
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

% Load input parameters [Us U Wf Rej Ts Wd LB LD] to dist
dist=param(1:13);

if abs(flag) == 1
  % Return state derivatives.
  sys = msfplant(x,u);

elseif abs(flag) == 3
  % Return system outputs.
  % If t is 0, call msfplant and set sumLB, sumLD
  if t==0; msfplant(x,u); sumLB=0; sumLD=0; end
  
  % Return output. Subtract 273 to return temperatures in Kelvin.
  sys = [x(22) x(44)-273 x(67)-273 x(68) Bd Wd];  

elseif flag == 0
  % Initalize the system
  
  % Load file containing initial condition of the states. 
  % This is x68.inc in the included example
  x0=load(fname);
  
  % Initial Output Vector
  sys = [68, 0, 6, 3, 0, 0];
  
  % Number of Heat Recovery and Rejection stages
  NREJ=param(14);
  NREC=param(15);
  
  % Set sumLB, sumLD to zero
  sumLB=0;
  sumLD=0;
  
  % Clear logged data variable (xout)
  %clear tout xout
else
  sys = [];  
end
