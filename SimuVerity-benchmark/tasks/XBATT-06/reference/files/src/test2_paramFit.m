clear
clc

load 20230919_data.mat

% -- function to fit
f = @(SOC,p)  p(1)*exp(p(2)*SOC) + p(3)*SOC.^3 + p(4)*SOC.^2 + p(5)*SOC + p(6);


% -- simple function to fit
g = @(SOC,p)  p(1).*exp(p(2).*SOC) + p(6);

R1 = Rx(1,:);
R2 = Rx(2,:);
R3 = Rx(3,:);
C1 = Tx(1,:)./Rx(1,:);
C2 = Tx(2,:)./Rx(2,:);
C3 = Tx(3,:)./Rx(3,:);

% -- fit R0
R0p = rand(6,1);
J0 = @(R0p) sum((f(SOC_LUT,R0p)-R0).^2);
thet0 = fminsearch(J0,R0p);
ax0 = nexttile;
plot(R0,'k.'); hold on; plot(f(SOC_LUT,thet0),'r--'); hold off


% -- fit R1
R1p = rand(6,1);
J1 = @(R1p) sum((f(SOC_LUT,R1p)-R1).^2);
thet1 = fminsearch(J1,R1p);
ax1 = nexttile;
plot(R1,'k.'); hold on; plot(f(SOC_LUT,thet1),'r--'); hold off

% -- fit R2
R2p = rand(6,1);
J2 = @(R2p) sum((f(SOC_LUT,R2p)-R2).^2);
thet2 = fminsearch(J2,R2p);
ax2 = nexttile;
plot(R2,'k.'); hold on; plot(f(SOC_LUT,thet2),'r--'); hold off

% -- fit R3
R3p = rand(6,1);
J3 = @(R3p) sum((f(SOC_LUT,R3p)-R3).^2);
thet3 = fminsearch(J3,R3p);
ax3 = nexttile;
plot(R3,'k.'); hold on; plot(f(SOC_LUT,thet3),'r--'); hold off

% -- fit T1
T1p = rand(6,1);
J4 = @(T1p) sum((f(SOC_LUT,T1p)-C1).^2);
thet4 = fminsearch(J4,T1p);
ax4 = nexttile;
plot(C1,'k.'); hold on; plot(f(SOC_LUT,thet4),'r--'); hold off

% -- fit T2
T2p = rand(6,1);
J5 = @(T2p) sum((f(SOC_LUT,T2p)-C2).^2);
thet5 = fminsearch(J5,T2p);
ax5 = nexttile;
plot(C2,'k.'); hold on; plot(f(SOC_LUT,thet5),'r--'); hold off

% -- fit T3
T3p = rand(6,1);
J6 = @(T3p) sum((f(SOC_LUT,T3p)-C3).^2);
thet6 = fminsearch(J6,T3p);
ax6 = nexttile;
plot(C3,'k.'); hold on; plot(f(SOC_LUT,thet6),'r--'); hold off


% combine params
thet = [thet0,thet1,thet2,thet3,thet4,thet5,thet6]';

% zero out the g function params
thet(1:end,3:5) = 0;

% write to csv
writematrix(thet,'20230919_paramfitdata.csv')
save 20230919_data_fit