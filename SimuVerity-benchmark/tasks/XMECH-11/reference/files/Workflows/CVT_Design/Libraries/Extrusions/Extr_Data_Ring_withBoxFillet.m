function [xy_data] = Extr_Data_Ring_withBoxFillet(ring_or, box_ox, box_oy, rad_o, varargin)
%Extr_Data_Ring_withBoxFillet Produce extrusion data for a circle with a hole shaped as a
%rectangle with rounded corners.
%   [xy_data] = Extr_Data_Ring_withBoxFillet(ring_or, box_ox, box_oy, rad_o)
%   This function returns x-y data for a circle with a rectangular hole.
%   You can specify:
%       Outer radius	ring_or
%       Outer width             box_ox
%       Outer height            box_oy
%
%   To see a plot showing parameter values, enter the name
%   of the function with no arguments
%   >> Extr_Data_Ring_withBoxFillet
%
%   To see a plot created with your parameter values,
%   add 'plot' as the final argument
%   >> Extr_Data_Ring_withBoxFillet(5,2.5,8,0.2,'plot')

% Copyright 2018-2025 The MathWorks, Inc.

% Default data to show diagram
deg1 = 90;
deg2 = 90+360;
ring_ir = 0;
if (nargin == 0)
    ring_or = 5;
    box_ox = 2.5;
    box_oy = 8;
    rad_o = 0.2;
end

% Check if plot should be produced
if (isempty(varargin))
    showplot = 'n';
else
    showplot = varargin;
end

% Calculate extrusion data
xy_data1 = Extr_Data_Ring(ring_or, ring_ir, deg1, deg2);
xy_data2 = Extr_Data_BoxFillet(box_ox, box_oy, rad_o);
xy_data = [xy_data1; flipud(xy_data2)];

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
    axis([-1.1 1.1 -1.1 1.1]*ring_or);
    
    % Show parameters
    hold on
    
    or_label_ang = deg1+deg2*0.5;
    plot([0 ring_or*(cos(or_label_ang*pi/180))],[0 ring_or*(sin(or_label_ang*pi/180))],'r-d','MarkerFaceColor','r');
    text(cos(or_label_ang*pi/180)*0.75*ring_or,sin(or_label_ang*pi/180)*0.75*ring_or,'{\color{red}ring\_or}');
    
	plot([0 0],[-box_oy/2 box_oy/2],'r-d','MarkerFaceColor','r');
    text(0,-box_oy/2*0.5,'{\color{red}box\_oy}','HorizontalAlignment','right');
    
    plot([-box_ox/2 box_ox/2],[0 0],'g-d','MarkerFaceColor','g');
    text(box_ox/2*0.25,box_oy*0.025,'{\color{green}box\_ox}');
    
    radius_label_angle = 45*(pi/180);
    plot([box_ox/2-rad_o box_ox/2-rad_o*(1-cos(radius_label_angle))],[box_oy/2-rad_o box_oy/2-rad_o*(1-sin(radius_label_angle))],'k-d','MarkerFaceColor','k');
    text(box_ox/2-rad_o/2*(cos(radius_label_angle))*0.0,box_oy/2-rad_o/2*(sin(radius_label_angle))*0.0,'{\color{black}rad\_o}','HorizontalAlignment','center');
    [box_ox/2-rad_o/2*(cos(radius_label_angle)),box_oy/2-rad_o/2*(sin(radius_label_angle))];

    title(['[xy\_data] = Extr\_Data\_Ring_withBoxFillet(ring\_or, box\_ox, box\_oy, rad\_o);']);
    hold off
    box on
    clear xy_data
end
