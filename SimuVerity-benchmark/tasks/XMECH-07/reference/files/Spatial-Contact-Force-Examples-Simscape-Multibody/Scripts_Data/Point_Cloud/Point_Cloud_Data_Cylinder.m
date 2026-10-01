function ptcld = Point_Cloud_Data_Cylinder(radius,height,numpts,caps,varargin)
%Point_Cloud_Data_Cylinder Produce point cloud for exterior surface of a cylinder
%   [ptcld] = Point_Cloud_Data_Cylinder(radius,height,numpts,caps)
%
%   You can specify:
%       radius    Cylinder radius
%       height    Cylinder height
%       caps      Add points on ends (true/false)
%       numpts    Estimated number of points about circumference
%                 Points on cylinder ends will be in addition
%                 to this estimate, placed at the same points/area
%                 as on the cylinder circumference
%
%   Point cloud data will be centered at [0,0,0]
%
% Copyright 2022-2026 The MathWorks, Inc.

% Default data to show diagram
if (nargin == 0)
    radius = 5;
    height = 5;
    caps   = true;
    numpts = 100;
    showplot = 'plot';
end

% Check if plot should be produced
if (isempty(varargin))
    showplot = 'n';
else
    showplot = varargin;
end

% Calculate cylinder circumference
cyl_cir = 2*pi*radius;

% Starting point for search
n_h = 2;
n_c = 6;

% Increase number of points along height and about circumference
% until number of points meets or exceeds request
while (n_h*n_c<=numpts)
    n_h   = n_h+2;      % Always add 2 lines of points about circumference
    box_h = height/n_h; % Calculate separate of points about circumference
    n_c   =  floor(cyl_cir/(box_h*2));  % Calculate vertical point separation
end

% Calculate angle vectors for staggered rings about circumference
ang_ca = linspace(0,2*pi-(2*pi/n_c),n_c);
ang_cb = ang_ca+pi/n_c;

% Assemble point cloud, ring by ring
ptcld = [];
for i = 0:n_h
    if(rem(i,2)==0)
        pts_x = cos(ang_ca)*radius;
        pts_y = sin(ang_ca)*radius;
    else
        pts_x = cos(ang_cb)*radius;
        pts_y = sin(ang_cb)*radius;
    end
    pts_z = i/n_h*height*ones(size(pts_x))-height/2;
    ptcld = [ptcld;pts_x' pts_y' pts_z'];
end

if(caps)
    pts_per_area = size(ptcld,1)/(cyl_cir*height);
    area_end = pi*(radius-box_h/2)^2;
    pts_end  = ceil(area_end*pts_per_area);

    pts_end = Point_Cloud_Data_Circle(radius-box_h/2,pts_end);

    pts_end(:,3) = height/2;
    ptcld = [ptcld; pts_end];
    pts_end(:,3) = -height/2;
    ptcld = [ptcld; pts_end];
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

    plot3([0 0],[0 0],[-1 1]*height/2,'b-d','MarkerFaceColor','b','LineWidth',1)
    text(radius*0.05,radius*0.05,0,'height','Color','blue')

    plot3([0 radius],[0 0],[1 1]*height/2,'k-d','MarkerFaceColor','k','LineWidth',1)
    text(radius/2,0,height*0.45,'radius','Color','black')

    DT = delaunayTriangulation(ptcld);
    [K,~] = convexHull(DT);
    trisurf(K,DT.Points(:,1),DT.Points(:,2),DT.Points(:,3),'FaceColor',[0.6 0.6 0.9],'EdgeColor',[0.6 0.6 0.9],'FaceAlpha',0.3)

    title(['[ptcld] = Point\_Cloud\_Data\_Cylinder(radius, height, caps, numpts);']);
    hold off
    box on
    axis equal
    grid off
end