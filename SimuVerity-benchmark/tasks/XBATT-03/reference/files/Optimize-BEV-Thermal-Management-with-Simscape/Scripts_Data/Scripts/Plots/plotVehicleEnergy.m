function energies = plotVehicleEnergy(out,varargin)
% Description: After simulating the vehicle and passing the results trough the
%              function calcVehicleEnergy, the output of the function is reused here to
%              represent the vehicle consumption as a bar plot
%-----------------
% Inputs:      out: This struct is the output of the function calcVehicleEnergy
%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% Additional Inputs
% These inputs can be assigned by the variable varargin
p = inputParser;

% Add the optional inputs
addOptional(p,'MultipleFigs',0);
addOptional(p,'Title','Total energy consumption');
addOptional(p,'YLabel','Losses in kWh');
addOptional(p,'FigDim',[0,0,29.92/2,12.91]);
addOptional(p,'FontSize',11);

% Use the parse object and create the optional variables
parse(p, varargin{:});

% Create the optional input variables
Title       = p.Results.Title;
YLabel      = p.Results.YLabel;
FigDim      = p.Results.FigDim; 
FntSiz      = p.Results.FontSize;
MultipleFigs= p.Results.MultipleFigs;

%% 1) Identify required bars
% Colors to be used in the plots
Colors = [255,255,255; 0  , 75 , 135; 215, 136, 36; 0  , 118, 168; 148, 198, 215; 217, 217, 217]/255;

% If there is some energy stored in the vehicle, add it to the plot
labels  = {'E-Motor'; 'Gearbox'; 'HVAC'; 'Tires';'Drag'; 'Stored'};
reqEn   = round([out.energyLossEM(end); out.energyLossGrbx(end); out.energyHvac(end); out.energyLossTires(end); out.energyLossDrag(end); out.energyVehStrd(end)],2);

% Filter out the components that are smaller than 1 W. No need to represent them
reqEn(find(reqEn<0.001))  = [];
labels(find(reqEn<0.001)) = [];

% For a better visibility sort the data:
[reqEnSrtd,I] = sort(reqEn,'descend');
labelsSrtd    = labels(I);

%% 2) Create figure
% Figure name
figString = ['h1_' mfilename];

if MultipleFigs==0
    % Only create a figure if no figure exists
    figExist = 0;
    fig_hExist = evalin('base',['exist(''' figString ''')']);
    if (fig_hExist)
        figExist = evalin('base',['ishandle(' figString ') && strcmp(get(' figString ', ''type''), ''figure'')']);
    end
    if ~figExist
        fig_h = figure('Name',figString,'Units','centimeters','Position',FigDim,'Color','w');
        assignin('base',figString,fig_h);
    else
        fig_h = evalin('base',figString);
    end
    figure(fig_h)
    clf(fig_h)
else 
    figure('Name',figString,'Units','centimeters','Position',FigDim,'Color','w');
end

% Create bar plot
h1 = bar(gca,reqEnSrtd,'FaceColor','flat');

% Set axes dimensions and layout
set(gca,'XLim',[0.5,numel(reqEnSrtd)+0.5],'YLim',[0,max(reqEnSrtd)*1.1]);
set(gca, 'XTick',1:numel(reqEn),'XTickLabel', labelsSrtd,'FontSize',11);
ylabel(YLabel);

% Set color and dimensions of the bar plot
set(h1,'CData',Colors(1:numel(reqEn),:),'BarWidth',1);

% Write consumption values above the bar plot
text(h1.XEndPoints,h1.YEndPoints,num2str(reqEnSrtd),'HorizontalAlignment','center','VerticalAlignment','bottom','FontSize',10);
title(Title);
ax = gca; ax.FontSize = FntSiz;

%% 4) Assign outputs
energies = table(reqEnSrtd(1),reqEnSrtd(2),reqEnSrtd(3),reqEnSrtd(4),reqEnSrtd(5),'VariableNames',labelsSrtd');
end


