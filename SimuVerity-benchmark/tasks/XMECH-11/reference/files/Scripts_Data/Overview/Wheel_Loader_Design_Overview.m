%% Wheel Loader Design with Simscape(TM)
%
% <<Wheel_Loader_Design_Overview.png>>
% 
% This repository contains models and code to help engineers design
% wheel loaders. 
%
% * *Early-stage physical design* is supported by calculating
% ratios for geartrains and hydrostatic transmissions to achieve desired speed ranges.
% * *Integrated testing of physical system and controller* is supported by
% a hydromechanical model of the CVT, powertrain, and linkage.
%
%
% Copyright 2023-2025 The MathWorks, Inc.

%%
% *Complete Wheel Loader Model*
% 
% # Wheel Loader with Power Split CVT: <matlab:open_system('sm_wheel_loader') Model>, <matlab:web('sm_wheel_loader.html') Documentation>
%
% *CVT Test Models*
%
% # Hydromechanical Power Split CVT: <matlab:open_system('ssc_hydromech_power_split_cvt') Model>, <matlab:web('ssc_hydromech_power_split_cvt.html') Documentation>
% # Hydromechanical Power Split CVT with Engine: <matlab:open_system('ssc_hydromech_power_split_cvt_engine') Model>, <matlab:web('ssc_hydromech_power_split_cvt_engine.html') Documentation>
% # Power Split CVT with Four Speed Ranges (Multibody): <matlab:open_system('sm_cvt_power_split_pg_4range') Model>, <matlab:web('sm_cvt_power_split_pg_4range.html') Documentation>
% # Power Split Planetary Gear (Multibody): <matlab:open_system('sm_cvt_power_split_pg') Model>, <matlab:web('sm_cvt_power_split_pg.html') Documentation>
%
% *Vehicle, Linkage, and Steering Models*
% 
% # Wheel Loader Chassis, Drivetrain, and Linkage: <matlab:open_system('sm_wheel_loader_vehicle') Model>, <matlab:web('sm_wheel_loader_vehicle.html') Documentation>
% # Wheel Loader Linkage: <matlab:open_system('sm_wheel_loader_linkage') Model>, <matlab:web('sm_wheel_loader_linkage.html') Documentation>
% # Wheel Loader Steering: <matlab:open_system('sm_wheel_loader_steer') Model>, <matlab:web('sm_wheel_loader_steer.html') Documentation>
%
% *Driveline Test Models*
%
% # Differential Front: <matlab:open_system('sm_wheel_loader_diff_f') Model>, <matlab:web('sm_wheel_loader_diff_f.html') Documentation>
% # Differential Rear: <matlab:open_system('sm_wheel_loader_diff_r') Model>, <matlab:web('sm_wheel_loader_diff_r.html') Documentation>
% # Axle Front: <matlab:open_system('sm_wheel_loader_drive_f') Model>, <matlab:web('sm_wheel_loader_drive_f.html') Documentation>
% # Axle Rear: <matlab:open_system('sm_wheel_loader_drive_r') Model>, <matlab:web('sm_wheel_loader_drive_r.html') Documentation>
% # Driveline Joint: <matlab:open_system('sm_wheel_loader_driveline') Model>, <matlab:web('sm_wheel_loader_driveline.html') Documentation>
% # Planetary Gear Wheel Hub: <matlab:open_system('sm_wheel_loader_planetary_gear') Model>, <matlab:web('sm_wheel_loader_planetary_gear.html') Documentation>
%
% *Workflows*
%
% # Power Split CVT Design:
% <matlab:web('optim_cvt_power_split_design.html') Documentation>,
% <matlab:run('CVT_Calculate_Swash_Control_app_run.m'); MATLAB App>
% # Terrain Definition from STL: <matlab:web('wheel_loader_surface_terrain.html') Documentation>
% # Tire Point Cloud from STL: <matlab:web('wheel_loader_point_cloud_tire.html') Documentation>

