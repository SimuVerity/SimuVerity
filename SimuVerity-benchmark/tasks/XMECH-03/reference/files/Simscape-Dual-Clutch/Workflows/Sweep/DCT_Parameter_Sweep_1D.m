%% Dual Clutch Transmission - Parameter Sweep, 1 Parameter, Parallel Computing
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
% Short sweep
rampconst = 0:10:70;

% Detailed sweep
%rampconst = 0:0.5:80;

mingeardiff = 17;
%[SimSettings,rc,mg] = Generate_Sim_Settings(rampconst,mingeardiff,rtp);

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

figure(1);
%set(gcf,'Position',[11   356   545   293]);
plot(rampconst,[simOut.FuelUsedLiters],'b-.o','LineWidth',2,'MarkerFaceColor','b');
title('Fuel Use With Varying Shift Schedule','FontWeight','Bold','FontSize',14);
xlabel('Shift Schedule Parameter','FontWeight','Bold','FontSize',12);
ylabel('Fuel Used (L)','FontWeight','Bold','FontSize',12);
legend('Parameter Sweep','Location','NorthWest');


clear rampconst mingeardiff

% Close parallel pool
delete(gcp);
bdclose(mdl);
%delete('*.mex*')
%!rmdir slprj /S/Q
delete([mdl '.slx']);

