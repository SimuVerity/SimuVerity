function [xy_data] = Extr_Data_Ratchet_Wheel(r_outer, r_inner, n_teeth, varargin)
% Extr_Data_Ratchet_Wheel Produce extrusion data for a ratchet wheel
% as a set of vertices. 
%   [xy_data] = Extr_Data_Ratchet_Wheel(r_outer, r_inner, n_teeth, varargin)
%   This function returns x-y data for a ratchet wheel.
%   You can specify:
%       r_outer         - Outer radius of teeth
%       r_inner         - Inner radius of teeth
%       n_teeth         - Number of teeth
%
%   To see a plot showing parameter values, enter the name
%   of the function with no arguments or with just the gear type
%   >> Extr_Data_Ratchet_Wheel
%
%   To see a plot created with your parameter values,
%   add 'plot' as the final argument
%   >> Extr_Data_Ratchet_Wheel(0.1,0.09,30,'plot')

% Copyright 2013-2026 The MathWorks, Inc.

showplot = 'n';

% DEFAULT DATA TO SHOW DIAGRAM
if (nargin == 0)
    r_outer = 0.10;
    r_inner = 0.09;
    n_teeth = 30;
end

if (nargin==0)
    showplot = 'plot';
elseif (nargin==4)
    showplot = varargin(end);
else
    showplot = 'n';
end

teeth_qvec  = flipud(linspace(0,360-360/(n_teeth),n_teeth)); 
teeth_outer = r_outer*[cosd(teeth_qvec)'  sind(teeth_qvec)'];
teeth_inner = r_inner*[cosd(teeth_qvec)'  sind(teeth_qvec)'];

xy_data = [];
for i = 1:length(teeth_qvec)
    xy_data(2*i-1,:) = teeth_inner(i,:);
    xy_data(2*i,:)   = teeth_outer(i,:);
end

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
    
    % Show parameters
    teeth_pts = [xy_data(5:2:9,:)];
    plot(teeth_pts(:,1),teeth_pts(:,2),'r-d','MarkerFaceColor','r');
    text(teeth_pts(2,1)*0.9,teeth_pts(2,2)*0.9,'{\color{red}n\_teeth}','HorizontalAlignment','right');
    
    plot([0 xy_data(4,1)],[0 xy_data(4,2)],'k--d','MarkerFaceColor','k','LineWidth',1);
    text(xy_data(4,1)*0.35,xy_data(4,2)*0.35,'r\_outer','VerticalAlignment','bottom','HorizontalAlignment','right');

    plot([0 xy_data(end-1,1)],[0 xy_data(end-1,2)],'b--d','MarkerFaceColor','b','LineWidth',1);
    text(xy_data(end-1,1)*0.35,xy_data(end-1,2)*0.35,'{\color{blue}r\_inner}','VerticalAlignment','top','HorizontalAlignment','right');
    title('[xy\_data] = Extr\_Data\_Ratchet\_Wheel(r\_outer, r\_inner, n\_teeth);');
    hold off
    box on
    clear xy_data
end
