%% Dual Clutch Transmission - Optimization, 2 Parameters, Patternsearch
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
% to limit the design space. The optimization algorithm used is patternsearch.
%
% Copyright 2014-2025 The MathWorks, Inc.

%% Setup Optimization
% Setup model 
mdl = 'Dual_Clutch_Trans';
setup_model_optim

% Set initial value of shift map parameters
rampconst0 = 35;
mingeardiff0 = 18;

% Pre-generate rapid accelerator target
load_system(mdl);
rtp = Simulink.BlockDiagram.buildRapidAcceleratorTarget(mdl,'AddTunableParamInfo','on');
close_system(mdl);

% Create plots of parameter sweep, initial shift map
setup_optim2D_plots

%% Run optimization 
close all
setup_optim2D_plots

% using parallel computing
%parpool;
%options = psoptimset('Vectorized','off','Display','iter','UseParallel','always',...
%    'TolMesh',0.0025,'CompletePoll','on','InitialMeshSize',0.05,'ScaleMesh','on');

% Run optimization without parallel computing
options = psoptimset('Vectorized','off','Display','iter','UseParallel','never',...
    'TolMesh',0.0025,'CompletePoll','on','InitialMeshSize',0.05,'ScaleMesh','on');

% Run optimization
tic;
[x,fval,exitflag,output] = ...
    patternsearch(@(x)obj_find_min_fuel_2D(x,mdl,rtp,fuelUse_h,map_h),...
    [mingeardiff0 rampconst0],[],[],[],[],[16 0],[20 60],[],options);

Elapsed_Sim_Time = toc;
disp(['Elapsed Sim Time = ' num2str(Elapsed_Sim_Time)]);

% Save key results of optimization
%{
mingeardiff_final = x(1);
rampconst_final = x(2);

OptPS2D.rampconst0 = rampconst0;
OptPS2D.rampconst_final = rampconst_final;
OptPS2D.mingeardiff0 = mingeardiff0;
OptPS2D.mingeardiff_final = mingeardiff_final;
OptPS2D.Elapsed_Sim_Time = Elapsed_Sim_Time;
OptPS2D.FuncCount = output.funccount;
OptPS2D.FuelUsedMin = fval;

save OptPS2D OptPS2D

figure(1)
saveas(gcf,'OptPS2D_Mesh','fig');
%}

% Reset model InitFcn -- only necessary for optimization
%delete(gcb);
reset_model_optim
