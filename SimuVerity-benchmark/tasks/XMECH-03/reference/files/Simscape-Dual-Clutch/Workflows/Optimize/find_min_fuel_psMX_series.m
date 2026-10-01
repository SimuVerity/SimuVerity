%% Dual Clutch Transmission - Optimization, 20 Parameters, patternsearch, Series Tests
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
% The script below uses an optimization algorithm to find shift map that
% maximizes fuel economy. The shift map is parameterized with 20
% parameters.  The tests are run sequentially on a single core so we can
% capture the results of each test and animate the evolution of the shift
% map.
%
% Copyright 2014-2025 The MathWorks, Inc.

%% Setup Optimization
% Setup model 
mdl = 'Dual_Clutch_Trans';
setup_model_optim_full

% Pre-generate rapid accelerator target
load_system(mdl);
rtp = Simulink.BlockDiagram.buildRapidAcceleratorTarget(mdl,'AddTunableParamInfo','on');
close_system(mdl);

% Offset parameters
delta0 = [10 12 12 10 10;...
    3  3  3  3  3;
    3  3  3  3  3;
    3  3  3  3  3];

% Reshape offsets into a vector so that it can be passed to the objective function
delta0_v = reshape(delta0,[],1);

% Shift boundaries must be separated to allow time to shift
% Shift boundaries must have a positive slope
%   Set lower bound for deltas (minimum difference between points)
LB = reshape([5 5 5 5 5;...
    1  1  1  1  1;
    1  1  1  1  1;
    1  1  1  1  1],[],1);

% Shift boundary lines must be separated by b
%   Create constraint for delta values according to Ax <= b
%   Delta(2,1) <= Delta(1,2) + Delta(2,2) + b
SubA = [0 1 0 0;0 1 1 0;0 1 1 1];
SubB = [-1 -1 0 0;-1 -1 -1 0;-1 -1 -1 -1];
Sub0 = zeros(size(SubA));

A =[SubA SubB Sub0 Sub0 Sub0;...
    Sub0 SubA SubB Sub0 Sub0;...
    Sub0 Sub0 SubA SubB Sub0;...
    Sub0 Sub0 Sub0 SubA SubB;...
    1 0 0 0 1 0 0 0 1 0 0 0 1 0 0 0 1 1 1 1];

mingdiff = -10; 
b = [mingdiff*ones(size(A,1)-1,1); 120];

% Plot initial shift map
[Upshift_Speeds, Downshift_Speeds, Pedal_Positions] = Calc_Shift_Map_DL(delta0,Pedal_Positions);
map_h=figure;
Plot_Gear_Shift_Schedule(Pedal_Positions,Upshift_Speeds,Downshift_Speeds);
set(gca,'XLim',[0 120])

%% Run optimization using parallel computing
%parpool;
%options = psoptimset('Vectorized','off','Display','iter','UseParallel','always',...
%    'TolMesh',0.0025,'CompletePoll','on','InitialMeshSize',0.05,'ScaleMesh','on');

% Run optimization without parallel computing

options = psoptimset('Vectorized','off','Display','iter','UseParallel','never',...
    'TolMesh',0.0025,'CompletePoll','on','InitialMeshSize',0.05,'ScaleMesh','on','MaxFunEvals',100);

DCT_minFuelOptResMX = [];

DCT_minFuelOptResMX.tableDeltas = delta0_v;
DCT_minFuelOptResMX.fuelUsed = 10;

% Call optimization function
tic;
[x,fval,exitflag,output] = ...
    patternsearch(@(x)obj_find_min_fuel_psMX(mdl,x,rtp,map_h,true),...
    delta0_v,A,b,[],[],LB,[],[],options);

Elapsed_Sim_Time = toc;
disp(['Elapsed Sim Time = ' num2str(Elapsed_Sim_Time)]);

% Update workspace variables with final values (based on x)
delta_final = reshape(x,4,[]);
[Upshift_Speeds_final, Downshift_Speeds_final, Pedal_Positions_final] = Calc_Shift_Map_DL(delta_final,Pedal_Positions);

% Save key results of optimization
%{
trans_var = get_param([mdl '/Dual Clutch Transmission'],'BlockChoice');
veh_var = get_param([mdl '/Vehicle Dynamics'],'BlockChoice');
solver_setting = get_param(mdl,'Solver');
if (strcmp(solver_setting,'ode23t'))
    solver_var = 'Desktop';
else
    solver_var = 'Real Time';
end

SaveVarName = ['OptPSMX_' trans_var(1:3) solver_var(1:3) '_DC' num2str(Drive_Cycle_Num)];

eval([SaveVarName '.delta0 = delta0;']);
eval([SaveVarName '.delta_final = delta_final;']);
eval([SaveVarName '.Elapsed_Sim_Time = Elapsed_Sim_Time;']);
eval([SaveVarName '.FuncCount = output.funccount;']);
eval([SaveVarName '.FuelUsedMin = fval;']);
eval([SaveVarName '.Variants.Transmission = ''' trans_var ''';']);
eval([SaveVarName '.Variants.Vehicle = ''' veh_var ''';']);
eval([SaveVarName '.Variants.SolverSettings = ''' solver_var ''';']);

save(SaveVarName, SaveVarName);
%}

%figure(2)
%Plot_Gear_Shift_Schedule(Pedal_Positions_final,Upshift_Speeds_final,Downshift_Speeds_final);
%set(gca,'XLim',[0 120])

%saveas(gcf,SaveVarName,'fig');

% Reset model -- remove settings specific to optimization
delete(gcp('nocreate'))
reset_model_optim

datestringfile = datestr(now,'yymmddHHMM');

save(['DCT_minFuelOptResMX_' datestringfile '.mat'], 'DCT_minFuelOptResMX');

%save DCT_minFuelOptResMX


