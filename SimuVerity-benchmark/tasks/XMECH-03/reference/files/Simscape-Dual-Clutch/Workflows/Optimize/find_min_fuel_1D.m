%% Dual Clutch Transmission - Optimization, One Parameter
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
% maximizes fuel economy. The shift map is parameterized with a single
% parameter to limit the design space.
%
% Copyright 2014-2025 The MathWorks, Inc.

%% Setup Optimization
% Setup model 
mdl = 'Dual_Clutch_Trans';
setup_model_optim

% Set initial value of shift map parameter
rampconst0 = 45;

% Pre-generate rapid accelerator target
load_system(mdl);
rtp = Simulink.BlockDiagram.buildRapidAcceleratorTarget(mdl,'AddTunableParamInfo','on');
close_system(mdl);

% Create plots of parameter sweep, initial shift map
setup_optim1D_plots

%% Run optimization
close all
setup_optim1D_plots

tic;
[x,fval,exitflag,output] = ...
    fminsearch(@obj_find_min_fuel_1D,rampconst0, ...
    optimset('Tolx',1e-3,'Display','iter','MaxIter',6),mdl,rtp,fuelUse_h,map_h);

disp(['Elapsed time for optimization = ' num2str(toc)]);

% Save final value of shift map parameter
rampconst_final = x;

% Reset model (remove settings only necessary for optimization)
reset_model_optim

% Plot detailed parameter sweep
%hold on
%figure(1);
%load FuelUsedSweep1D_AbsRea_161
%plot(FuelUsedSweep1D_AbsRea_161.rampconst(1:121),FuelUsedSweep1D_AbsRea_161.FuelUsedSET(1:121),'m');



