function [xy_data,cFrame] = Extr_Data_Pawl(rad, range, offset, scaleY, scaleX, tip_rad, varargin)
% Extr_Data_Pawl Produce extrusion data for a ratchet wheel
% as a set of vertices. 
%   [xy_data, cFrame] = Extr_Data_Ratchet_Wheel(r_outer, r_inner, n_teeth, varargin)
%   This function returns x-y data for a pawl and the location of a frame 
%   for the contact disk geometry at the tip.
%
%   You can specify:
%       rad          - Radius of inner surface
%       range        - Arc range of inner surface (in degrees)
%       offset       - Width of pawl at base
%       scaleX       - Percentage outer arch will be scaled in x
%       scaleY       - Percentage outer arch will be scaled in y
%       tip_rad      - Radius of pawl tip
%
%   To see a plot showing parameter values, enter the name
%   of the function with no arguments or with just the gear type
%   >> Extr_Data_Pawl
%
%   To see a plot created with your parameter values,
%   add 'plot' as the final argument
%   >> Extr_Data_Pawl(0.05,60,0.01,1.04,1.1,0.002,'plot')

% Copyright 2013-2026 The MathWorks, Inc.

showplot = 'n';

% DEFAULT DATA TO SHOW DIAGRAM
if (nargin == 0)
    rad    = 0.05;
    range    = 60;
    offset = 0.01;
    scaleY = 1.04;
    scaleX = 1.1;
    tip_rad = 0.002;
end

if (nargin==0)
    showplot = 'plot';
elseif (nargin==7)
    showplot = varargin(end);
else
    showplot = 'n';
end

% Range of angles for intial arc
pawl_qvec     = flipud(linspace(0,range,range));

% Create outer arc
pawl_arcOuter = rad*[cosd(pawl_qvec)'  sind(pawl_qvec)'];

% Create inner arc (flip for counter-clockwise)
pawl_arcInner = flipud(pawl_arcOuter);

% Offset inner arc
pawl_arcInner = pawl_arcInner-[offset 0];

% Scale outer arc
pawl_arcOuter = (pawl_arcOuter-[rad 0]).*[scaleX 1]+[rad 0];
pawl_arcOuter = (pawl_arcOuter-[rad 0]).*[1 scaleY]+[rad 0];

% Create half circle for base
pawl_baseqvec = linspace(-180,0,20);
pawl_base     = offset/2*[cosd(pawl_baseqvec)'  sind(pawl_baseqvec)']+[rad-offset/2 -rad*0.01];

% Create partial circle for pawl tip
quarter_circle_rad  = tip_rad;              % Radius
quarter_circle_qvec = linspace(110,270,15); % Range of circle

% Create circle
quarter_circle_inn  = quarter_circle_rad*[cosd(quarter_circle_qvec)'  sind(quarter_circle_qvec)'];

% Offset so [0 0] is at bottom of circle
quarter_circle_inn  = quarter_circle_inn+[0 quarter_circle_rad];

% Get angle to pivot partial circle
q_tip_inn = 180+atan2d(pawl_arcInner(1,2)-pawl_arcInner(2,2),pawl_arcInner(1,1)-pawl_arcInner(2,1));
R = [cosd(q_tip_inn) -sind(q_tip_inn);
     sind(q_tip_inn)  cosd(q_tip_inn)];

% Rotate partial circle
quarter_circle_innR = (R*quarter_circle_inn')';

% Offset to start of pawl inner arc
quarter_circle_innR = quarter_circle_innR+pawl_arcInner(1,:);

% Obtain frame for contact disk
cFrame = pawl_arcInner(1,:)+(R*[0;quarter_circle_rad])'-[rad-offset/2 0];

% Assemble extrusion data
xy_data = [quarter_circle_innR(1:end-1,:);pawl_arcInner;pawl_base;pawl_arcOuter]-[rad-offset/2 0]; 

% Plot diagram to show parameters and extrusion
if (nargin == 0 || strcmpi(showplot,'plot'))
    
    % Figure name
    figString = ['h1_' mfilename];
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
    
    % Plot extrusion
    patch(xy_data(:,1),xy_data(:,2),[1 1 1]*0.90,'EdgeColor','none');
    hold on
    plot(xy_data(:,1),xy_data(:,2),'-','Marker','o','MarkerSize',4,'LineWidth',2);
    axis('equal');
    
    plot(cFrame(1),cFrame(2),'rd')

    % Show parameters
    %{
    teeth_pts = [xy_data(5:2:9,:)];
    plot(teeth_pts(:,1),teeth_pts(:,2),'r-d','MarkerFaceColor','r');
    text(teeth_pts(2,1)*0.9,teeth_pts(2,2)*0.9,'{\color{red}n\_teeth}','HorizontalAlignment','right');
    
    plot([0 xy_data(4,1)],[0 xy_data(4,2)],'k--d','MarkerFaceColor','k','LineWidth',1);
    text(xy_data(4,1)*0.35,xy_data(4,2)*0.35,'r\_outer','VerticalAlignment','bottom','HorizontalAlignment','right');

    plot([0 xy_data(end-1,1)],[0 xy_data(end-1,2)],'b--d','MarkerFaceColor','b','LineWidth',1);
    text(xy_data(end-1,1)*0.35,xy_data(end-1,2)*0.35,'{\color{blue}r\_inner}','VerticalAlignment','top','HorizontalAlignment','right');
    %}

    title('[xy\_data] = Extr\_Data\_Pawl(rad, range, offset, scaleY, scaleX,tip\_rad);');
    hold off
    box on
    clear xy_data
end
