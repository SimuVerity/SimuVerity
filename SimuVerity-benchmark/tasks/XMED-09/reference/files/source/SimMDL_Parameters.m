clear all
dt_step   = 1e-3;
end_t   = 60;
T = 0:dt_step:end_t;
n = length(T);

HR=130; %Change heart rate here 100-160 bpm
deltastar=0.5;
Tc= 60/HR;
Tas = 0.03+0.09*Tc;
Tvs = 0.16+0.20*Tc;
Tav=0.01;
Tavi= Tas+Tav;
Tavf=Tas+Tav+Tvs;
ts_VAD = 0.5; %Ejection time as a fraction of Tc
VAD_delay=ts_VAD;
t_eject = (Tc*ts_VAD)/dt_step; % Ejection time for VAD in fill-to-empty operation
for k = 1:n
   j = mod(T(k), Tc);
   Kn(k) = ((j-(Tas + Tav))/Tvs)*sin((pi*(j-(Tas + Tav))/Tvs));
end
Kn = max(Kn);

deltaR = zeros(n,1);
aux = 0;
t_eject_i = (Tc*ts_VAD)/dt_step; % Ejection time for VAD in fill-to-empty operation

for i = 1:n
    if i >= aux*(60/HR)/dt_step %1 Time period of heartbeat in terms of passo
        aux = aux + 1;
        deltaR(i) = 1;
    end
end

if deltaR(i) == 1 % R-wave detection ()
    j = 0;
    num_R = num_R + 1; % Counter of the cardiac cycles
    aux_deltapDAV = 1; % Auxiliary variable to activate the pVAD ejection
end

%% Elastances:
% Maximum and Minimum Elastance:
Elamax = 1.99;
Elamin = 0.733;

Eramax = 0.63;
Eramin = 0.317;

Elvmax = 28.4; % [HEALTHY]
%Elvmax = 9; % [SICK]
Elvmin = 0.550;

Ervmax = 2.09;
Ervmin = 0.348;

%% Compliances and Initial Volumes:
% Compliances:
Cpv = 1/0.247;
Cpa = 1/1.27;
Csai = 1/7.76;
Csae = 1/3.02;
Csve = 1/0.0918;
Csvi = 1/0.0989;

% Unstressed Volumes
Vlvu = 2.0; % [HEALTHY]
Vlau = 1.0; % [HEALTHY]
%Vlvu = 10.0; % [SICK]
% Vlau = 3.0; % [SICK]
Vrvu = 3.0; 
Vrau = 1.5; 



%Initial Pressures
%psai0 = 75;  %60 
pao0  = 60;
psae0 = 70;
psve0 = 8.7;

psvi0 = 6;
ppa0  = 8.5;
ppv0  = 8;  %Healthy-6.3 Sick-8
qsae0 = 10;

pla0  = 0;
plv0  = 0;
pra0  = 0;
prv0  = 0;
pbc0  = 0;
pac0  = 0;

qla0  = 0;
qmv0  = 0;
qsai0 = 0;
qsp0  = 0;
qsve0 = 0;
qsvi0 = 0;
qra0  = 0;
qtv0  = 0;
qpa0  = 0;
qpp0  = 0;
qi0   = 0;
qo0   = 0;

Dt0 = 1;
Dp0 = 0;
Dm0 = 1;
Da0 = 0;

%% Volume (stressed)
vrv0 = 26.99; %21.7221; 
vlv0 = 15.6126; %19.82; %
vra0 = 22.36; %22.1937;  
vla0 = 11.2524; %12.51; %





%% Resistances and Inertances

Rt = 0.006;
% Left Atrium
Rpv = 0.006;
Rm = 0.006;

% Left Ventricle
Rsai = 0.016;

% Systemic Circulation
Lsae = 0.0002;
Rsae = 0.120;
Rsp = 2.00;
Rsve = 0.18;

% Right Atrium
Rsvi = 0.006;
Rtv = 0.006;

% Right Ventricle
Rpa = 0.006;

%Circulação pulmonar
Rpp = 0.220;

% Pressão torácica
Pth = -3.25;

Pabd=0;



%pVAD
Ri  = 0.4283;
Ro  = 1.2841;
Rac = 0.0025;

Li = 0.0402;
Lo = 0.0426;

Cbc = 0.25;
Cac = 13.7054;

%Goodwin2004
%Cardiac Output
CO_min = 1.2;
CO_max = 2;
CO_base = 1.8;

%Systemic Pressures
P_DP = 57;
P_SP = 86;
MAP = P_DP+(1/3)*(P_SP-P_DP);

%LVAD-Test-Simulations-Hunsbergeraz
Rp_lvad = 0.05;
Lp_lvad = 0.0033;
Cp_lvad =2; %In Coredeiro, in Huns its varying.
Pi_lvad=8;
Pe_lvad=8;
Pd_lvad=0;
Rs_lvad=0.83;
Cs_lvad=2.896;
alpha=0.15;

%pVAD Driver Huns
Cd_driver=4;
Rd_driver=0.01;

% %pVAD Driver Sousa
% Cac=0.1370;
% Rac=0.25;
% 
% %pVAD sousa
% Li=0.04;
% Lo=0.04;
% Ro=1.3;
%Ri=0.5;
alpha1=1;
% Cbc= 0.2521;
V_eject=15;

Vbc_min=24;
Vbc_max=33;

%Trigger 
delay=0.5*Tc;

% %% Baroreflex-Liu
% %%Afferent neural pathway
% Tau_p=2.076;
% Tau_z=6.37;
% f_min=2.52;
% f_max=47.78;
% pn=30;%Healthy:92
% ka=11.758; %Healthy: 11.758
% 
% %%Efferent neural pathway
% f_es_inf=2.1;
% f_ev_inf=6.3;
% k_es=0.0675;
% f_as_0=25;
% f_es_0=16.11;
% f_ev_0=3.2;
% k_ev=7.06;
% 
% %%Effector
% G_R_svr=0.36;
% G_E_max_lv=0.475;
% G_E_max_rv=0.282;
% G_Ts=-0.13;
% G_Tv=0.03;%0.09
% Tau_R_svr=6;
% Tau_E_max_lv=8;
% Tau_E_max_rv=8;
% Tau_Ts=2;
% Tau_Tv=1.5;
% D_R_svr=2;
% D_E_max_lv=2;
% D_E_max_rv=2;
% D_Ts=2;
% D_Tv=0.2;
% f_es_min=2.66;

%% Initial Arterial Pressure
psai0 = 75;

%% Baroreflex model Ursino2003
Vln=2.3; %Litres
Psan=75; %mmHg 95

%Heart Period
GaTv=0.028; %mmHg^-1 0.028 putting=0 removes the fluctuation
GaTs=0.015; %mmHg^-1 0.015 putting=0 removes the fluctuation
GpTv=0.25; %L^-1
GpTs=0; %L^-1
T_min=0.395; %seconds % 0.558
T_max=0.535; %seconds 1.308
DTv=0.5; %Seconds
DTs=3*(Tc/0.833); %seconds
Tau_Ts=1.8;%seconds
Tau_Tv=0.8;%seconds
STo=1; %Slope of the sigmoidal curve at center(alteration of sinus-node sensitivity to vag/sym)
kT=(T_max-T_min)/(4*STo);

%Rsp
Ga_Rsp=0.1; %mmHg^-1 0.1
Gp_Rsp=0.33; %l^-1
Rsp_min=1.5; %mmHg.s.ml^-1
Rsp_max=3; %mmHg.s.ml^-1
DRsp=3*(Tc/0.833); %Seconds
Tau_Rsp=1.5;%seconds
SRspo=1; %Sensitivity to sympathetic activity
k_Rsp=(Rsp_max-Rsp_min)/(4*SRspo);

%Erv
Ga_Erv=0.012; %mmHg^-1 0.1
Gp_Erv=0; %l^-1
Erv_max_thres=0.8*Ervmax; %mmHg.s.ml^-1
Erv_max_sat=1.2*Ervmax; %mmHg.s.ml^-1
DErv=2*(Tc/0.833); %Seconds
Tau_Erv=1.5;%seconds
SErvo=1; %Sensitivity to sympathetic activity
k_Erv=(Erv_max_sat-Erv_max_thres)/(4*SErvo);

%Elv
Ga_Elv=0.012; %mmHg^-1 0.1
Gp_Elv=0; %l^-1
Elv_max_thres=0.8*Elvmax; %mmHg.s.ml^-1
Elv_max_sat=1.2*Elvmax; %mmHg.s.ml^-1
DElv=2*(Tc/0.833); %Seconds
Tau_Elv=1.5;%seconds
SElvo=1; %Sensitivity to sympathetic activity
k_Elv=(Elv_max_sat-Elv_max_thres)/(4*SElvo);







% %% Baroreflex Goodwin/Couto
% mPsai_op= 82;
% HP_op=Tc*1000;
% mPsai_op_lamb=75;
% mPsai_lamb_thres=60;
% mPsai_lamb_sat=92;
% mPsai_thres=mPsai_lamb_thres*(mPsai_op/mPsai_op_lamb);
% mPsai_sat=mPsai_lamb_sat*(mPsai_op/mPsai_op_lamb);
% HP_gain=10.23;
% HP_min=HP_op-HP_gain*(mPsai_op-mPsai_thres);
% HP_max=HP_op+HP_gain*(mPsai_sat-mPsai_op);
% 

%Sliding mode Parameters Timeseries
% tune_lambda1=[0,2];
% tune_lambda2=[0,1];
% tune_gamma=[0,15];
% tune_nu=[0,10];
% tune_alpha=[0,1];

%Sliding mode Parameters constants intial
% tune_lambda1=2;
% tune_lambda2=1;
% tune_gamma=15;
% tune_nu=10;
% tune_alpha=1;

%% Sliding mode Parameters constants GA 14 gen ITAE
x=[2.80726784416043,0.849989015326732,14.8336742411938,10.4274455916650,0.708430135156437]; %Baroreflex+8 Gen GA
tune_lambda1=x(1);%1.9556;
tune_lambda2=x(2);%1.2546;
tune_gamma=x(3);%13.5469;
tune_nu=x(4);%13.4221;
tune_alpha=x(5);%1.1860;



%% PD parameters %14 Generation run
de_gain=1.5;  %Tuned for other ref 1.5
e_gain=2;     %Tuned for other ref 2 |2
%CVS_LVAD_TUNE_SM(x)

%% Cord2020's Controller
num = [1.0000    2.3082   -0.1752    0.0017];
b0 =  num(1);
b1 =  num(2);
b2 =  num(3);
b3 =  num(4);

den = [1.0000   -0.4633   -0.9876    0.4509];
a0 =  den(1);
a1 =  den(2);
a2 =  den(3);
a3 =  den(4);