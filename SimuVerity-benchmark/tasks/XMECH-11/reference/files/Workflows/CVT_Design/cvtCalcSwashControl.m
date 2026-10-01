function [swashCtrlIdeal, swashCtrlTable,ax_sw] = cvtCalcSwashControl(...
    tgtVSpdRanges,rWhl,nGearCVTOut,nDiff,nFinalDrive,wEng,wPumpNom,...
    nHSPumpMotor,tgtMaxSwash,nTRing,nTSuns,nGearHSOut,pumpVolEff,showplot,varargin)
% Calculates the table for controlling the hydrostatic pump
% displacement based on target vehicle speed.
%
%   tgtVSpdRanges   Target vehicle speed ranges for transmission (km/h)
%   rWhl            Radius of wheel (m)
%   nGearCVTOut     Gear ratio after CVT output
%   nDiff           Ratio of differential
%   nFinalDrive     Ratio of wheel hub planetary gear
%   wEng            Engine target speed
%   wPumpNom        Pump nominal speed
%   nHSPumpMotor    Ratio (Hydrostatic Pump Displacement/
%                         Hydrostatic Motor Displacement)
%   tgtMaxSwash     Target max displacement ratio of pump swash plate (0-1)
%   nTRing          Number of teeth on planetary ring gears (all)
%   nTSuns          Vector 1x4 number of teeth on sun gear for each planetary
%   nGearHSOut      Gear ratio at output of hydrostatic transmission
%   pumpVolEff      Hydrostatic pump volumetric efficiency
%   showplot        Set to 'plot' to plot swash control table

% Copyright 2023-2025 The MathWorks, Inc.

%% Calculate ratio (CVT output shaft/Vehicle Speed) (rpm/kmph)
vWhl2CVTOut = 1/(3.6*rWhl*pi/30)*nGearCVTOut*nDiff*nFinalDrive;

%% Obtain design
% Get ratio wSun-to-wCVT Out when engine is not spinning
% Use this to calculate slope for intersection points
nSun1CVTOut_e0s1  = cvtGetCVTOutputSpeeds(0,1,nTRing,nTSuns);
slopeCVTCtrl = nSun1CVTOut_e0s1*...
    (nHSPumpMotor)*1/(nGearHSOut)*wPumpNom/wEng;

% Get ratio wEng-to-wCVT_Out when swash is 0
% Use to obtain midpoint of each speed segment
nEng2CVTOut_Sw0 = cvtGetCVTOutputSpeeds(1,0,nTRing,nTSuns);

% Convert desired vehicle speed ranges to ratio wEng-to-CVT Output speed
tgtCVTRatios = tgtVSpdRanges*vWhl2CVTOut/wEng;

% Assemble speed segment lines
for i = 1:length(nEng2CVTOut_Sw0)
    ratioSeg(i,2) = nEng2CVTOut_Sw0(i);            % Midpoint
    ratioSeg(i,1) = nEng2CVTOut_Sw0(i)-slopeCVTCtrl(i); % Lower ratio
    ratioSeg(i,3) = nEng2CVTOut_Sw0(i)+slopeCVTCtrl(i); % Higher ratio
end

% Find points of intersection
swas0 = -nEng2CVTOut_Sw0(1)/slopeCVTCtrl(1);
cvtr0 =  nEng2CVTOut_Sw0(1)+slopeCVTCtrl(1)*swas0;

for i = 1:(length(nEng2CVTOut_Sw0)-1)
    swas(i) = (nEng2CVTOut_Sw0(i+1)-nEng2CVTOut_Sw0(i))/...
        (slopeCVTCtrl(i)-slopeCVTCtrl(i+1));
    cvtr(i) = nEng2CVTOut_Sw0(i)+slopeCVTCtrl(i)*swas(i);
end

swas5 = (tgtCVTRatios(end)-nEng2CVTOut_Sw0(end))/slopeCVTCtrl(end);
cvtr5 = nEng2CVTOut_Sw0(end)+swas5*slopeCVTCtrl(end);

% Assemble ideal values into table
swasPts = [swas0 swas swas5];
cvtrPts = [cvtr0 cvtr cvtr5];
swashCtrlIdeal  = [swasPts' cvtrPts'];

%% Calculate Table
% To smooth transitions and account for volumetric efficiency,
% and add offsets at transitions.
yOff = 5e-5;
swashCtrlTable = [swashCtrlIdeal(1,:);...
    0 nEng2CVTOut_Sw0(1);...
    swashCtrlIdeal(2,1)/pumpVolEff swashCtrlIdeal(2,2)-yOff;...
    swashCtrlIdeal(2,1)*pumpVolEff swashCtrlIdeal(2,2)+yOff;...
    0 nEng2CVTOut_Sw0(2);...
    swashCtrlIdeal(3,1)/pumpVolEff swashCtrlIdeal(3,2)-yOff;...
    swashCtrlIdeal(3,1)*pumpVolEff swashCtrlIdeal(3,2)+yOff;...
    0 nEng2CVTOut_Sw0(3);...
    swashCtrlIdeal(4,1)/pumpVolEff swashCtrlIdeal(4,2)-yOff;...
    swashCtrlIdeal(4,1)*pumpVolEff swashCtrlIdeal(4,2)+yOff;...
    0 nEng2CVTOut_Sw0(4);...
    swashCtrlIdeal(5,:)];

if(strcmpi(showplot,'plot'))
    if(nargin==14)
        % Reuse figure if it exists, else create new figure
        figString = 'h1_CVT_Ratios';
        % Only create a figure if no figure exists
        figExist = 0;
        fig_hExist = evalin('base',['exist(''' figString ''')']);
        if (fig_hExist)
            figExist = evalin('base',['ishandle(' figString ') && strcmp(get(' figString ', ''type''), ''figure'')']);
        end
        if ~figExist
            fig_h = figure('Name',figString);
            assignin('base',figString,fig_h);
        else
            fig_h = evalin('base',figString);
        end
        figure(fig_h)
        clf(fig_h)
        ax_sw = gca;
    elseif(nargin==15)
        ax_sw = varargin{1};     % Use axis handle if provided
        cla(ax_sw)
    end

    ax_sw.XAxisLocation = 'origin';
    ax_sw.YAxisLocation = 'origin';

    %% Plot desired corners of swash plate control
    l_h(1) = plot(ax_sw,[-1 1 -1 1 -1]*tgtMaxSwash,tgtCVTRatios*wEng/vWhl2CVTOut,'r',...
        'Marker','square','MarkerSize',12, 'MarkerFaceColor',[1 0.8 0.8],...
        'DisplayName','Target','Tag','Target');
    hold(ax_sw,'on');
    hold(ax_sw,'off');
    hold(ax_sw,'on');
    l_h(2) = plot(ax_sw,swasPts,cvtrPts*wEng/vWhl2CVTOut,'b-o','LineWidth',2,...
        'DisplayName','Control Map','Tag','Control');
    for i = 1:size(ratioSeg,1)
        l_h(3) = plot(ax_sw,[-1 0 1],ratioSeg(i,:)*wEng/vWhl2CVTOut,'--o','Color',[0.6 0.6 0.6],...
            'DisplayName','Possible','Tag','Possible');
    end
    hold(ax_sw,'off');

    ax_sw.YAxisLocation = 'origin';

    axXLims = get(ax_sw,'XLim');
    set(ax_sw,'XLim',[-1 1]*max([abs(axXLims) 1.1]));

    maxy = max([cvtrPts max(ratioSeg,[],'all') tgtCVTRatios]);
    set(ax_sw,'YLim',[0 maxy]*wEng/vWhl2CVTOut*1.1);

    patch(ax_sw,[-1 -[1 1]*max([abs(axXLims) 1.1]) -1],[0 0 1 1]*38,[1 1 1]*0.6,'FaceAlpha',0.3,'EdgeColor','none');
    patch(ax_sw,[ 1  [1 1]*max([abs(axXLims) 1.1])  1],[0 0 1 1]*38,[1 1 1]*0.6,'FaceAlpha',0.3,'EdgeColor','none');

    ylabel(ax_sw,'Vehicle Speed (km/h)')
    xlabel(ax_sw,'Displacement Ratio Hydrostatic Pump (0-1)')

    title(ax_sw,'Swash Plate Ratio by Speed Range')
    legend(ax_sw,l_h,'Location','West')
    box(ax_sw,'on')
    if(nargin<15)
        sm_cvt_power_split_pg_4range_animate_format(ax_sw);
    end
end