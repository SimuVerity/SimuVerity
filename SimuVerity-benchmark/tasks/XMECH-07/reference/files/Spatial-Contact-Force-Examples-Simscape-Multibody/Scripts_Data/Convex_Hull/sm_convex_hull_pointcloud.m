function sm_convex_hull_pointcloud(pointcloud,varargin)
%sm_convex_hull_pointcloud  Plot and produce STL to visualize convex hull of a point cloud
%   sm_convex_hull_pointcloud(pointcloud,<cvhfilename>,<showplot>)
%
%   You can specify:
%       pointcloud   Matrix of x, y, z data for points [n x 3]
%       cvhfilename  Filename for generated STL file to visualize convex hull
%                    Specify 'none' to generate no file
%       showplot     Specify 'plot' to plot the point cloud and convex hull
%
%   Examples:
%   >> sm_convex_hull_pointcloud
%   With no arguments, it will plot an example
%
%   >> sm_convex_hull_pointcloud(rand(25,3),'none','plot')
%   This will plot 25 randomly distributed points enclosed in a convex hull
%
%   >> sm_convex_hull_pointcloud(rand(25,3),'myPointcloudSTL.stl','plot')
%   This will plot 25 randomly distributed points enclosed in a convex hull
%   and produce an STL file of the convex hull.
%
% Copyright 2021-2026 The MathWorks, Inc.

%% Assign default values
showplot    = 'plot';
cvhfilename = 'none';
if (nargin==0)
    stlfile    = 'test_stl_steering_wheel.stl';
    stl_tri    = stlread(stlfile);
    pointcloud = stl_tri.Points;
end
if (nargin>=2)
    cvhfilename = varargin{1};
end
if (nargin==3)
    showplot = varargin{2};
end

% Generate Delaunay triangulation
pointcloud_dt = delaunayTriangulation(pointcloud);

% Obtain indexes for convex hull
cvh_inds      = convexHull(pointcloud_dt);

% Generate triangulation using indices of convex hull
warning('off','MATLAB:triangulation:PtsNotInTriWarnId')
pointcloud_dt_cvh  = triangulation(cvh_inds,pointcloud_dt.Points);
warning('on','MATLAB:triangulation:PtsNotInTriWarnId')

% Plot point cloud and convex hull if requested
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
    plot3(pointcloud(:,1),pointcloud(:,2),pointcloud(:,3),'o','MarkerSize',2,'MarkerFaceColor',temp_colororder(2,:),'DisplayName','Point Cloud')
    hold on
    trisurf(pointcloud_dt_cvh,'FaceColor',[0.9 0.4 0.4],'EdgeColor',[0.9 0.4 0.4],'FaceAlpha',0.3,'DisplayName','Convex Hull');
    hold off
    axis equal
    box on
    title('Point Cloud and Convex Hull')
    legend('Location','Best')
end

% Generate STL file for convex hull if requested
if(~strcmp(cvhfilename,'none'))
    stlwrite(pointcloud_dt_cvh,cvhfilename);
end


