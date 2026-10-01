function ptcld = Point_Cloud_Data_Circle(radius,numpts,varargin)
%Point_Cloud_Data_Circle Produce point cloud for area within a circle
%   [ptcld] = Point_Cloud_Data_Circle(radius,numpts)
%   
%   You can specify:
%       radius    circle radius
%       numpts    number of points
%
%   Point cloud data will be centered at [0,0,0]
%
% Copyright 2021-2025 The MathWorks, Inc.

% Default data to show diagram
if (nargin == 0)
    radius = 5;
    numpts = 100;
    showplot = 'plot';
end

% Check if plot should be produced
if (isempty(varargin))
    showplot = 'n';
else
    showplot = varargin;
end

ptcld=[0 0 0];
golden_angle = pi * (3 - sqrt(5));

for i = 1:numpts
    theta = i*golden_angle;
    r = sqrt(i)/sqrt(numpts);
    ptcld(i,:) = [r*cos(theta) r*sin(theta) 0]*radius;
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
    
    temp_colororder = get(gca,'defaultAxesColorOrder');
    
    plot3(ptcld(:,1),ptcld(:,2),ptcld(:,3),'o','MarkerFaceColor',temp_colororder(2,:))
    hold on
    
    angles = 0:0.1:2*pi;
    plot3(sin(angles)*radius,cos(angles)*radius,zeros(size(angles)),'b')
    plot3([0 radius],[0 0],[0 0],'b-d','MarkerFaceColor','b','LineWidth',1)
    text(radius/2,0,0,'radius','Color','blue')

    title(['[ptcld] = Point\_Cloud\_Data\_Circle(radius, height, numpts);']);
    hold off
    box on
    axis equal
    grid off
end