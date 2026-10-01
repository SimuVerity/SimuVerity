clear 
clc

% syms V s C1 C2 V01 V02 RS RL R1 R2
% I = (V*(1+s*R1*C1)*(1+s*R2*C2) - V01*R1*C1*(1+s*R2*C2) -... 
%      V02*R2*C2*(1+s*R1*C1)) / ((RS + RL)*(1+s*R1*C1)*(1+s*R2*C2) + R1 + R2);
% 
% syms X0 R C
% X = (X0-I/C)/(s+1/R*C);
% 
% %%
% pretty(expand(I))
% 
% %%
% pretty(expand(X))

% -- variables: SOC loop
X0 = 1;
C = 0.01;
R = 0.01;

% -- variables: Voc loop
Rs = 0.01;
RL = 1;
R1 = 0.01;
C1 = 400;
R2 = 0.01;
C2 = 600;
T1 = R1*C1;
T2 = R2*C2;
V = 50;
V01 = 0;
V02 = 0;

% -- build coefficients for transfer functions
a(1) = R1 + R2 + Rs + RL;
a(2) = (Rs+RL)*(T1+T2);
a(3) = T1*T2*(RL+Rs);
b(1) = T1*T1*V;
b(2) = (T1+T2)*V - T1*T2*(V01+V02);
b(3) = V - T1*V01 - T2*V02;
c(1) = C^2/R*(R1+R2+RL+Rs);
c(2) = C*(R1+R2+RL+Rs) + C^2/R*((T1+T2)*(Rs+RL));
c(3) = C*((T1+T2)*(Rs+RL)) + C^2/R*(T1*T2*(RL+Rs));
c(4) = C*T1*T2*(RL+Rs);
d(1) = -V + T1*V01 + T2*V02;
d(2) = -V*(T1+T2)+T1*T2*(V01+V02);
d(3) = -T1*T2*V;

%%
out = sim("CRM_model_simulinkVersion.slx");

plot(out.tout,out.selfDischarge_SOC.Data)
