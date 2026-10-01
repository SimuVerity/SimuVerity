%% Description:
% This script simulates and compares two configuration, one using the winter
% and the other using the summer cycle. The two configurations differ as follow: 
% -Winter configuration: Uses a Highway cycle and the outer temperature is -5°C
% -Summer configuration: Uses a City cycle and the outer temperature is 40°C

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the models to be simulated
% Ensure that the model workspace is reset to the original values (turn off fast restart for the reset)
clear; modelName = checkModel('BEV_Thermal_Management');

% Create simulation Input for summer and winter
simInput(1:2) = Simulink.SimulationInput(modelName);
simInput(2)   = setSimInputObj(simInput(2),'FixAllParam',1,'Scenario','Winter');
simInput(1)   = setSimInputObj(simInput(1),'FixAllParam',1,'Scenario','Summer');
simInput      = simInput.setPostSimFcn(@(out) postSimFcnEV(out,simInput));

%% 2) Simulate Winter and Summer scenario
% Simulate summer & winter and store results
resultsSummer = sim(simInput(1));
resultsWinter = sim(simInput(2));
set_param(modelName,'FastRestart','off')

% Plot energy consumption for the main components
energySum = plotVehicleEnergy(resultsSummer.results,'Title','Summer','MultipleFigs',1);
energyWin = plotVehicleEnergy(resultsWinter.results,'Title','Winter','MultipleFigs',1);

% Show also the Tables with the HVAC Table
energiesHVAC(2,:) = [resultsWinter.results.hvac.energyCmpr,resultsWinter.results.hvac.energyBlwr + resultsWinter.results.hvac.energyFan, resultsWinter.results.hvac.energyPmps , resultsWinter.results.hvac.energyHeater + resultsWinter.results.hvac.energyPTC];
energiesHVAC(1,:) = [resultsSummer.results.hvac.energyCmpr,resultsSummer.results.hvac.energyBlwr + resultsSummer.results.hvac.energyFan, resultsSummer.results.hvac.energyPmps , resultsSummer.results.hvac.energyHeater + resultsSummer.results.hvac.energyPTC];
energiesHVACTable = array2table(energiesHVAC, 'VariableNames', {'Compressor', 'Blower + Fan', 'Pumps', 'Heater + PTC'});

%% 3) Plot vehicle speed over time for both cycles
speedSum     = resultsSummer.resultsLogs.get('speedRef').Values;
speedWin     = resultsWinter.resultsLogs.get('speedRef').Values;
simTimeS     = speedSum.Time;
simTimeW     = speedWin.Time;

figure('Units','centimeters','Position',[0,0,29.92/2.2,12.91],'Color','w'); hold on
plot(simTimeS, speedSum.Data,'LineWidth',2,'Color',[215,135,36]/255); grid on;
xlabel('Time in sec'); ylabel('Speed in km/h'); ax = gca; ax.FontSize =14; ax.YLim(2) =100;
plot(simTimeW, speedWin.Data,'LineWidth',2,'Color',[0,118,168]/255);  grid on;

%% 4) Plot Battery Temperature over time:
tempBattSum  = resultsSummer.resultsLogs.get('tempBattery').Values;
tempBattWin  = resultsWinter.resultsLogs.get('tempBattery').Values;
tempCabinSum = resultsSummer.resultsLogs.get('tempCabin').Values;
tempCabinWin = resultsWinter.resultsLogs.get('tempCabin').Values;

% Surface for the safe temperatures for battery: 
yLower = 5; yUpper = 35; x = [0, 765, 765, 0]; y = [yLower, yLower, yUpper, yUpper];

figure('Units','centimeters','Position',[0,0,29.92/2.2,12.91],'Color','w'); hold on; grid on;
fill(x, y,[152,198,234]/255,'FaceAlpha',0.5,'EdgeColor','none'); % Light blue surface
ax = gca; ax.FontSize =14; ax.XLim(2) = 765; ax.YLim = [-10,45];
xlabel('Time in sec'); ylabel('Battery Temperature in °C'); 
plot(simTimeS, tempBattSum.Data,'LineWidth',2,'Color',[215,135,36]/255); grid on;
plot(simTimeW, tempBattWin.Data,'LineWidth',2,'Color',[0,118,168]/255);  grid on;

%% 5) Create result table
% Create a table with the data for the required time
[~,idBW] = min(abs(tempBattWin.Data-5));
[~,idBS] = min(abs(tempBattSum.Data-35));
[~,idCW] = min(abs(tempCabinWin.Data-24));
[~,idCS] = min(abs(tempCabinSum.Data-26));

sprintf('Battery Summer %.1f\nBattery Winter %.1f\nCabin Summer %.1f\nCabin Winter %.1f',simTimeS(idBS),simTimeW(idBW),simTimeS(idCS),simTimeW(idCW));

%% 6) Save results
% Save results if needed
proj       = currentProject;
saveLabel  = strrep(strrep(char(datetime),'-','_'),':','_');
saveFolder = [char(proj.RootFolder) filesep 'Workflows' filesep 'Optimization' filesep 'results'];

% Save the results in the folder
try
    save([saveFolder filesep 'baselineConf'],'resultsSummer','resultsWinter');
catch
    disp('The "results" folder does not exist and is purposely put under gitignore (to avoid loading big data to Git). Create a result folder locally')
end
