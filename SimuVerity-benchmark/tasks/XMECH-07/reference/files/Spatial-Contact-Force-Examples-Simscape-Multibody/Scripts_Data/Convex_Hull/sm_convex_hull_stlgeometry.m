function sm_convex_hull_stlgeometry(stlfile,varargin)
%sm_convex_hull_stlgeometry  Plot and produce STL to visualize convex hull of a point cloud
%   sm_convex_hull_stlgeometry(stlfile,<cvhfilename>,<showplot>)
%
%   You can specify:
%       stlfile      Matrix of x, y, z data for points [n x 3]
%       cvhfilename  Filename for generated STL file to visualize convex hull
%                    Specify 'none' to generate no file
%       showplot     Specify 'plot' to plot the point cloud and convex hull
%
%   Examples:
%   >> sm_convex_hull_stlgeometry
%   With no arguments, it will plot an example
%
%   >> sm_convex_hull_stlgeometry('test_stl_steering_wheel.stl','none','plot')
%   This will plot the STL geometry as a surface enclosed in a convex hull
%
%   >> sm_convex_hull_stlgeometry('test_stl_steering_wheel.stl','myGeometrySTL.stl','plot')
%   This will plot the STL geometry as a surface enclosed in a convex hull
%   and produce an STL file of the convex hull.
%
% Copyright 2021-2026 The MathWorks, Inc.

%% Assign default values
showplot    = 'plot';
cvhfilename = 'none';
if (nargin==0)
    stlfile     = 'test_stl_steering_wheel.stl';
end
if (nargin>=2)
    cvhfilename = varargin{1};
end
if (nargin==3)
    showplot = varargin{2};
end

% Read in STL file
stl_tri = stlread(stlfile);

% Generate Delaunay triangulation
stl_dt   = delaunayTriangulation(stl_tri.Points);

% Obtain indexes for convex hull
cvh_inds  = convexHull(stl_dt);

% Generate triangulation using indices of convex hull
warning('off','MATLAB:triangulation:PtsNotInTriWarnId')
stl_cvh  = triangulation(cvh_inds,stl_dt.Points);
warning('on','MATLAB:triangulation:PtsNotInTriWarnId')

% Plot STL as a surface and convex hull if requested
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
    trisurf(stl_tri,'EdgeColor','none','FaceAlpha',1,'DisplayName',strrep(stlfile,'_','\_'))
    colormap bone
    hold on
    trisurf(stl_cvh,'FaceColor',[0.9 0.4 0.4],'EdgeColor',[0.9 0.4 0.4],'FaceAlpha',0.3,'DisplayName','Convex Hull');
    hold off
    axis equal
    box on
    title('STL Geometry and Convex Hull')
    legend('Location','Best')
end

% Generate STL file for convex hull if requested
if(~strcmp(cvhfilename,'none'))
    stlwrite(stl_cvh,cvhfilename);
end

