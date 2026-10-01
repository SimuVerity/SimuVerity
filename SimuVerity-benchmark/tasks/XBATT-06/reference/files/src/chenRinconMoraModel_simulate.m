clc
clear
clf

% -- Import Data
fn = 'data/data_test1.mat';
fn2 = 'data_cut/cdata_test1.mat';

switch 2
    case 1
        T = 5000;
        dt = 1e-0;
        n = round(T/dt);
        t = linspace(0,T,n)';
        load(fn)
        data.ic_interp = interp1(data.tc,data.ic,t);
        data.vc_interp = interp1(data.tc,data.vc,t);
        data.rc_interp = interp1(data.tc,data.rc,t);
    case 2
        load(fn2); 
        c_ind = 6;        
        dt = 1e-0;      
        data.tc = cdata(c_ind).t - cdata(c_ind).t(1);
        T = floor(data.tc(end));
        n = round(T/dt);
        t = linspace(0,T,n)';
        data.vc = cdata(c_ind).v;
        data.ic = cdata(c_ind).i;
        data.rc = cdata(c_ind).r;
        data.ic_interp = interp1(data.tc,data.ic,t);
        data.vc_interp = interp1(data.tc,data.vc,t);
        data.rc_interp = interp1(data.tc,data.rc,t);
end

% -- Input to Simulink model
simin.time = t;
simin.signals.values = data.rc_interp;
% simin.signals.dimensions = size(data.x(:,2));
% R_load = 0.4; %[t,0.4*ones(n,1)];

% -- Battery Lifetime
p.capacity = 25; % AH
p.f1 = 0.9; % cycle number correction factor
p.f2 = 0.9; % temperature correction factor
p.C_capacity = 3600*p.capacity*p.f1*p.f2;
p.R_selfDischarge = 1e12;

% -- fitting functions
f       = @(SOC,p)  p(1)*exp(p(2)*SOC) + p(3)*SOC.^3 + p(4)*SOC.^2 + p(5)*SOC + p(6);
g       = @(SOC,p)  p(1).*exp(p(2).*SOC) + p(3);
% gradf_p   = @(SOC,p)
% gradf_SOC   = @(SOC,p)

% -- Voltage-Current Characteristics from fitted Manufacturer data
ncells = 12;  % Number of cells used: 6S x2
k_V_oc = 1.03;
p.V_oc         = k_V_oc*ncells*[-0.6388,-48.7497,0.7153,-0.6260,0.4743,3.6115];
f(1,p.V_oc)
% -- Voltage-Current params to learn (initial conditions)
R_series0 =  0.0176725770193065; k_R_series = 1;
R_10 = 0.0300931359624154; k_R_1 = 1;
C_10 = 89; k_C_1 = 1;
R_20 = 0.019421970865732; k_R_2 = 1;
C_20 = 3506.11460380014; k_C_2 = 1;
R_30 = 0.019421970865732; k_R_3 = 1;
C_30 = 3506.11460380014; k_C_3 = 1;

% -- sequence 1
% k_C_2 = 1.6065
% k_R_1 = 0.6;
% k_R_2 = 0.6842
% k_R_series = 2.1;
% k_C_3 = 3.7842
% k_R_3 = 2.3;
% k_V_oc = 1.0287


% -- sequence 2
% k_C_2 = 1.572
% k_R_1 = 1.2535
% k_R_2 = 0.71904
% k_R_series = 0.19319
% k_C_3 = 10.629
% k_R_3 = 42.835
% k_V_oc = 1.0263

% -- sequence 3
% k_C_2 = 1.8128
% k_R_1 = 1.0467
% k_R_2 = 0.53614
% k_R_series = 0.30923
% k_C_3 = 12.941
% k_R_3 = 3.0334
% k_V_oc = 1.0166

% -- sequence 4
k_C_2 = 1.1658
k_R_1 = 1.0913
k_R_2 = 0.81949
k_R_series = 2.5976e-15
k_C_3 = 1000
k_R_3 = 3.4178e-09
k_V_oc = 1.0073
% CRM_paramEstimation/C_capacity:CRM_paramEstimation.C_capacity.vc = 0.44127;

% -- sequence 5
k_C_2 = 2.1337
k_R_1 = 1.0632
k_R_2 = 0.51122
k_R_series = 0.12736
k_C_3 = 1000
k_R_3 = 1.5288e-09
k_V_oc = 0.99947
% CRM_paramEstimation/C_capacity:CRM_paramEstimation.C_capacity.vc = 0.36943

p.R_series     = [0,0,R_series0*k_R_series];
p.R_1          = [0,0,R_10*k_R_1];
p.C_1          = [0,0,C_10*k_C_1];
p.R_2          = [0,0,R_20*k_R_2];
p.C_2          = [0,0,C_20*k_C_2];

R_series0*k_R_series
R_10*k_R_1
C_10*k_C_1
R_20*k_R_2
C_20*k_C_2
R_30*k_R_3
C_30*k_C_3

% -- Voltage-Current Characteristics from Chen-Rincon-Mora
% ncells = 12;
% p.V_oc         = ncells*[-1.031,-30,0.3201,-0.1178,0.2156,3.685];
% p.R_series     = [0.1562,-24.37,0.07446];
% p.R_1          = 0*[0.3208,-29.14,0.04669];
% p.C_1          = 0*[-600,-13.51,703.6];
% p.R_2          = 0*[6.603,-155.2,0.04984];
% p.C_2          = 0*[-3056,-27.12,4475];

% -- Get initial SOC
voc_0       = data.vc_interp(1)-0*0.7*ncells;  % percent*usableVolt/cell*ncells
SOC         = linspace(0,1,1000);
temp        = f(SOC,p.V_oc);
tempk       = find(temp <= voc_0,1,"last");
SOC_0       = SOC(tempk);

% -- Initialize Simulation Variables
switch c_ind
    case 1
        v.SOC         = 0.87998;%SOC_0; % sequence 1
    case 2
        v.SOC         = 0.735467282528717; %SOC_0;
    case 3
        v.SOC         = 0.561090954566274; %SOC_0;
    case 4
        v.SOC         = 0.44127; %0.39001671767703;
    case 5
        v.SOC         = 0.36943; %0.216492361981287;
    case 6
        v.SOC         = 0.1481462082476085;
end
v.V_oc        = f(v.SOC,p.V_oc);
v.R_series    = g(v.SOC,p.R_series);
v.R_1         = g(v.SOC,p.R_1);
v.C_1         = g(v.SOC,p.C_1);
v.R_2         = g(v.SOC,p.R_2);
v.C_2         = g(v.SOC,p.C_2);

%% Loop
format long g
dJ = 0;
J = 0;
ep = -10.^[-3,-2,-2,-2,-2];
nk = 1;
% R_series = linspace(0.01,0.07,nk);
tol = 1e-4;
for k=1:nk
    %     clc
    %     disp(k)
    %     p.R_series(3) = R_series(k);
    %out = sim("chenRinconMoraModel_paramEstimation.slx");
    out = sim("CRM_paramEstimation.slx");
    %
    % -- Extract data...
    y.t = out.simout.Time;% 0: time
    y.R_series = out.simout.Data(:,1);% 1: R_series
    y.R_1 = out.simout.Data(:,2);% 2: R_1
    y.C_1 = out.simout.Data(:,3);% 3: C_1
    y.R_2 = out.simout.Data(:,4);% 4: R_2
    y.C_2 = out.simout.Data(:,5);% 5: C_2
    y.SOC = out.simout.Data(:,6);% 6: SOC
    y.V_oc = out.simout.Data(:,7);% 7: Voc
    y.i = out.simout.Data(:,8);  % 8: i_bat
    y.V_L = out.simout.Data(:,9);% 9: V_L
    y.R_L = simin.signals.values;%10: R_L

    ylen = length(y.R_series);
    datalen = length(data.vc_interp);
    J(k) = sum((y.V_L(2:end)-data.vc_interp(1:ylen-1)).^2 +(y.i(2:end)-data.ic_interp(1:ylen-1)).^2);
    thet = [p.R_series(3),p.R_1(3),p.C_1(3),p.R_2(3),p.C_2(3)];
%     lam = 1e-4;
%     J(k) = J(k) + lam*sum(thet);
    if k==1
        dJ = ep(1).^2*randn();
    else
        dJ = J(k)-J(k-1);
    end

    if dJ == 0
        dJ = 0*0.01.^2*randn();
    end

        %     param_dir = randi(5);
        dk = mod(k,1)+1;
        switch dk
            case 1
                %randi(3);
                temp = p.R_series(3) + ep(dk)*dJ;
                            if temp > 0
                                p.R_series(3) = temp;
                            end
            case 2
                %randi(3);
                temp = p.R_1(3) + ep(dk)*dJ;
                            if temp > 0
                                p.R_1(3) = temp;
                            end
            case 3
                 %randi(3);
                temp = p.C_1(3) + ep(dk)*dJ;
                            if temp > 0
                                p.C_1(3) = temp;
                            end
            case 4
                 %randi(3);
                temp = p.R_2(3) + ep(dk)*dJ;
                            if temp > 0
                                p.R_2(3) = temp;
                            end
            case 5
                 %randi(3);
                temp = p.C_2(3) + ep(dk)*dJ;
                            if temp > 0
                                p.C_2(3) = temp;
                            end
            otherwise
        end
        clc
        thet = [p.R_series(3),p.R_1(3),p.C_1(3),p.R_2(3),p.C_2(3)];
        disp([k,thet,dJ]')
%         disp()
%         disp(p.R_1)
%         disp(p.C_1)
%         disp(p.R_2)
%         disp(p.C_2)
%         disp(dJ)
        % disp(param_dir)

%     end
    % Plots
    % -- Plot data...
    lw = 2;
    plot(data.tc,data.vc,'k','LineWidth',lw)
    hold on;
    plot(y.t(2:end),y.V_L(2:end),'r--','LineWidth',lw)
    yyaxis left
    ylim([40,52])
    hold off;
    yyaxis right
    plot(data.tc,data.ic,'b','LineWidth',lw)
    hold on
    plot(y.t(2:end),y.i(2:end),'g--','LineWidth',lw);
    hold off

    xlim([y.t(1),y.t(end)])

    legend('V_L experiment','V_L simulated','i_L experiment','i_L simulated')
    shg
end
% yyaxis right
% plot(simin.time,simin.signals.values,'g')
% ylim([0,8])
% set(gca,'YColor','g')
