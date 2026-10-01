function ptcld = Point_Cloud_Data_Sphere(radius,numpts,varargin)
%Point_Cloud_Data_Sphere Produce point cloud for exterior surface of a sphere
%   [ptcld] = Point_Cloud_Data_Sphere(radius,numpts)
%   
%   You can specify:
%       radius    sphere radius
%       numpts    number of points
%
%   Point cloud data will be centered at [0,0,0]
%
% Copyright 2021-2026 The MathWorks, Inc.

% Default data to show diagram
if (nargin == 0)
    radius = 0.5;
    numpts = 100;
    showplot = 'plot';
end

% Check if plot should be produced
if (isempty(varargin))
    showplot = 'n';
else
    showplot = varargin;
end

[ptcld,~,~,~]=ParticleSampleSphere('N',numpts,'upd',false);

ptcld = ptcld*radius;

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
    
    plot3([0 0],[0 0],[0 radius],'b-d','MarkerFaceColor','b','LineWidth',1)
    text(radius*0.05,radius*0.05,radius*0.5,'radius','Color','blue')
    DT = delaunayTriangulation(ptcld);
    [K,~] = convexHull(DT);
    trisurf(K,DT.Points(:,1),DT.Points(:,2),DT.Points(:,3),'FaceColor',[0.6 0.6 0.9],'EdgeColor',[0.6 0.6 0.9],'FaceAlpha',0.3)
    
    title(['[ptcld] = Point\_Cloud\_Data\_Sphere(radius, numpts);']);
    hold off
    box on
    axis equal
    grid off
end