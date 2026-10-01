%% Wheel Loader Chassis, Drivetrain, and Linkage
% 
% <<sm_wheel_loader_vehicle_Overview.png>>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
% 
% This example models a wheel loader actuation system, steering, linkage
% with implement, drivetrain and chassis.  
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a wheel loader actuation system, linkage with
% implement, steering system, drivetrain, and chassis. The powertrain is modeled as an
% ideal power source to speed up simulations by reducing computation.
%
% <matlab:open_system('sm_wheel_loader_vehicle'); Open Model>

open_system('sm_wheel_loader_vehicle')

set_param([bdroot '/Wheel Loader'],'popup_driveline','1D, CV Joints')
sm_wheel_loader_config_impl(bdroot,'Bucket')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
set_param([bdroot '/Wheel Loader'],'popup_actuator_model','Hydraulic')

ann_h = find_system('sm_wheel_loader_vehicle','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures');
for anhi=1:length(ann_h)
    set_param(ann_h(anhi),'Interpreter','off');
end

%% Vehicle Subsystem
%
% Model of the wheel loader vehicle, including front and rear articulated
% chassis, driveline, and linkage.  An optional load can be added using
% variant subsystems.  
% 
% The fidelity level of the mechanical driveline model can be set to
% different options:
%
% * *Driveline 1D* : Shafts are modeled as rotational inertias only.
% Simulation runs very quickly.
% * *Driveline 3D* : Shafts are modeled with a 3D multibody model.
% Captures all rigid body dynamics of the system.
%
% The actuation model for the steering, linkage, and implements can be
% configured to use the following options
%
% * *Ideal*: Cylinder positions are set using prescribed motion.
% Simulation runs very quickly.  Used to determine actuator requirements.
% * *Hydraulic*: Hydraulic pumps, valves, and cylinders are used to
% model the actuation system.  Used to select hydraulic components and set
% pressure levels.
%
% <matlab:open_system('sm_wheel_loader_vehicle');open_system('sm_wheel_loader_vehicle/Wheel%20Loader/Vehicle','force'); Open Subsystem>

set_param('sm_wheel_loader_vehicle/Wheel Loader/Vehicle','LinkStatus','none')
open_system('sm_wheel_loader_vehicle/Wheel Loader/Vehicle','force')

%% Actuator Subsystem: Hydraulic
%
% In this configuration the cylinders are actuated by a hydraulic system.
% Pumps are driven by the PTO shaft, one for the linkage and implements and
% another for the steering system. Valves control the flow of hydraulic
% fluid to the actuators which extend and contract to the desired position.
%
% The interface from this 1D model of the hydromechanical system and the 3D
% multibody of the linkage is a 1D mechanical connection for the rod of
% each cylinder.
%
% <matlab:open_system('sm_wheel_loader_vehicle');open_system('sm_wheel_loader_vehicle/Wheel%20Loader/Vehicle/Actuators/Hydraulic','force'); Open Subsystem>

set_param('sm_wheel_loader_vehicle/Wheel Loader/Vehicle/Actuators/Hydraulic','LinkStatus','none')
open_system('sm_wheel_loader_vehicle/Wheel Loader/Vehicle/Actuators/Hydraulic','force')

%% Driveline 3D Subsystem
%
% Models a four-wheel drive driveline using parts imported from a CAD
% assembly.  The output of the CVT connects to the output transfer gear
% which is connected via differentials to all four wheels.  A separate
% variant models the driveline as a 1D mechanical model that can be used
% for exploring the design space of shaft sizes and gear ratios.
%
% <matlab:open_system('sm_wheel_loader_vehicle');open_system('sm_wheel_loader_vehicle/Wheel%20Loader/Vehicle/Driveline/Driveline/Driveline%203D','force'); Open Subsystem>

set_param([bdroot '/Wheel Loader'],'popup_driveline','3D, U Joints')
set_param([bdroot '/Wheel Loader/Vehicle/Driveline/Driveline/Driveline 3D'],'LinkStatus','none')
open_system([bdroot '/Wheel Loader/Vehicle/Driveline/Driveline/Driveline 3D'],'force')
set_param(bdroot,'SimulationCommand','update')

%% Driveline 1D Subsystem
%
% Models a four-wheel drive driveline using parts imported from a CAD
% assembly.  The output of the CVT connects to the output transfer gear
% which is connected via differentials to all four wheels.  A separate
% variant models the driveline as a 1D mechanical model that can be used
% for exploring the design space of shaft sizes and gear ratios.
%
% <matlab:open_system('sm_wheel_loader_vehicle');open_system('sm_wheel_loader_vehicle/Wheel%20Loader/Vehicle/Driveline/Driveline/Driveline%201D/Driveline','force'); Open Subsystem>

set_param([bdroot '/Wheel Loader'],'popup_driveline','1D, CV Joints')
set_param([bdroot '/Wheel Loader/Vehicle/Driveline/Driveline/Driveline 1D/Driveline'],'LinkStatus','none')
open_system([bdroot '/Wheel Loader/Vehicle/Driveline/Driveline/Driveline 1D/Driveline'],'force')
set_param(bdroot,'SimulationCommand','update')

%% Ground Contact FL: Sphere
%
% The simplest ground contact model uses a sphere to represent the tire.
% This is suitable for use on a flat, planes where we can assume a single
% point of contact with any individual plane.  The Spatial Contact Force in
% Simscape Multibody models normal and friction force between the sphere
% and the road surface.
%
% <matlab:open_system('sm_wheel_loader_vehicle');open_system('sm_wheel_loader_vehicle/Wheel%20Loader/Vehicle/Driveline/Ground%20Contact%20FL/Sphere','force'); Open Subsystem>

set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
set_param([bdroot '/Wheel Loader/Vehicle/Driveline/Ground Contact FL/Sphere'],'LinkStatus','none')
open_system([bdroot '/Wheel Loader/Vehicle/Driveline/Ground Contact FL/Sphere'],'force')


%% Ground Contact FL: Multibody Magic Formula Tire
%
% A more advanced contact model uses standard Magic Formula to represent
% contact between the tire and the ground.  This is suitable for use on a
% flat or uneven surfaces.  It models normal and friction force between the
% tire and road surface at the contact point.  Note that the steady-state
% version of the magic formula tire equations does not include vertical
% damping.  Since our vehicle suspension has no damping, we include a
% vertical damping component by adding a sphere at the center of the tire
% and only enabling vertical damping in the Spatial Contact Force block for
% the connection between the sphere and the ground.
%
% <matlab:open_system('sm_wheel_loader_vehicle');open_system('sm_wheel_loader_vehicle/Wheel%20Loader/Vehicle/Driveline/Ground%20Contact%20FL/Tire','force'); Open Subsystem>

set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Tires)');
set_param([bdroot '/Wheel Loader/Vehicle/Driveline/Ground Contact FL'],'LinkStatus','none')
set_param([bdroot '/Wheel Loader/Vehicle/Driveline/Ground Contact FL/Tire'],'LinkStatus','none')
open_system([bdroot '/Wheel Loader/Vehicle/Driveline/Ground Contact FL/Tire'],'force')
set_param(bdroot,'SimulationCommand','update')

%% Ground Contact FL: Point Cloud
%
% A more advanced contact model uses a point cloud to model the geometry of
% the tire.  This is suitable for use on a flat or uneven surfaces.  It
% models normal and friction force between the tire and road surface at all
% points of the point cloud that touch the road surface.  This block can be
% connected via the Spatial Contact Force block to a grid surface.  This
% lets us test the wheel loader on uneven terrain.
%
% <matlab:open_system('sm_wheel_loader_vehicle');open_system('sm_wheel_loader_vehicle/Wheel%20Loader/Vehicle/Driveline/Ground%20Contact%20FL/Points','force'); Open Subsystem>

set_param([bdroot '/Wheel Loader'],'popup_surface','Terrain');
set_param([bdroot '/Wheel Loader/Vehicle/Driveline/Ground Contact FL/Points'],'LinkStatus','none')
open_system([bdroot '/Wheel Loader/Vehicle/Driveline/Ground Contact FL/Points'],'force')
set_param(bdroot,'SimulationCommand','update')


%% Simulation Results: Y Cycle, 1D Driveline, Bucket, Ideal Actuation, Spheres
%%
%
% Run a bucket load Y cycle test with 1D driveline, ideal actuation, and
% spheres for wheel-ground contact.
%

set_param([bdroot '/Wheel Loader'],'popup_driveline','1D, CV Joints')
sm_wheel_loader_config_impl(bdroot,'Bucket')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
set_param([bdroot '/Wheel Loader'],'popup_actuator_model','Ideal')

sim('sm_wheel_loader_vehicle');

sm_wheel_loader_plot1whlspd(simlog_sm_wheel_loader_vehicle,HMPST.Tire.Rad)
sm_wheel_loader_plot2vehpos(simlog_sm_wheel_loader_vehicle)
sm_wheel_loader_plot4linkage(logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)
sm_wheel_loader_plot5steer(simlog_sm_wheel_loader_vehicle.Wheel_Loader,logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)

%% Simulation Results: Y Cycle, 1D Driveline, Bucket, Ideal Actuation, Multibody Magic Formula Tire
%%
%
% Run a bucket load Y cycle test with 1D driveline, ideal actuation, and
% Multibody Magic Formula tires.

set_param([bdroot '/Wheel Loader'],'popup_driveline','1D, CV Joints')
sm_wheel_loader_config_impl(bdroot,'Bucket')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Tires)');

sim('sm_wheel_loader_vehicle');

sm_wheel_loader_plot1whlspd(simlog_sm_wheel_loader_vehicle,HMPST.Tire.Rad)
sm_wheel_loader_plot2vehpos(simlog_sm_wheel_loader_vehicle)
sm_wheel_loader_plot4linkage(logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)
sm_wheel_loader_plot5steer(simlog_sm_wheel_loader_vehicle.Wheel_Loader,logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)

%% Simulation Results: Y Cycle, 1D Driveline, Grapple, Hydraulic Actuation, Spheres
%%
%
% Run a grapple load Y cycle test with 1D driveline, hydraulic actuation,
% and spheres for wheel-ground contact.
%

set_param([bdroot '/Wheel Loader'],'popup_driveline','1D, CV Joints')
sm_wheel_loader_config_impl(bdroot,'Grapple')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
set_param([bdroot '/Wheel Loader'],'popup_actuator_model','Hydraulic')

sim('sm_wheel_loader_vehicle');

sm_wheel_loader_plot1whlspd(simlog_sm_wheel_loader_vehicle,HMPST.Tire.Rad)
sm_wheel_loader_plot2vehpos(simlog_sm_wheel_loader_vehicle)
sm_wheel_loader_plot4linkage(logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)
sm_wheel_loader_plot5steer(simlog_sm_wheel_loader_vehicle.Wheel_Loader,logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)
sm_wheel_loader_plot6linkagehydr(simlog_sm_wheel_loader_vehicle.Wheel_Loader.Vehicle.Actuators)
sm_wheel_loader_plot7steerhydr(simlog_sm_wheel_loader_vehicle.Wheel_Loader.Vehicle.Actuators.Hydraulic)

%% Simulation Results: Y Cycle, 3D Driveline CV Joints, Bucket, Ideal Actuation, Spheres
%%
%
% Run a bucket load Y cycle test with 3D driveline, CV joints, and ideal
% actuation.
%

set_param([bdroot '/Wheel Loader'],'popup_driveline','3D, CV Joints')
sm_wheel_loader_config_impl(bdroot,'Bucket')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
set_param([bdroot '/Wheel Loader'],'popup_actuator_model','Ideal')

sim('sm_wheel_loader_vehicle');

sm_wheel_loader_plot1whlspd(simlog_sm_wheel_loader_vehicle,HMPST.Tire.Rad)
sm_wheel_loader_plot2vehpos(simlog_sm_wheel_loader_vehicle)
sm_wheel_loader_plot5steer(simlog_sm_wheel_loader_vehicle.Wheel_Loader,logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)

%% Simulation Results: Load Cycle, 3D Driveline, U-Joints
%%
%
% Run a bucket load Y cycle test with 3D driveline, U joints, and ideal
% actuation.
%

set_param([bdroot '/Wheel Loader'],'popup_driveline','3D, U Joints')
sm_wheel_loader_config_impl(bdroot,'Bucket')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
set_param([bdroot '/Wheel Loader'],'popup_actuator_model','Ideal')

sim('sm_wheel_loader_vehicle');

sm_wheel_loader_plot1whlspd(simlog_sm_wheel_loader_vehicle,HMPST.Tire.Rad)
sm_wheel_loader_plot2vehpos(simlog_sm_wheel_loader_vehicle)
sm_wheel_loader_plot5steer(simlog_sm_wheel_loader_vehicle.Wheel_Loader,logsout_sm_wheel_loader_vehicle.get('mVehicle').Values)

%%

close all
bdclose('sm_wheel_loader_vehicle');
