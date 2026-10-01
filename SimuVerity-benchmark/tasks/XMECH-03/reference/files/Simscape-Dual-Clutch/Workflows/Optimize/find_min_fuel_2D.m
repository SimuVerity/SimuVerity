%% Dual Clutch Transmission - Optimization, 2 Parameters, fminsearch
%
% This example shows a vehicle with a five-speed automatic dual-clutch
% transmission. The transmission controller converts the pedal deflection
% into a demanded torque. This demanded torque is then passed to the engine
% management. The pedal deflection and the vehicle speed are also used by
% the transmission controller to determine when the gear shifts should
% occur. Gear shifts are implemented via the two clutches, one clutch
% pressure being ramped up as the other clutch pressure is ramped down.
% Gear pre-selection via dog clutches ensures that the correct gear is
% fully selected before the on-going clutch is enabled.
% 
% The script below uses optimization algorithms to find shift map that
% maximizes fuel economy. The shift map is parameterized with 2 parameters
% to limit the design space. The optimization algorithm used is fminsearch.
%
% Copyright 2014-2025 The MathWorks, Inc.

%% Setup Optimization
% Setup model 
mdl = 'Dual_Clutch_Trans';
setup_model_optim

% Set initial value of shift map parameters
rampconst0 = 36;
mingeardiff0 = 19;

% Pre-generate rapid accelerator target
load_system(mdl);
rtp = Simulink.BlockDiagram.buildRapidAcceleratorTarget(mdl,'AddTunableParamInfo','on');
close_system(mdl);

% Create plots of parameter sweep, initial shift map
setup_optim2D_plots

%% Run optimization 
close all
setup_optim2D_plots

% Run optimization without parallel computing
tic;
[x,fval,exitflag,output] = ...
    fminsearch(@obj_find_min_fuel_2D,[mingeardiff0 rampconst0], ...
    optimset('Tolx',1e-3,'Display','iter'),mdl,rtp,fuelUse_h,map_h);

Elapsed_Sim_Time = toc;
disp(['Elapsed Sim Time = ' num2str(Elapsed_Sim_Time)]);

% Save key results of optimization
%{
mingeardiff_final = x(1);
rampconst_final = x(2);

OptFm2D.rampconst0 = rampconst0;
OptFm2D.rampconst_final = rampconst_final;
OptFm2D.mingeardiff0 = mingeardiff0;
OptFm2D.mingeardiff_final = mingeardiff_final;
OptFm2D.Elapsed_Sim_Time = Elapsed_Sim_Time;
OptFm2D.FuncCount = output.funcCount;
OptFm2D.FuelUsedMin = fval;

save OptFm2D OptFm2D

figure(1)
saveas(gcf,'OptFm2D_Mesh','fig');
%}

% RESET MODEL InitFcn -- ONLY NECESSARY FOR OPTIMIZATION
reset_model_optim





