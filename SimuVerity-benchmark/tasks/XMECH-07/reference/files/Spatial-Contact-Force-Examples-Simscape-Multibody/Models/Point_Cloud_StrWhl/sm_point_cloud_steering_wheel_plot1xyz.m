% Code to plot simulation results from sm_point_cloud_steering_wheel
%% Plot Description:
%
% This script plots the paths of the balls and the final position of the
% steering wheel.  The ball that models contact with the STL file directly
% encounters the convex hull and does not pass through the hole.  The ball
% that models contact with the point cloud passes through the hole in the
% steering wheel.
%
% Copyright 2019-2026 The MathWorks, Inc.

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_point_cloud_steering_wheel', 'var') || ...
        ~isgraphics(h1_sm_point_cloud_steering_wheel, 'figure')
    h1_sm_point_cloud_steering_wheel = figure('Name', 'sm_point_cloud_steering_wheel');
end
figure(h1_sm_point_cloud_steering_wheel)
clf(h1_sm_point_cloud_steering_wheel)

% Generate simulation results if they don't exist
if ~exist('simlog_sm_point_cloud_steering_wheel', 'var')
    sim('sm_point_cloud_steering_wheel')
end

temp_colororder = get(gca,'defaultAxesColorOrder');

simlog_t = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Ball_STL.Pz.p.series.time;
simlog_bstl_px = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Ball_STL.Px.p.series.values('mm');
simlog_bstl_py = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Ball_STL.Py.p.series.values('mm');
simlog_bstl_pz = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Ball_STL.Pz.p.series.values('mm');
simlog_bpcl_px = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Ball_Point_Cloud.Px.p.series.values('mm');
simlog_bpcl_py = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Ball_Point_Cloud.Py.p.series.values('mm');
simlog_bpcl_pz = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Ball_Point_Cloud.Pz.p.series.values('mm');

simlog_swhl_px = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Wheel.Px.p.series.values('mm');
simlog_swhl_py = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Wheel.Py.p.series.values('mm');
simlog_swhl_pz = simlog_sm_point_cloud_steering_wheel.x6_DOF_Joint_Wheel.Pz.p.series.values('mm');

simlog_swhl_rm = logsout_sm_point_cloud_steering_wheel.get('R_StrWhl');
swhl_rm_final = simlog_swhl_rm.Values.Data(:,:,end);
swhl_po_final = [simlog_swhl_px(end) simlog_swhl_py(end) simlog_swhl_pz(end)];

steering_wheel_ptCloud_final = ...
    triangulation(...
    steering_wheel_ptCloud.ConnectivityList,...
    (swhl_rm_final*(steering_wheel_ptCloud.Points)')'+swhl_po_final);


%% Plot results

plot3(simlog_bpcl_px, simlog_bpcl_py, simlog_bpcl_pz, ...
    'LineWidth', 2,'Color','#808080','DisplayName','Ball to Point Cloud');
hold on
plot3(simlog_bstl_px, simlog_bstl_py, simlog_bstl_pz, ...
    'LineWidth', 2,'Color','#CC9900','DisplayName','Ball to Convex Hull');
trimesh(steering_wheel_ptCloud_final,'FaceColor',[0.2 0.6 1.0],'EdgeColor',[0.2 0.6 1.0],'FaceAlpha',0.3,'HandleVisibility','off')
hold off
grid off
box on
view(30,3)
title('Ball Trajectory')
axis equal
legend('Location','Best')

% Remove temporary variables
clear simlog_t simlog_handles temp_colororder

