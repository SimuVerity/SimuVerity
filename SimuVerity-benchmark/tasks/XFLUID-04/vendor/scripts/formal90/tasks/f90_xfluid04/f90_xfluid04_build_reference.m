function modelPath = f90_xfluid04_build_reference(outDir)
%F90_XFLUID04_BUILD_REFERENCE Build the benchmark exact-source reference.

repoRoot = fullfile(getenv("SIMUVERITY_TASK_VENDOR_ROOT"));
if nargin < 1 || strlength(string(outDir)) == 0
    outDir = fullfile(getenv("SIMUVERITY_TASK_ROOT"), "reference", "files");
else
    outDir = string(outDir);
end
sourceRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
sourceModel = fullfile(sourceRoot,"ssc_hydraulic_lift.slx");
projectPath = fullfile(sourceRoot,"Hydraulic_Lift.prj");
addpath(fullfile(repoRoot,"scripts","xp9"));
addpath(fullfile(repoRoot,"scripts","formal90","tasks","f90_xfluid04"));
assert(isfile(sourceModel),"F90_XFLUID04_SOURCE_MISSING");
assert(strcmpi(xp9_file_presence_file(sourceModel), ...
    "present"), ...
    "F90_XFLUID04_SOURCE_BINDING_MISMATCH");
if ~isfolder(outDir),mkdir(outDir);end
modelPath = fullfile(outDir,"XFLUID04_reference.slx");
if isfile(modelPath),delete(modelPath);end

old = pwd;
cleanupDir = onCleanup(@() cd(old)); %#ok<NASGU>
cd(sourceRoot);
project = openProject(projectPath);
cleanupProject = onCleanup(@() close_project(project)); %#ok<NASGU>
Scissor_Lift_Model_PARAM;

sourceName = "ssc_hydraulic_lift";
load_system(sourceModel);
save_system(sourceName,modelPath);
close_system(sourceName,0);
load_system(modelPath);
model = "XFLUID04_reference";
cleanupModel = onCleanup(@() close_if_loaded(model)); %#ok<NASGU>

def = f90_xfluid04_definition;
for index = 1:numel(def.public_inputs)
    assignin("base",def.public_inputs(index).name, ...
        def.public_inputs(index).nominal);
end

% Keep the source's raise/hold/return operating pattern, but expose its
% trajectory parameters to the task.  The root command is sensor-scaled:
% 2.5 V corresponds to 50 mm and the upper command voltage is obtained
% from the source's own displacement-sensor gain.
command = model + "/Load" + newline + "Height";
targetVoltage = ...
    "2.5+(lift_target_mm-50)*Scissor_Lift_Param.Sensor_Gain/1000";
sequenceTime = "[0 motion_start_s " + ...
    "motion_start_s+ramp_duration_s " + ...
    "motion_start_s+ramp_duration_s+target_hold_s " + ...
    "motion_start_s+2*ramp_duration_s+target_hold_s 20]";
sequenceValue = "[2.5 2.5 " + targetVoltage + " " + ...
    targetVoltage + " 2.5 2.5]";
replace_signal_source_with_sequence(model,command, ...
    sequenceTime,sequenceValue);

% Make the finite pressure source execute the declared in-run disturbance.
pump = model + "/Pump" + newline + "and" + newline + "Tank";
supply = pump + "/Supply" + newline + "Pressure";
replace_signal_source_with_step(pump,supply, ...
    "motion_start_s+ramp_duration_s+pressure_step_offset_s", ...
    "supply_pressure_bar", ...
    "supply_pressure_bar*(1+supply_pressure_step_fraction)");

% Read displacement and velocity directly from the same physical cylinder
% motion sensor.  The source's root Sensing output is P + 0.1 s*V for
% control lead compensation, so it must not be relabeled as pure position.
actuatorCustom = model + "/Actuator/Custom";
actuatorMotionSensor = actuatorCustom + "/" + newline + "Motion Sensor";
assert(getSimulinkBlockHandle(actuatorMotionSensor)>0, ...
    "F90_XFLUID04_ACTUATOR_MOTION_SENSOR_CONTRACT");
motionPorts = get_param(actuatorMotionSensor,"PortHandles");
assert(numel(motionPorts.RConn)>=3, ...
    "F90_XFLUID04_ACTUATOR_MOTION_PORTS_MISSING");

extensionConverter = actuatorCustom + "/Measure Cylinder Extension";
add_block("nesl_utility/PS-Simulink" + newline + "Converter", ...
    extensionConverter,"Unit","mm","Position",[350 85 390 115]);
extensionPorts = get_param(extensionConverter,"PortHandles");
add_line(actuatorCustom,motionPorts.RConn(3), ...
    extensionPorts.LConn(1),"autorouting","on");
add_signal_log(actuatorCustom,extensionConverter,1, ...
    "actuator_extension",[415 85 550 115]);

velocityConverter = actuatorCustom + "/Measure Cylinder Velocity";
add_block("nesl_utility/PS-Simulink" + newline + "Converter", ...
    velocityConverter,"Unit","mm/s","Position",[350 135 390 165]);
velocityPorts = get_param(velocityConverter,"PortHandles");
add_line(actuatorCustom,motionPorts.RConn(2), ...
    velocityPorts.LConn(1),"autorouting","on");
add_signal_log(actuatorCustom,velocityConverter,1, ...
    "actuator_velocity",[415 135 550 165]);

% Tap the source valve's own physical translational-motion sensor.  The
% converter requests millimetres, so no score-side unit conversion exists.
valveCustom = model + "/Valve/Custom";
motionSensor = valveCustom + "/Motion Sensor";
spoolConverter = valveCustom + "/Measure Valve Spool Position";
add_block("nesl_utility/PS-Simulink" + newline + "Converter", ...
    spoolConverter,"Unit","mm","Position",[185 285 225 315]);
motionPorts = get_param(motionSensor,"PortHandles");
converterPorts = get_param(spoolConverter,"PortHandles");
assert(numel(motionPorts.RConn)>=3, ...
    "F90_XFLUID04_VALVE_POSITION_PORT_MISSING");
add_line(valveCustom,motionPorts.RConn(3),converterPorts.LConn(1), ...
    "autorouting","on");
add_signal_log(valveCustom,spoolConverter,1,"valve_spool_position", ...
    [250 285 400 315]);

set_param(model, ...
    "SolverType","Variable-step", ...
    "Solver","ode23t", ...
    "ConcurrentTasks","off", ...
    "StartTime","0", ...
    "StopTime",num2str(def.sim.stop,"%.15g"), ...
    "MaxStep",num2str(def.sim.max_step,"%.15g"), ...
    "ReturnWorkspaceOutputs","on", ...
    "SimMechanicsOpenEditorOnUpdate","off");
annotation = Simulink.Annotation(model, ...
    "F90-XFLUID-04 | pinned electrohydraulic scissor-lift reference | CURRENT");
annotation.Position = [-125 235 505 255];
set_param(model,"SimulationCommand","update");
save_system(model,modelPath);
fprintf("F90_XFLUID04_BUILD_OK path=%s\n",modelPath);
end

function replace_signal_source_with_sequence(parent,block,time,value)
position = get_param(block,"Position");
ports = get_param(block,"PortHandles");
assert(numel(ports.Outport)==1, ...
    "F90_XFLUID04_SOURCE_PORT_CONTRACT:%s",block);
line = get_param(ports.Outport(1),"Line");
assert(line>0,"F90_XFLUID04_SOURCE_LINE_MISSING:%s",block);
destinations = get_param(line,"DstPortHandle");
delete_line(line);
delete_block(block);
add_block("simulink/Sources/Repeating Sequence Interpolated",block, ...
    "TimeValues",time,"OutValues",value, ...
    "LookUpMeth","Interpolation-Use End Values", ...
    "tsamp","0.01","Position",position);
newPorts = get_param(block,"PortHandles");
for index = 1:numel(destinations)
    add_line(parent,newPorts.Outport(1),destinations(index), ...
        "autorouting","on");
end
end

function replace_signal_source_with_step(parent,block,time,before,after)
position = get_param(block,"Position");
ports = get_param(block,"PortHandles");
assert(numel(ports.Outport)==1, ...
    "F90_XFLUID04_SOURCE_PORT_CONTRACT:%s",block);
line = get_param(ports.Outport(1),"Line");
assert(line>0,"F90_XFLUID04_SOURCE_LINE_MISSING:%s",block);
destinations = get_param(line,"DstPortHandle");
delete_line(line);
delete_block(block);
add_block("simulink/Sources/Step",block, ...
    "Time",time,"Before",before,"After",after,"Position",position);
newPorts = get_param(block,"PortHandles");
for index = 1:numel(destinations)
    add_line(parent,newPorts.Outport(1),destinations(index), ...
        "autorouting","on");
end
end

function add_signal_log(parent,source,portIndex,varName,position)
ports = get_param(source,"PortHandles");
assert(numel(ports.Outport)>=portIndex, ...
    "F90_XFLUID04_LOG_SOURCE_PORT_MISSING:%s:%d",source,portIndex);
destination = parent + "/Log_" + varName;
add_block("simulink/Sinks/To Workspace",destination, ...
    "VariableName",varName, ...
    "SaveFormat","Timeseries", ...
    "MaxDataPoints","inf", ...
    "Position",position);
destinationPorts = get_param(destination,"PortHandles");
add_line(parent,ports.Outport(portIndex),destinationPorts.Inport(1), ...
    "autorouting","on");
end

function close_if_loaded(model)
try
    if bdIsLoaded(model),close_system(model,0);end
catch
end
end

function close_project(project)
try
    if ~isempty(project),close(project);end
catch
end
end
