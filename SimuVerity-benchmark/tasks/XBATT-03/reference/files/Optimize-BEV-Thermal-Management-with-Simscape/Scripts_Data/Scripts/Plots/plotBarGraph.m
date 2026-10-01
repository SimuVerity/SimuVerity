function [barHandle,figHandle] = plotBarGraph(XData,YData,varargin)
%% Description: 
% This function is used to represent a vector as a 2D bar graph. The
% function is extended with a set of optional inputs to control the
% appearance of the plot. The function was built to analyze results of a
% series of Simulink simulations and plot the logged Simulink signals.
% For usage, see functions such as sensitivityHeater and the other sensitivity functions

%% Inputs:
% XData:   [1xn double]: The vector used as label for the each bar (X Axis)
% YData:   [1xn double]: The size of the bars in the bar plot

% Optional Inputs: 
% Xticks:  [string]        'Yes' or 'No'
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
addOptional(p,'XTicks','Yes');
addOptional(p,'Title','');
addOptional(p,'XLabel','');
addOptional(p,'YLabel','');
addOptional(p,'BarColor',[0,118,168]/255);
addOptional(p,'FigDim',[0,0,29.92/2,12.91]);
addOptional(p,'FontSize',14);

% Use the parse object and create the optional variables
parse(p, varargin{:});

% Create the optional input variables
Xticks = p.Results.XTicks;
Title  = p.Results.Title;
XLabel = p.Results.XLabel;
YLabel = p.Results.YLabel;
FigDim = p.Results.FigDim; 
BarCol = p.Results.BarColor;
FntSiz = p.Results.FontSize;

%% 2) Create figure
% Create the figure
figHandle = figure('Units','centimeters','Position',FigDim,'Color','white');

% Plot the bar color
barHandle = bar(XData,YData,'BarWidth',1,'FaceColor',BarCol);

% Add title, labels and ticks
if ~isempty(XLabel); xlabel(XLabel); end
if ~isempty(YLabel); ylabel(YLabel); end
title(Title);

% If the user selected the Xticks then apply them
if strcmp(Xticks,'Yes'); xticks(XData); end

% Adapt the axes size for good scaling:
ax=gca; 
XData = sort(XData);
ax.XLim = [XData(1)-(XData(2)-XData(1))/2,XData(end)+(XData(2)-XData(1))/2];
adjustMargins(2, 1.5, 0.5, 0.7); % Left, Bottom, Right, Top Margins in cm
ax.FontSize = FntSiz;

end