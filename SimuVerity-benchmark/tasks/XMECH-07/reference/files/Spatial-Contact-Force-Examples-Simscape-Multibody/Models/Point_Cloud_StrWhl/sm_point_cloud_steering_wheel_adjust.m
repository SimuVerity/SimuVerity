%% Read in Steering Wheel STL file
% Copyright 2021-2026 The MathWorks, Inc.
steering_wheel_ptCloud = stlread('steering_wheel_orig.STL');

%% Move Steering wheel to center of solid
steering_wheel_ctr = ...
    triangulation(...
    steering_wheel_ptCloud.ConnectivityList,...
    steering_wheel_ptCloud.Points-((max(steering_wheel_ptCloud.Points)-min(steering_wheel_ptCloud.Points))/2)-min(steering_wheel_ptCloud.Points));

%% Write new steering wheel file
stlwrite(steering_wheel_ctr,'steering_wheel_ctr.stl')

    