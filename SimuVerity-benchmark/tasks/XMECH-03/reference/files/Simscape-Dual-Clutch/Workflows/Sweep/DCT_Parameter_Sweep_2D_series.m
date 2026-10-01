%% Dual Clutch Transmission - Parameter Sweep, 1 Parameter, Series Runs
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
% The script below uses varies the shift map to see the impact on fuel
% economy. The shift map is parameterized with 1 parameter to limit the
% design space. The sweep is run on a single core so that we can capture
% the shift map at each test and animate the evolution of the map.
%
% Copyright 2014-2025 The MathWorks, Inc.

%% Model

open_system('Dual_Clutch_Trans')

set_param(find_system('Dual_Clutch_Trans','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Run Parameter Sweep

orig_mdl = 'Dual_Clutch_Trans';
mdl = [orig_mdl '_pct_temp']; % Normally would add suffix for PCT copy
open_system(orig_mdl);
save_system(orig_mdl,[pwd filesep mdl]);

setup_model_param_sweep

% Generate parameter sets

% Quick test
%mingeardiff = 16:1.25:20;
%rampconst = 0:15:60;

% For comparing methods/solvers
mingeardiff = 16:1:20;
rampconst = 0:5:60;

% Detailed sweep
%mingeardiff = 16:0.2:20;
%rampconst = 0:1:60;

%[SimSettings,rc,mg] = Generate_Sim_Settings(rampconst,mingeardiff,rtp);
pSetNum = 0;
for rc_i = 1:length(rampconst)
    for mgd_i = 1:length(mingeardiff)
        pSetNum = pSetNum+1;
        rc(pSetNum) = rampconst(rc_i);
        mg(pSetNum) = mingeardiff(mgd_i);
    end
end

%numSims = length(SimSettings);
%out = cell(1, numSims);
numSims = pSetNum;

% Variable for saving results
clear FuelUsedSET

% Run simulations
tic;
for run_i = 1:numSims
    % CALCULATE NEW SHIFT MAP
    [Upshift_Speeds Downshift_Speeds Pedal_Positions] = Calc_Shift_Map_RO(rc(run_i),mg(run_i));
    
    figure(2)
    Plot_Gear_Shift_Schedule(Pedal_Positions, Upshift_Speeds, Downshift_Speeds);
    set(gca,'XLim',[0 100]);
    
    %disp(['Simulating with rampconst = ' num2str(rampconst(run_i))]);
    %out{run_i} = sim(mdl,SimSettings{run_i});
    %disp(['FINISHED with rampconst = ' num2str(rampconst(run_i)) ' Fuel Used = ' num2str(FuelUsedLiters)]);
    sim(mdl)
    FuelUsedSET_v(run_i) = FuelUsedLiters;
end
Elapsed_Sim_Time = toc;
disp(['Elapsed Sim Time = ' num2str(Elapsed_Sim_Time)]);

% Plot results
out_i = 0;
for rc_i=1:length(rampconst)
    for mg_i=1:length(mingeardiff)
        out_i = out_i+1;
        %FuelUsedSET(mg_i,rc_i) = out{out_i}.find('FuelUsedLiters');
        FuelUsedSET(mg_i,rc_i) = FuelUsedSET_v(out_i);
    end
end

figure;
set(gcf,'Position',[104   78   560   420]);
[rc_array, mgd_array] = meshgrid(rampconst,mingeardiff);
mesh(mgd_array,rc_array,FuelUsedSET);
%surf(mgd_array,rc_array,FuelUsedSET);
title('Fuel Use With Varying Shift Schedule','FontWeight','Bold','FontSize',14);
xlabel('Offset Parameter','FontWeight','Bold','FontSize',12);
ylabel('Ramp Parameter','FontWeight','Bold','FontSize',12);
zlabel('Fuel Used (L)','FontWeight','Bold','FontSize',12);
legend('Parameter Sweep','Location','NorthWest');

%save FuelUsedSET_Sweep2D_AbsDes FuelUsedSET rampconst mingeardiff
%clear rampconst mingeardiff FuelUsedSET


% Save results
trans_var = get_param([mdl '/Dual Clutch Transmission'],'LabelModeActiveChoice');
veh_var = get_param([mdl '/Vehicle Dynamics'],'LabelModeActiveChoice');
solver_setting = get_param(mdl,'Solver');
if (strcmp(solver_setting,'ode23t'))
    solver_var = 'Desktop';
else
    solver_var = 'Real Time';
end

SaveVarName = ['FuelUsedSweep2D_' trans_var(1:3) solver_var(1:3) '_' num2str(numel(FuelUsedSET))];
eval([SaveVarName '.FuelUsedSET = FuelUsedSET;']);
eval([SaveVarName '.rampconst = rampconst;']);
eval([SaveVarName '.mingeardiff = mingeardiff;']);
eval([SaveVarName '.Elapsed_Sim_Time = Elapsed_Sim_Time;']);
eval([SaveVarName '.Variants.Transmission = ''' trans_var ''';']);
eval([SaveVarName '.Variants.Vehicle = ''' veh_var ''';']);
eval([SaveVarName '.Variants.SolverSettings = ''' solver_var ''';']);

save(SaveVarName, SaveVarName);

clear rampconst mingeardiff FuelUsedSET

% Reset model and close pool
reset_model_param_sweep

% Reset model and close pool
bdclose(mdl);
%delete('*.mex*')
%!rmdir slprj /S/Q
delete([mdl '.slx']);
