function [figHandle] = plotTimeData(logData,logDataLabel,varargin)
%% Description: 
% This function is used to plot different time series all at once on the
% same plot. The function has a series of optional input to control the
% appearance of the plot. The function was built to analyze results of a
% series of Simulink simulations and plot the logged Simulink signals.
% For usage, see functions such as sensitivityHeater and the other sensitivity functions

%% Inputs:
% logData:      struct containing the logged data of several simulation
% logDataLabel: Label of the desired variable to be plotted

% Optional Inputs: 
% FigDim:  [1x4 double]    Dimension of the figure in cm, e.g. [0,0,29.92/2,12.91]
% Title :  [string]        Title string for the plot
% XLabel:  [string]        String for the X-Axis
% YLabel:  [string]        String for the Y-Axis
% FontSize:[1x1 double]    Size of the font 
% Legend:  [1xn cellarray] Array that contains the labels of the legend

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set optional inputs
% Parse input arguments
p = inputParser;

% Add the optional inputs
addOptional(p,'Title','');
addOptional(p,'XLabel','Time in sec');
addOptional(p,'YLabel','');
addOptional(p,'FigDim',[0,0,29.92/2,12.91]);
addOptional(p,'FontSize',14);
addOptional(p,'Legend','');

% Use the parse object and create the optional variables
parse(p,varargin{:});

% Create the optional input variables
Title  = p.Results.Title;
XLabel = p.Results.XLabel;
YLabel = p.Results.YLabel;
FigDim = p.Results.FigDim; 
FntSiz = p.Results.FontSize;
Legend = p.Results.Legend;

%% 2) Create figure 
% Create the figure
figHandle = figure('Units','centimeters','Position',FigDim,'Color','white'); grid on; hold on

% Color Map for the model
colorPlot = turbo(numel(logData));

%% 3) Plot the variables
% Plot the variables
for i=1:numel(logData)

    % Get the temperature of the battery over time
    varName = logData(i).get(logDataLabel).Values.Data;
    simTime = logData(i).get(logDataLabel).Values.Time;
    
    % Plot
    plot(simTime,squeeze(varName),'Color',colorPlot(i,:),'LineWidth',2);
end

%% 4) Add legend, title and labels
% Add the legend
if ~isempty(Legend); legend(Legend,'Location','best'); end

% Add title, labels
xlabel(XLabel); 
ylabel(YLabel);
title(Title);

% Adapt the axes size for good scaling:
ax=gca;
adjustMargins(2, 1.5, 0.5, 0.7); % Left, Bottom, Right, Top Margins in cm
ax.FontSize = FntSiz;
end