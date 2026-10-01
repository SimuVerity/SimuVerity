%% Dual Clutch Transmission - Parameter Sweep, 2 Parameter, Parallel Computing
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
% economy. The shift map is parameterized with 2 parameters to limit the
% design space. 
%
% Copyright 2014-2025 The MathWorks, Inc.

%% Model

open_system('Dual_Clutch_Trans')

set_param(find_system('Dual_Clutch_Trans','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Run Parameter Sweep

% Open and configure model
cd(fileparts(which(mfilename)));
orig_mdl = 'Dual_Clutch_Trans';
mdl = [orig_mdl '_pct_temp']; % Normally would add suffix for PCT copy
open_system(orig_mdl);
save_system(orig_mdl,[pwd filesep mdl]);

setup_model_param_sweep

% Generate parameter sets

% Quick test
mingeardiff = 16:1.25:20;
rampconst = 0:15:60;

% For comparing methods/solvers
%mingeardiff = 16:1:20;
%rampconst = 0:5:60;

% Detailed sweep
%mingeardiff = 16:0.2:20;
%rampconst = 0:1:60;

pSetNum = 0;
for rc_i = 1:length(rampconst)
    for mgd_i = 1:length(mingeardiff)
        pSetNum = pSetNum+1;
        [Upshift_Speeds, Downshift_Speeds, Pedal_Positions] = Calc_Shift_Map_RO(rampconst(rc_i),mingeardiff(mgd_i));

        simInput(pSetNum) = Simulink.SimulationInput(mdl);
        simInput(pSetNum) = simInput(pSetNum).setVariable('Upshift_Speeds',Upshift_Speeds);
        simInput(pSetNum) = simInput(pSetNum).setVariable('Downshift_Speeds',Downshift_Speeds);
        rc(pSetNum) = rampconst(rc_i);
        mg(pSetNum) = mingeardiff(mgd_i);
    end
end

% Run simulations
simOut = parsim(simInput,...
    'ShowProgress','on',...
    'UseFastRestart','on',...
    'ShowSimulationManager','on',...
    'TransferBaseWorkspaceVariables','on');

% Plot results
out_i = 0;
for rc_i=1:length(rampconst)
    for mg_i=1:length(mingeardiff)
        out_i = out_i+1;
        FuelUsedSET(mg_i,rc_i) = simOut(out_i).FuelUsedLiters;
        logsout_i = simOut(out_i).logsout_Dual_Clutch_Trans;
        testData_i(out_i)  = logsout_i.get('Vehicle_Speed');
    end
end

% Reuse figure if it exists, else create new figure
if ~exist('h5_Dual_Clutch_Trans', 'var') || ...
        ~isgraphics(h5_Dual_Clutch_Trans, 'figure')
    h5_Dual_Clutch_Trans = figure('Name', 'Dual_Clutch_Trans_2D_Sweep');
end
figure(h5_Dual_Clutch_Trans)
clf(h5_Dual_Clutch_Trans)

set(gcf,'Position',[104   78   560   420]);
[rc_array, mgd_array] = meshgrid(rampconst,mingeardiff);
mesh(mgd_array,rc_array,FuelUsedSET);
%surf(mgd_array,rc_array,FuelUsedSET);
title('Fuel Use With Varying Shift Schedule','FontWeight','Bold','FontSize',14);
xlabel('Offset Parameter','FontWeight','Bold','FontSize',12);
ylabel('Ramp Parameter','FontWeight','Bold','FontSize',12);
zlabel('Fuel Used (L)','FontWeight','Bold','FontSize',12);
legend('Parameter Sweep','Location','NorthWest');

% Reuse figure if it exists, else create new figure
if ~exist('h6_Dual_Clutch_Trans', 'var') || ...
        ~isgraphics(h6_Dual_Clutch_Trans, 'figure')
    h6_Dual_Clutch_Trans = figure('Name', 'Dual_Clutch_Trans_2D_Sweep');
end
figure(h6_Dual_Clutch_Trans)
clf(h6_Dual_Clutch_Trans)
out_i = 0;
for rc_i=1:length(rampconst)
    for mg_i=1:length(mingeardiff)
        out_i = out_i+1;
        logsout_i = simOut(out_i).logsout_Dual_Clutch_Trans;
        testData_i  = logsout_i.get('Engine_Speed');
        plot(testData_i.Values.Time,testData_i.Values.Data)
        hold on
        legend_str{out_i} = ['Test ' num2str(out_i)];
    end
end
hold off
title('Engine Speed With Varying Shift Schedule');
ylabel('Engine Speed (rpm)');
xlabel('Time (s)');
legend(legend_str,'Location','East');

% Save results
% Uncomment to save results
%{
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
%}

clear rampconst mingeardiff FuelUsedSET

% Reset model and close pool
delete(gcp);
bdclose(mdl);
%delete('*.mex*')
%!rmdir slprj /S/Q
delete([mdl '.slx']);

