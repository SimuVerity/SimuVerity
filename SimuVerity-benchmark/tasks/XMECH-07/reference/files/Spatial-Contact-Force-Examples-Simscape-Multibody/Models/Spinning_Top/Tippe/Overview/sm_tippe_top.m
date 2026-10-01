%% Spinning Top, Contact Methods (Tippe Shape)
%
% This example models a top spinning on a flat surface. The top consists of
% a narrow shaft and a truncated sphere. When spun at high speeds, the stem
% will tilt downwards until it lifts the body of the top off of the ground.
% Mask parameters select whether contact with the floor is modeled using a
% sphere or a point cloud. A point cloud will result in higher amounts of
% friction forces with the floor for the same friction coefficients.
%
% Copyright 2022-2026 The MathWorks, Inc.

%% Model

open_system('sm_tippe_top')

set_param(find_system('sm_tippe_top','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Body of Top and Contact Proxies
%
% Two types of geometry can used to model contact the floor. For both the
% truncated sphere and the stem, either a single sphere (single point of
% contact) or a point cloud can be used.  The biggest difference in
% behavior is that for objects spinning about an axis that goes through the
% point of contact, no friction is generated.  As a result, the point cloud
% will have higher levels of friction for the spinning top for the same
% friction coefficients.

open_system('sm_tippe_top/Top','force')


%% Points For Truncated Sphere
%
% A set of points is used to define the profile of the truncated sphere.
% The internal profile of the sphere adjusts the location of the center of
% mass which influences how quickly the top will flip over.
%
sm_tippe_top_plot3headrevolution;

%% Convex Hull 
%
% If the top were defined as a single solid, the Spatial Contact Force
% block would use its convex hull to detect contact with the floor.  This
% plot shows what that convex hull would look like.
%
sm_convex_hull_pointcloud(ptcld_cvh,'none','plot');

%% Simulation Results from Simscape Logging
%%
%
% This is a plot of the rotational speed of the top. The rotational speed
% of the top about its axis switches direction as the top flips over and
% stands on its stem. Eventually the top slows down enough that both the
% stem and the body are touching the ground, and the top is rolling in a
% circle.
%

sm_tippe_top_plot1speed;

%% Simulation Results from Simscape Logging: Comparing Contact Proxies
%%
%
% This plot compares the effect of selected contact proxies at the head and
% base of the top.  The Point Cloud will result in higher levels of
% friction than the sphere for the same friction coefficients.  This is
% because multi-point contact will have a higher relative velocity,
% especially for objects that spin about an axis that passes through the
% contact point.
%

sm_tippe_top_plot2compareproxies;

%%

%clear all
close all
bdclose all
