clear
clc

% -- Algorithm
% 1. load in experimental data, lookup table data, and fitted parameter data
% 2. Clean up database of unsued parameters
% 3. Create the simin data using the voltage and current.
% 4. Create output data and expand params for plotting


addpath data\ auxillary\

load 20230919_data_fit.mat

mp = struct(); %modelparams
mp.R0 = R0;
mp.R0Prime = R0Prime;
mp.R1 = R1;
mp.R1Prime = R1Prime;
mp.R2 = R2;
mp.R2Prime = R2Prime;
mp.R3 = R3;
mp.R3Prime = R3Prime;
mp.C1 = C1;
mp.C1Prime = C1Prime;
mp.C2 = C2;
mp.C2Prime = C2Prime;
mp.C3 = C3;
mp.C3Prime = C3Prime;
mp.CapacityAh = CapacityAh;
mp.CapacityAhPrime = CapacityAhPrime;
mp.Em = Em;
mp.EmPrime = EmPrime;
mp.InitialCapVoltage = InitialCapVoltage;
mp.InitialChargeDeficitAh = InitialChargeDeficitAh;
mp.SOC_LUT = SOC_LUT;
mp.SOC_LUTPrime = SOC_LUTPrime;
mp.thet = [thet0';thet1';thet2';thet3';thet4';thet5';thet6'];
mp.TempPrime = TempPrime;
mp.f = f;
mp.fn = [{'2022-07-29 10-38-55_f1.mat'},
    {'2022-08-04 10-58-30_f1.mat'}
    {'2022-08-04 10-58-30_f2.mat'}
    {'2022-08-08 10-44-35_f1.mat'}
    {'2022-08-10 09-40-57_f1.mat'}
    {'2022-09-26 11-49-08_f1.mat'}
    {'2022-10-21 13-31-20_f1.mat'}];
mp.j = 1;
load(char(mp.fn(mp.j)));
mp.i = i;
mp.v = v;
mp.t = t;

% -- clean up imported data
mp.i(isnan(mp.i))=0;
mp.t = mp.t - mp.t(1);

mp.R0prime = mp.f(mp.SOC_LUT,mp.thet(1,:));
mp.R1prime = mp.f(mp.SOC_LUT,mp.thet(2,:));
mp.R2prime = mp.f(mp.SOC_LUT,mp.thet(3,:));
mp.R3prime = mp.f(mp.SOC_LUT,mp.thet(4,:));
mp.C1prime = mp.f(mp.SOC_LUT,mp.thet(5,:));
mp.C2prime = mp.f(mp.SOC_LUT,mp.thet(6,:));
mp.C3prime = mp.f(mp.SOC_LUT,mp.thet(7,:));
mp.J = @(x,y) sum((x-y).^2,'omitnan');
mp.simulinkModel = "BatteryEstim3RC_PTBS_EQ_RUL_v1.slx";
mp.PLOT = 1;
save 20230919_data_modelparams_RUL mp 

clear
close all

load 20230919_data_modelparams
load 20230919_data_performance

% global mpg
% mpg = mp;
% xhat(mp.j,:) = fminsearchbnd(...
%         @(x) behaviorMatchingCostFunction(x),...
%         [19.1,0.6],...
%         [18,0.5],...
%         [25,1]);

mp.Em0 = max(mp.v);
mp.SOC_0 = interp1(mp.Em,mp.SOC_LUT,mp.Em0);
mp.CapacityAh =  xhat(mp.j,1);%24.1;%p(1,j);
mp.CapacityAhPrime = xhat(mp.j,1)*ones(1,2);
mp.InitialChargeDeficitAh = xhat(mp.j,2)*(1-mp.SOC_0)*mp.CapacityAh;%5.75;
Cavail = 24.1;
Cnom = 25;
X0 = (mp.CapacityAh - mp.InitialChargeDeficitAh)/Cnom;
XL = 0.031;
XNA = (Cnom - Cavail)/Cnom;

% mp = mpg;
% mpg = mp;

% switch 1
%     case 1
%         J = mp.J(mp.v,mp.v1c);
%     case 2
%         wlen = 10;
%         J = mp.J(movmean(mp.v,wlen),movmean(mp.v1c,wlen));
% end

%%
% -- init RUL params 
    i = mp.i; t = mp.t; v = mp.v;
    dt = [0;diff(t)];
    Xi = zeros(1,length(t));
    XRUL = Xi;
    tRUL = Xi;
    avg_i = 10;         % amps
    avg_tLand = 125;    % seconds     
    tRUL(1) = inf;      % assuming 0 current condition (ideal battery)    
        
    FLAG_LAND_EARLYWARNING  = 0;
    FLAG_LAND_NOW           = 0;
    idx_landearlywarn       = 1;
    idx_landnow             = 1;
    idx_landactual          = 10837;
    idx_landVTOL            = 11002;

for j=2:length(t)
    % -- set stop based on current time step
    mp.tstop = t(end);

    % -- set current for model to have real + avg expected current
    mp.itest = [i(1:j-1);avg_i*ones(length(t)-j+1,1)];

    % -- run simulation to current time step
    sim(mp.simulinkModel);
    clc
    disp(['step = ',num2str(j),', out of 11656'])

    % -- extract the data
    %mp.t1 = yout.getElement(1).Values.Time;
    %mp.v1 = yout.getElement(1).Values.Data;
    %mp.t2 = yout.getElement(4).Values.Time;
    %mp.v2 = yout.getElement(4).Values.Data;
    %mp.X1 = yout.getElement(2).Values.Data;
    %mp.X2 = yout.getElement(3).Values.Data;

    % -- Interpolate model voltage to frequency of input
    %mp.v1c = interp1(mp.t1,mp.v1,mp.t);
    %mp.v2c = interp1(mp.t2,mp.v2,mp.t);

    % -- Utilize Columb counting to estimate the consumed SOC
    Xi(j) = Xi(j-1) + i(j)*dt(j)/3600/Cnom;

    % -- Compute RUL SOC based on landing cost, consumed, and not avail SOC
    XRUL(j) = X0 - Xi(j) - XL - XNA;

    % -- Compute the time RUL left given a 10A average
    tRUL(j) = 3600*Cnom*XRUL(j)/avg_i;

    % -- find early warning and critical landing times
    if tRUL(j) <= 2*avg_tLand && ~FLAG_LAND_EARLYWARNING
        FLAG_LAND_EARLYWARNING = 1;
        idx_landearlywarn = j;
    elseif tRUL(j) <= avg_tLand && ~FLAG_LAND_NOW
        FLAG_LAND_NOW = 1;
        idx_landnow = j;
    end

end
%%

% -- modify for testing (w/o rerunning ^up there^ )
load 20230919_data_RUL.mat
temp = XRUL + XNA - 0.12;
temp = 3600*Cnom*temp/avg_i;

idx_landearlywarn = find(temp <= 2*avg_tLand,2,'first');
idx_landearlywarn = idx_landearlywarn(2);
idx_landnow = find(temp <= avg_tLand,2,'first');
idx_landnow = idx_landnow(2);

% -- test plot
figure(1)
clf
lw = 1.5;
ax1 = nexttile;
yyaxis left
plot(t,temp,'k.','LineWidth',lw)
hold on;
% plot(t(idx_landearlywarn),temp(idx_landearlywarn),'go','LineWidth',lw)
plot(t(idx_landVTOL),temp(idx_landVTOL),'kd','LineWidth',lw,'MarkerFaceColor','k')
patch([t(idx_landnow) t(idx_landnow) t(end) t(end) t(idx_landnow)],...
    [1400 -400 -400 1400 1400],'r','FaceAlpha',0.25);
patch([1 1 t(idx_landearlywarn) t(idx_landearlywarn) 1],...
    [1400 -400 -400 1400 1400],'g','FaceAlpha',0.25);
patch([t(idx_landearlywarn) t(idx_landearlywarn) t(idx_landnow) t(idx_landnow) t(idx_landearlywarn)],...
    [1400 -400 -400 1400 1400],'y','FaceAlpha',0.25);
% patch([t(idx_landearlywarn) t(idx_landearlywarn) t(idx_landearlywarn)+avg_tLand t(idx_landearlywarn)+avg_tLand t(idx_landearlywarn)],...
%     [1400 -400 -400 1400 1400],'g','FaceAlpha',0.5);
% patch([t(idx_landnow) t(idx_landnow) t(idx_landVTOL) t(idx_landVTOL) t(idx_landnow)],...
%     [1400 -400 -400 1400 1400],'y','FaceAlpha',0.5);
text(5100,1100,'Safe','Color','k')
text(5380,1100,'Danger','Color','k')
text(5700,1100,'Unsafe','Color','k')
txt = '\leftarrow VTOL landing';
text(t(idx_landVTOL)+10,temp(idx_landVTOL)+100,txt)
hold off
ylim([-400,1400])
ylabel('RUL(t)');
grid on
yyaxis right
plot(t,v,'b.')
ylim([40,46])
xlim([5000,t(end)])
ax = gca;
ax.YAxis(1).Color = 'k';
ax.YAxis(2).Color = 'b';
xlabel('flight time, s');
ylabel('V(t), V');
title('RUL vs time')
set(gca,'FontSize',14)

ax2 = nexttile;
plot(mp.SOC_LUT,mp.Em,'k','LineWidth',lw)
% hold on
% scatter(mp.X1,mp.v1,'r.')
% scatter(mp.X2,mp.v2,'g.')
% hold off

xlabel('state of charge');
ylabel('V_{oc}, V');
title('V_{oc} vs SOC curve')
set(gca,'FontSize',14)
% -- RUL plot vs time
% figure(1)
% yyaxis left
% plot(t,XRUL,'k')
% yyaxis right
% plot(t,Xi*Cnom,'r')
% ax = gca;
% ax.YAxis(2).Color = 'r';

% -- save images 
saveas(gcf,['RULimage_',num2str(mp.j)],'png')
saveas(gcf,['RULimage_',num2str(mp.j)],'fig')

