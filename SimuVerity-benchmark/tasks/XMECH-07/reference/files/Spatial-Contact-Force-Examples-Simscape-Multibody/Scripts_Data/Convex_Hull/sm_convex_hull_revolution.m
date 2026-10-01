function sm_convex_hull_revolution(extr_data,varargin)
%sm_convex_hull_revolution  Plot and produce STL to visualize convex hull of a point cloud
%   sm_convex_hull_pointcloud(pointcloud,<cvhfilename>,<showplot>)
%
%   You can specify:
%       extr_data    Matrix of x, y data for profile to be revolved [n x 2]
%       cvhfilename  Filename for generated STL file to visualize convex hull
%                    Specify 'none' to generate no file
%       showplot     Specify 'plot' to plot the point cloud and convex hull
%
%   Examples:
%   >> sm_convex_hull_revolution
%   With no arguments, it will plot an example
%
%   >> sm_convex_hull_revolution(sortrows(rand(25,2).*[0.3 1],2),'none','plot')
%   This will plot a revolution of 25 points enclosed in a convex hull
%
%   >> sm_convex_hull_revolution(sortrows(rand(25,2).*[0.3 1],2),'myRevSTL.stl','plot')
%   This will plot a revolution of 25 points enclosed in a convex hull
%   and produce an STL file of the convex hull.
%
% Copyright 2021-2026 The MathWorks, Inc.

%% Assign default values
showplot = 'plot';
cvhfilename = 'none';
if (nargin==0)
    extr_data = [
        [1 1 2 2 1 1 1 2 2 1 1]*0.4;...
        linspace(-2,2,11)]';
end
if (nargin>=2)
    cvhfilename = varargin{1};
end
if (nargin==3)
    showplot = varargin(end);
end

% Generate vector of angles
angle_vector = linspace(0,2*pi*0.99,50)';

% Generate points by revolving profile about z-axis
rev_pts = [];
npts = 0;
for i = 1:(size(extr_data,1))
    for j = 1:length(angle_vector)
        npts = npts+1;
        rev_pts(npts,:) = [[cos(angle_vector(j)) sin(angle_vector(j))].*extr_data(i,1) extr_data(i,2)];
    end
end

% Remove any duplicate points
rev_pts = unique(rev_pts,'rows');

% Generate Delaunay triangulation
rev_pts_tri = delaunayTriangulation(rev_pts);

% Obtain indexes for convex hull
cvh_inds  = convexHull(rev_pts_tri);

% Generate triangulation using indices of convex hull
warning('off','MATLAB:triangulation:PtsNotInTriWarnId')
rev_pts_cvh  = triangulation(cvh_inds,rev_pts_tri.Points);
warning('on','MATLAB:triangulation:PtsNotInTriWarnId')

% Plot points from revolved profile and convex hull if requested
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
    plot3(extr_data(:,1),extr_data(:,1)*0,extr_data(:,2),'d-','LineWidth',2,'MarkerFaceColor',temp_colororder(2,:),'DisplayName','Revolution Profile')
    hold on
    plot3(rev_pts(:,1),rev_pts(:,2),rev_pts(:,3),'o','MarkerSize',2,'MarkerFaceColor',temp_colororder(4,:),'DisplayName','Revolution Points')
    trisurf(rev_pts_cvh,'FaceColor',[0.6 0.6 0.9],'EdgeColor',[0.6 0.6 0.9],'FaceAlpha',0.3,'DisplayName','Convex Hull');
    hold off
    axis equal
    box on
    title('Convex Hull')
    legend('Location','Best')
end

% Generate STL file for convex hull if requested
if(~strcmp(cvhfilename,'none'))
    stlwrite(rev_pts_cvh,cvhfilename);
end

