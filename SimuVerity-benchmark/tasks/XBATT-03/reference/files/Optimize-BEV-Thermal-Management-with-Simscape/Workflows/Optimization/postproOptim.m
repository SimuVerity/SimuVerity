function postproOptim(trials,x,varargin)
%% Description: 
% This function plots the results obtained with the script
% surrOptBEVParallel. You can use the function to analyze the
% results of the optimization and compare the optimized solution with the baseline solution

%% Input
% trials        : [1x1 struct]: Struct containing the trials of surrogateopt
% x             : [1x7 double]: Contains the variables of the optimized configuration
% varargin      : varargin    : Implements additional inputs. See section 1) for more info

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% 1) Optional Inputs
% Parse input arguments
p = inputParser;

% These variables decide which variables will NOT be updated
addOptional(p,'PlotBaseLine',1);

% Use the parse object and create the optional variables
parse(p, varargin{:});

% Create the optional input variables
PlotBaseLine = p.Results.PlotBaseLine;

% The user requested to plot the Baseline as a reference
if PlotBaseLine==1
    try
        load('baselineConf'); % This variable can be generated with the script simBaselineConfiguration.m
    catch
        disp('Base Line Configuration not available! Generate it with simBaselineConfiguration.m')
        PlotBaseLine = 0;
    end
end

%% 2) Load the baseline simulation data (if requested)
% If requested, set up the baseline data as it will be compared with the% optimization
if PlotBaseLine==1
    % Energy consumption in winter and summer
    energySumBase = resultsSummer.results.energyBattery;
    energyWinBase = resultsWinter.results.energyBattery;
    
    % Get the battery time in sec for the baseline configuration
    battTimeWinBase = checkTempReq([resultsWinter.resultsLogs.get('tempBattery').Values.Time,resultsWinter.resultsLogs.get('tempBattery').Values.Data],[5,35]);
    
    % The baseline configuration has 4000 W heater power
    heaterPwrBase    = 4000;
end

%% 3) Load the optimization data
% Get the energy consumption in kWh for both winter and summer scenarios
energySumOpt    = -trials.Ineq(:,end);
energyWinOpt    = -trials.Ineq(:,end-1);

% Get the battery and cabin time in sec for both winter and summer scenarios
battTimeWinOpt  = trials.Ineq(:,4) + 600;

% Find the ID of the optimal solution:
optSolId     = find(ismember(trials.X, x, 'rows'));

% Convert heater and PTC power to their actual values in W
heaterPwrOpt = trials.X(:,end-1);
heaterPwrOpt = interp1(1:1:7,4000:250:5500,heaterPwrOpt,'nearest')/1000;

% Identify which elements are feasible (i.e. fulfill all the constraints):
fullFilssConstr = all(trials.Ineq(:,1:4)<0,2);

%% 4) Create contour plot with the consumption
% Create the figure
figure('Units','centimeters','Position',[0,0,25.96,12.91],'Color','white'); hold on; grid on; 

% Set labels and axes size
xlabel('Consumption Summer in kWh'); ylabel('Consumption Winter in kWh'); ax=gca; ax.FontSize = 14;

% Plot the consumption in summer vs. the consumption in winter
scatter(energySumOpt,energyWinOpt); limX = ax.XLim; limY = ax.YLim;

% Create the matrix for the colormap
Scons   = linspace(limX(1),limX(2),100)/1.35;
Wcons   = linspace(limY(1),limY(2),100)/2.83;
TotCons = Scons+Wcons';

% create the colormap
imagesc('XData', linspace(limX(1), limX(2), size(TotCons, 2)), ...
        'YData', linspace(limY(1), limY(2), size(TotCons, 1)),'CData', TotCons);

% Resize the colormap to fill the figure
contour(linspace(limX(1), limX(2), size(TotCons, 2)), ...
        linspace(limY(1), limY(2), size(TotCons, 1)), TotCons, 'LineColor', 'k','ShowText','on'); % 'k' for black lines

% Change color of the colormap and adjust margins
colormap jet; c = colorbar; c.Label.String = 'f(x): Combined Consumption in kWh'; ax.Layer = 'top';
adjustMargins(1.9, 1.7, 3, 0.6); % Left, Bottom, Right, Top Margins in cm

% The colormap is now hiding the points, Plot the unfeasible solution
scatter(energySumOpt(~fullFilssConstr),energyWinOpt(~fullFilssConstr),'filled','MarkerFaceColor',[242,242,242]/255,'MarkerEdgeColor',[1,0,0],'LineWidth',1,'SizeData',90);
scatter(energySumOpt(~fullFilssConstr),energyWinOpt(~fullFilssConstr),'x','MarkerEdgeColor',[1,0,0],'LineWidth',1,'SizeData',90);

% Now plot the feasible solutions
scatter(energySumOpt(fullFilssConstr),energyWinOpt(fullFilssConstr),'filled','MarkerFaceColor',[242,242,242]/255,'MarkerEdgeColor',[72,162,63]/255,'LineWidth',1.2,'SizeData',90);

% Plot the optimized solution (in green)
scatterOpt(energySumOpt(optSolId),energyWinOpt(optSolId));

% If desired plot the other solution
if PlotBaseLine==1; scatterBase(energySumBase,energyWinBase); end

%% 5) Create the battery images
% Plot the battery time
figure('Units','centimeters','Position',[0,0,25.96/2,12.91],'Color','white'); hold on; grid on; 
xlabel('t_{Batt} Winter in sec'); ylabel('Consumption in Winter in kWh');  ax=gca; ax.FontSize = 14;
scatter(battTimeWinOpt(~fullFilssConstr),energyWinOpt(~fullFilssConstr),'filled','MarkerFaceColor',[242,242,242]/255,'MarkerEdgeColor',[1,0,0],'LineWidth',1,'SizeData',70);
scatter(battTimeWinOpt(~fullFilssConstr),energyWinOpt(~fullFilssConstr),'x','MarkerEdgeColor',[1,0,0],'LineWidth',1,'SizeData',70);
scatter(battTimeWinOpt(fullFilssConstr),energyWinOpt(fullFilssConstr),'filled','MarkerFaceColor',[242,242,242]/255,'MarkerEdgeColor',[72,162,63]/255,'LineWidth',1.2,'SizeData',70);

scatterOpt(battTimeWinOpt(optSolId),energyWinOpt(optSolId));
if PlotBaseLine==1; scatterBase(battTimeWinBase,energyWinBase); end


% Plot the heater vs. battery time
figure('Units','centimeters','Position',[0,0,25.96/2,12.91],'Color','white'); hold on; grid on; xlabel('t_{Batt} Winter in sec'); ylabel('Heater Power in kW');  ax=gca; ax.FontSize = 14;
scatter(battTimeWinOpt(~fullFilssConstr),heaterPwrOpt(~fullFilssConstr),'filled','MarkerFaceColor',[242,242,242]/255,'MarkerEdgeColor',[1,0,0],'LineWidth',1,'SizeData',70);
scatter(battTimeWinOpt(~fullFilssConstr),heaterPwrOpt(~fullFilssConstr),'x','MarkerEdgeColor',[1,0,0],'LineWidth',1,'SizeData',70);
scatter(battTimeWinOpt(fullFilssConstr),heaterPwrOpt(fullFilssConstr),'filled','MarkerFaceColor',[242,242,242]/255,'MarkerEdgeColor',[72,162,63]/255,'LineWidth',1.2,'SizeData',70);

scatterOpt(battTimeWinOpt,heaterPwrOpt);
if PlotBaseLine==1; scatterBase(battTimeWinBase,heaterPwrBase/1000); end

end

%% Subfunctions:
function scatterOpt(X,Y)
    % Function to plot the final point identified by the optimizer
    scatter(X(end),Y(end),'filled',...
           'MarkerFaceColor',[72,162,63]/255, ...
           'MarkerEdgeColor',[0,0,0], ...
           'SizeData',160);
end

function scatterBase(X,Y)
    % Function to plot the base point meaning the starting configuration before
    % the optimization
    scatter(X,Y,'filled',...
           'MarkerFaceColor',[1,0,0], ...
           'MarkerEdgeColor',[0,0,0], ...
           'SizeData',160);
end