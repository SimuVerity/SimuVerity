% For detailed user guidance, go to https://github.com/Rchi666/EV_Truck_Model.git
%% Initial Value Setup
clear
clc
Veh_mass = 2885;              % Total mass of vehicle in kilograms
Power_option = 132;         % Three power options available: 95/132/150kW motor
Batt_soc_init = 1;                % Initial state of charge of the battery, set from 0 to 100%
Elec_aux_sw = 1;                 % Switch of auxiliary power consumption
Elec_rgn_sw = 1;                 % Switch of regenerative braking system
Run_number = 1;               % Identifier of run number
testrun = 'NEDC';               % Set simulation test cycle: NEDC/WLTP/CLTC/... Remember to select the test cycle and update simulation time first

%% Test Run
Simulink.sdi.view;
Simulink.sdi.clear;
sim("EV_Truck_Model.slx");      %Testrun to ensure proper settings
% remember to activate Fast Restart first!!
pause(5); 
Simulink.sdi.loadView('TempleteWLTP.mldatx');
pause(5);
Simulink.sdi.clear;

%% Start Simulation Loop
for m = 0:1
    if m ==0
        Veh_mass = 2885;
    else
        Veh_mass = 5885;
    end

    for p = 0:2
        if p == 0
            Power_option = 132;
        elseif p == 1
            Power_option = 150;
        else
            Power_option = 95;
        end
    
        for i = 0:1
%             if i == 0
%                     Batt_soc_init = 1.0;
%             elseif i == 1
            if i == 0
                Batt_soc_init = 0.95;
            else
                Batt_soc_init = 0.5;
            end
        
            for j = 0:1
                if j == 0
                    Elec_aux_sw = 1.0;
                else
                    Elec_aux_sw = 0;
                end
                
                for k = 0:1
                    if k == 0
                        Elec_rgn_sw = 1;
                    else
                        Elec_rgn_sw = 0;
                    end
        
                    X = [testrun  ,'Run_number: ', num2str(Run_number), ...
                             newline ,'     Power_option: ', num2str(Power_option), ...
                             newline ,'     Batt_soc_init: ', num2str(Batt_soc_init), ...
                             newline ,'     Elec_rgn_sw: ', num2str(Elec_rgn_sw), ...
                             newline ,'     Elec_aux_sw: ', num2str(Elec_aux_sw)];
                    disp(X);
                    runsim(Run_number, Power_option);       %Call out for simulation function
                    Run_number = Run_number+1;
                end
            end
        end
    end
end

% Save result of Simulink data inspector to .mldatx file
datafilename = [testrun,'_Result.mldatx'];

Simulink.sdi.save(datafilename);
%% Call Simulation Function
function [] = runsim(RN,PO)
% Open data inspector and run simulation
    sim("EV_Truck_Model.slx");
    pause(5);
    Simulink.sdi.loadView('TempleteWLTP.mldatx');
    pause(5);
% Take a snapshot from simulink data inspector
    fig = Simulink.sdi.snapshot;
    figfilename = ['WLTP_',num2str(PO),'kW_Run_',num2str(RN),'.png'];
    saveas(fig, figfilename);
    
end