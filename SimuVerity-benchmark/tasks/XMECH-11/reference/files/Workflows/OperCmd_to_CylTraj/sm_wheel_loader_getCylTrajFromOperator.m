% Code to use vehicle model and extract cylinder trajectories of hydraulic
% actuation with operator commands.  This enables testing with ideal
% actuators which use prescribed motion and run much faster.

% Copyright 2023-2025 The MathWorks, Inc.

%% Open model
mdl = 'sm_wheel_loader_vehicle';
open_system(mdl)

%% Configure for bucket load test on flat ground and run
set_param([bdroot '/Wheel Loader'],'popup_driveline','1D, CV Joints')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
sm_wheel_loader_config_impl(mdl,'Bucket Load');
set_param([bdroot '/Wheel Loader'],'popup_actuator_model','Hydraulic');
sim(mdl)

% Extract cylinder trajectories
cylResultsBucketLoad = sm_wheel_loader_getCylTraj(logsout_sm_wheel_loader_vehicle.get('mVehicle').Values);

%% Configure for grapple log test test on flat ground and run
set_param([bdroot '/Wheel Loader'],'popup_driveline','1D, CV Joints')
set_param([bdroot '/Wheel Loader'],'popup_surface','Plane (Spheres)');
sm_wheel_loader_config_impl(mdl,'Grapple Log');
set_param([bdroot '/Wheel Loader'],'popup_actuator_model','Hydraulic');
sim(mdl)

% Extract cylinder trajectories
cylResultsGrappleLoad = sm_wheel_loader_getCylTraj(logsout_sm_wheel_loader_vehicle.get('mVehicle').Values);

%% Save results so that simulations do not have to be re-run
save refCylRes cylResultsBucketLoad cylResultsGrappleLoad

%% Explore Results Bucket
figure(1)
plot(cylResultsBucketLoad.time,cylResultsBucketLoad.pLift.values,'DisplayName','Lift')
hold on
plot(cylResultsBucketLoad.time,cylResultsBucketLoad.pTilt.values,'DisplayName','Tilt')
plot(cylResultsBucketLoad.time,cylResultsBucketLoad.pStr.values,'DisplayName','Steer')
hold off
xlabel('Time')
ylabel('Position (m)')
title('Bucket Test')

%% Sample simulation results at a fixed sample time
% Note - do not use as input with linear interpolation
% Piecewise linear in position, discrete steps in velocity, impulse in
% acceleration will lead to long simulation times.

tSample = 0.1;
tInterp = cylResultsBucketLoad.time(1):tSample:cylResultsBucketLoad.time(end);
pLiftRef = interp1(cylResultsBucketLoad.time,cylResultsBucketLoad.pLift.values,tInterp);
pTiltRef = interp1(cylResultsBucketLoad.time,cylResultsBucketLoad.pTilt.values,tInterp);
pStrRef  = interp1(cylResultsBucketLoad.time,cylResultsBucketLoad.pStr.values,tInterp);

% Steering command needs to be amplified a tiny bit due to filters and
% spring compression.  Important for open-loop grapple log test, not so
% critical for bucket test.
pStrRef = pStrRef + (pStrRef-pStrRef(1))*0.01;

%% Extract simulation results at points near when open-loop inputs change
% Take points 0.2 seconds before and after each input change
% Use sort and unique in case input changes are within 0.2 seconds
liftTforInterp = [BucketYCycle{1}.Time; BucketYCycle{1}.Time+0.2; BucketYCycle{1}.Time-0.2];
liftTforInterp = sort(unique(liftTforInterp));
liftTforInterp = liftTforInterp(find(liftTforInterp>=0));
liftTforInterp = liftTforInterp(find(liftTforInterp<=70));

tiltTforInterp = [BucketYCycle{2}.Time; BucketYCycle{2}.Time+0.2; BucketYCycle{2}.Time-0.2];
tiltTforInterp = sort(unique(tiltTforInterp));
tiltTforInterp = tiltTforInterp(find(tiltTforInterp>=0));
tiltTforInterp = tiltTforInterp(find(tiltTforInterp<=70));

steerTforInterp = [BucketYCycle{3}.Time; BucketYCycle{3}.Time+0.2; BucketYCycle{3}.Time-0.2];
steerTforInterp = sort(unique(steerTforInterp));
steerTforInterp = steerTforInterp(find(steerTforInterp>=0));
steerTforInterp = steerTforInterp(find(steerTforInterp<=70));

% Use interpolation to extract points at times of interest
pLiftRefTC = interp1(cylResultsBucketLoad.time,cylResultsBucketLoad.pLift.values,liftTforInterp);
pTiltRefTC = interp1(cylResultsBucketLoad.time,cylResultsBucketLoad.pTilt.values,tiltTforInterp);
pStrRefTC  = interp1(cylResultsBucketLoad.time,cylResultsBucketLoad.pStr.values,steerTforInterp);

hold on
plot(tInterp,pLiftRef,'k.','DisplayName','Ref')
plot(tInterp,pTiltRef,'k.','DisplayName','Ref')
plot(tInterp,pStrRef,'k.','DisplayName','Ref')
hold off

% testInput.BucketYCycle.tRef     = tInterp';
% testInput.BucketYCycle.pLiftRef = pLiftRef';
% testInput.BucketYCycle.pTiltRef = pTiltRef';
% testInput.BucketYCycle.pStrRef  = pStrRef';
% testInput.name = 'BucketYCycle';
testInput.BucketYCycle.Lift.t   = liftTforInterp;
testInput.BucketYCycle.Lift.p   = pLiftRefTC;
testInput.BucketYCycle.Tilt.t   = tiltTforInterp;
testInput.BucketYCycle.Tilt.p   = pTiltRefTC;
testInput.BucketYCycle.Steer.t  = steerTforInterp;
testInput.BucketYCycle.Steer.p  = pStrRefTC;
testInput.BucketYCycle.name     = 'BucketYCycle';

%% Explore Results Grapple
figure(2)
plot(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pLift.values,'DisplayName','Lift')
hold on
plot(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pTilt.values,'DisplayName','Tilt')
plot(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pStr.values,'DisplayName','Steer')
hold off
xlabel('Time')
ylabel('Position (m)')
title('Grapple Test')

%% Sample simulation results at a fixed sample time
% Note - do not use as input with linear interpolation
% Piecewise linear in position, discrete steps in velocity, impulse in
% acceleration will lead to long simulation times.

tSample = 0.1;
tInterp = cylResultsGrappleLoad.time(1):tSample:cylResultsGrappleLoad.time(end);
pLiftRef = interp1(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pLift.values,tInterp);
pTiltRef = interp1(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pTilt.values,tInterp);
pStrRef = interp1(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pStr.values,tInterp);

% Steering command needs to be amplified a tiny bit due to filters and
% spring compression.  Important for open-loop grapple log test, not so
% critical for bucket test.
pStrRef = pStrRef + (pStrRef-pStrRef(1))*0.01;

%% Extract simulation results at points near when open-loop inputs change
% Take points 0.2 seconds before and after each input change
% Use sort and unique in case input changes are within 0.2 seconds
liftTforInterp = [GrappleLogCycle{1}.Time; GrappleLogCycle{1}.Time+0.2; GrappleLogCycle{1}.Time-0.2];
liftTforInterp = sort(unique(liftTforInterp));
liftTforInterp = liftTforInterp(find(liftTforInterp>=0));
liftTforInterp = liftTforInterp(find(liftTforInterp<=70));

tiltTforInterp = [GrappleLogCycle{2}.Time; GrappleLogCycle{2}.Time+0.2; GrappleLogCycle{2}.Time-0.2];
tiltTforInterp = sort(unique(tiltTforInterp));
tiltTforInterp = tiltTforInterp(find(tiltTforInterp>=0));
tiltTforInterp = tiltTforInterp(find(tiltTforInterp<=70));

steerTforInterp = [GrappleLogCycle{3}.Time; GrappleLogCycle{3}.Time+0.2; GrappleLogCycle{3}.Time-0.2];
steerTforInterp = sort(unique(steerTforInterp));
steerTforInterp = steerTforInterp(find(steerTforInterp>=0));
steerTforInterp = steerTforInterp(find(steerTforInterp<=70));

% Use interpolation to extract points at times of interest
pLiftRefTC = interp1(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pLift.values,liftTforInterp);
pTiltRefTC = interp1(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pTilt.values,tiltTforInterp);
pStrRefTC  = interp1(cylResultsGrappleLoad.time,cylResultsGrappleLoad.pStr.values,steerTforInterp);

hold on
plot(tInterp,pLiftRef,'k.','DisplayName','Ref')
plot(tInterp,pTiltRef,'k.','DisplayName','Ref')
plot(tInterp,pStrRef,'k.','DisplayName','Ref')
hold off

% testInput.GrappleLogCycle.tRef     = tInterp';
% testInput.GrappleLogCycle.pLiftRef = pLiftRef';
% testInput.GrappleLogCycle.pTiltRef = pTiltRef';
% testInput.GrappleLogCycle.pStrRef  = pStrRef';
% testInput.name = 'GrappleLogCycle';
testInput.GrappleLogCycle.Lift.t   = liftTforInterp;
testInput.GrappleLogCycle.Lift.p   = pLiftRefTC;
testInput.GrappleLogCycle.Tilt.t   = tiltTforInterp;
testInput.GrappleLogCycle.Tilt.p   = pTiltRefTC;
testInput.GrappleLogCycle.Steer.t  = steerTforInterp;
testInput.GrappleLogCycle.Steer.p  = pStrRefTC;
testInput.GrappleLogCycle.name     = 'GrappleLogCycle';

save sm_wheel_loader_test_cylinder_traj testInput

