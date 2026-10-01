function ptCldTires = sm_wheel_loader_params_ptclds_tire(varargin)
% Script to generate point clouds from tire CAD geometry.
% Copyright 2021-2025 The MathWorks, Inc

if (nargin==0)
    showplot = 'n';
else
    showplot = varargin{1};
end

% Set of CAD files
tireSTLs = {...
    'TireFL_Wheel_Loader.STL',...
    'TireFR_Wheel_Loader.STL',...
    'TireRL_Wheel_Loader.STL',...
    'TireRR_Wheel_Loader.STL',...
    };

% Field names for point cloud data
tireSuffix = {'FL','FR','RL','RR'};

% Ensure transforms from CAD import are loaded
load('sm_wheel_loader_params_CAD_struct.mat')

% Indices for transforms from CAD geometry reference to wheel center
tireRotMats =[39 40 41 42];

% Loop over tires
for i = 1:length(tireSTLs)

    % Get unique set of points from STL
    tire_stl_points = stlread(tireSTLs{i});
    tire_stl_pts_unique = unique(tire_stl_points.Points,'Rows');

    % Obtain location and rotation matrix
    % from CAD reference frame to wheel center
    ctrPt = Wheel_Loader.coordSys(tireRotMats(i)).transform.translation'*1000;
    RM    = Wheel_Loader.coordSys(tireRotMats(i)).transform.rotation;

    % Calculate radius in yz-plane of each point (distance from center)
    radPts = vecnorm(tire_stl_pts_unique(:,[2 3])-ctrPt(:,[2 3]),2,2);

    % Find points outside of a certain radius
    rimInds = intersect(find(radPts>400),find(radPts<450));

    % Transform selected points from CAD reference to center of wheel
    % and so that z-axis points along axis of wheel rotation
    ptcldPtsCtr = tire_stl_pts_unique(rimInds,:)-ctrPt;
    ptcldPtsCtrOri = (RM*ptcldPtsCtr')';

    % Load into structure for inclusion in model parameters
    ptCldTires.(tireSuffix{i}) = ptcldPtsCtrOri;
end

% Generate cylinder of points from one tire
% Get tire width
tire_width = max(tire_stl_pts_unique(:,1))-min(tire_stl_pts_unique(:,1));
ptCldTires.cyl = Point_Cloud_Data_Cylinder(max(radPts),tire_width,100,0);

if(strcmp(showplot,'plot'))
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

    trimesh(tire_stl_points,'EdgeColor',[0.6 0.6 0.6])
    hold on
    plot3(tire_stl_pts_unique(rimInds,1),tire_stl_pts_unique(rimInds,2),tire_stl_pts_unique(rimInds,3),'b.')
    hold off
    xlabel('x');
    ylabel('y');
    zlabel('z');
    title('Tire CAD Geometry, Point Cloud')
    box on
    axis equal
end