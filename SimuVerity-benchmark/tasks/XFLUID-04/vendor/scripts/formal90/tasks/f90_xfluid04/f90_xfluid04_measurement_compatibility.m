function varargout = f90_xfluid04_measurement_compatibility(helperName, varargin)
%f90_xfluid04_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xfluid04_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["run_scenario", "static_audit", "nominal_values", "empty_row", "paired_causality"];
        end
    case "run_scenario"
        if nargout == 0
            run_scenario(varargin{:});
        else
            [varargout{1:nargout}] = run_scenario(varargin{:});
        end
    case "static_audit"
        if nargout == 0
            static_audit(varargin{:});
        else
            [varargout{1:nargout}] = static_audit(varargin{:});
        end
    case "nominal_values"
        if nargout == 0
            nominal_values(varargin{:});
        else
            [varargout{1:nargout}] = nominal_values(varargin{:});
        end
    case "empty_row"
        if nargout == 0
            empty_row(varargin{:});
        else
            [varargout{1:nargout}] = empty_row(varargin{:});
        end
    case "paired_causality"
        if nargout == 0
            paired_causality(varargin{:});
        else
            [varargout{1:nargout}] = paired_causality(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xfluid04_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function row = run_scenario(model,id,scenarioValues,def)
fields = fieldnames(scenarioValues);
for index = 1:numel(fields)
    assignin("base",fields{index},scenarioValues.(fields{index}));
end
set_param(model,"StopTime",num2str(def.sim.stop,"%.15g"), ...
    "ReturnWorkspaceOutputs","on");
out = sim(model);

series = cell(numel(def.outputs),1);
for index = 1:numel(def.outputs)
    name = def.outputs(index).name;
    series{index} = simuverity_public_output_compatibility( ...
        out,string(name),def.outputs(index).channels, ...
        AllowBaseWorkspace=true);
    validate_timeseries(series{index},def.outputs(index).channels, ...
        def.sim.stop,name);
end
extension = scalar_data(series{1});
velocity = scalar_data(series{2});
spool = scalar_data(series{3});
te = double(series{1}.Time(:));
tv = double(series{2}.Time(:));
ts = double(series{3}.Time(:));

target = scenarioValues.lift_target_mm;
initial = def.sim.initial_extension_mm;
t0 = scenarioValues.motion_start_s;
t1 = t0 + scenarioValues.ramp_duration_s;
t2 = t1 + scenarioValues.target_hold_s;
t3 = t2 + scenarioValues.ramp_duration_s;
pressureTime = t1 + scenarioValues.pressure_step_offset_s;
reference = cycle_reference(te,initial,target,t0,t1,t2,t3);
trackingError = extension-reference;

initialE = te <= min(.60,.50*t0);
cycleE = te >= t0 & te <= min(def.sim.stop,t3+.8);
upperE = te >= t1+.40 & te <= t2-.25;
upperOvershootE = te >= t1 & te <= t2;
tailE = te >= max(t3+.5,def.sim.stop-2);
tailV = tv >= max(t3+.5,def.sim.stop-2);
tailS = ts >= max(t3+.5,def.sim.stop-2);
prePressureE = te >= pressureTime-.80 & te <= pressureTime-.15;
postEnd = min(t2-.05,pressureTime+3);
postPressureE = te >= pressureTime & te <= postEnd;
prePressureS = ts >= pressureTime-.80 & ts <= pressureTime-.15;
postPressureS = ts >= pressureTime & ts <= postEnd;
assert(nnz(initialE)>=5 && nnz(cycleE)>=20 && nnz(upperE)>=10 && ...
    nnz(tailE)>=5 && nnz(tailV)>=5 && nnz(tailS)>=5 && ...
    nnz(prePressureE)>=5 && nnz(postPressureE)>=5 && ...
    nnz(prePressureS)>=5 && nnz(postPressureS)>=5, ...
    "F90_XFLUID04_METRIC_WINDOWS");

preExtension = mean(extension(prePressureE));
preSpool = mean(spool(prePressureS));
pressureExtensionExcursion = ...
    max(abs(extension(postPressureE)-preExtension));
pressureSpoolResponse = ...
    max(abs(spool(postPressureS)-preSpool));
pressureRecovery = recovery_in_window(te,abs(trackingError), ...
    pressureTime,t2,3,.60);
commandMagnitude = max(abs(target-initial),1);

row = empty_row;
row.id = id;
row.valid = true;
row.pressure_step_fraction = scenarioValues.supply_pressure_step_fraction;
row.pressure_step_time_s = pressureTime;
row.initial_extension_error_mm = abs(mean(extension(initialE))-initial);
row.cycle_tracking_rmse_mm = sqrt(mean(trackingError(cycleE).^2));
row.cycle_peak_tracking_error_mm = max(abs(trackingError(cycleE)));
row.upper_hold_error_mm = abs(mean(extension(upperE))-target);
row.return_error_mm = abs(mean(extension(tailE))-initial);
row.command_motion_fraction = ...
    (max(extension(cycleE))-mean(extension(initialE)))/commandMagnitude;
row.upper_overshoot_mm = ...
    max(0,max(extension(upperOvershootE))-target);
row.tail_oscillation_mm = max(extension(tailE))-min(extension(tailE));
row.tail_velocity_rms_mm_per_s = ...
    sqrt(mean(velocity(tailV).^2));
row.peak_velocity_mm_per_s = max(abs(velocity));
row.peak_spool_mm = max(abs(spool));
row.tail_spool_rms_mm = sqrt(mean(spool(tailS).^2));
row.pressure_extension_excursion_mm = pressureExtensionExcursion;
row.pressure_spool_response_peak_mm = pressureSpoolResponse;
row.pressure_tracking_rmse_mm = ...
    sqrt(mean(trackingError(postPressureE).^2));
row.pressure_peak_tracking_error_mm = ...
    max(abs(trackingError(postPressureE)));
row.pressure_recovery_s = pressureRecovery;
row.error = "";
end

function audit = static_audit(model,def)
blocks = find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "Type","Block");
counts = struct( ...
    "pressure_sources",0, ...
    "reservoirs",0, ...
    "directional_or_metering_valves",0, ...
    "translational_liquid_converters",0, ...
    "translational_motion_sensors",0, ...
    "electromechanical_converters",0, ...
    "controller_like",0, ...
    "multibody_joints",0, ...
    "solid_or_mass_elements",0);
for index = 1:numel(blocks)
    text = lower(identity_text(blocks{index}));
    counts.pressure_sources = counts.pressure_sources + ...
        double(contains(text,"pressure source (il)") || ...
        contains(text,"pressure_source") || ...
        contains(text,"hydraulic pressure source") || ...
        contains(text,"constant pressure source"));
    counts.reservoirs = counts.reservoirs + ...
        double(contains(text,"reservoir (il)") || ...
        contains(text,"isothermal_liquid.elements.reservoir") || ...
        contains(text,"hydraulic reservoir") || ...
        contains(text,"hydraulic reference"));
    counts.directional_or_metering_valves = ...
        counts.directional_or_metering_valves + ...
        double(contains(text,"directional valve") || ...
        contains(text,"local restriction (il)") || ...
        contains(text,"local_restriction") || ...
        contains(text,"variable orifice"));
    counts.translational_liquid_converters = ...
        counts.translational_liquid_converters + ...
        double(contains(text,"translational mechanical converter (il)") || ...
        contains(text,"translational_converter")) + ...
        2*double(contains(text,"double-acting hydraulic cylinder") || ...
        contains(text,"double-acting actuator"));
    counts.translational_motion_sensors = ...
        counts.translational_motion_sensors + ...
        double(contains(text,"translational motion sensor") || ...
        contains(text,"mechanical.sensors.velocity"));
    counts.electromechanical_converters = ...
        counts.electromechanical_converters + ...
        double(contains(text,"rotational electromechanical converter") || ...
        contains(text,"rotational_converter"));
    counts.controller_like = counts.controller_like + ...
        double(contains(text,"operational amplifier") || ...
        contains(text,"op-amp") || contains(text,"controller") || ...
        contains(text,"pid") || contains(text,"compensator"));
    counts.multibody_joints = counts.multibody_joints + ...
        double(contains(text,"revolute joint") || ...
        contains(text,"prismatic joint"));
    counts.solid_or_mass_elements = counts.solid_or_mass_elements + ...
        double(contains(text,"solid") || contains(text," mass"));
end

logs = strings(numel(def.outputs),1);
logsValid = false(numel(def.outputs),1);
originScores = zeros(numel(def.outputs),1);
for index = 1:numel(def.outputs)
    found = find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
        "BlockType","ToWorkspace","VariableName",def.outputs(index).name);
    if numel(found)==1
        logs(index) = string(found{1});
        logsValid(index) = strcmpi(get_param(found{1},"SaveFormat"),"Timeseries") && ...
            strcmpi(get_param(found{1},"MaxDataPoints"),"inf");
        originScores(index) = physical_log_origin(found{1});
    end
end

usedVariables = strings(0,1);
try
    variables = Simulink.findVars(model);
    usedVariables = string({variables.Name}).';
catch
end
publicNames = string({def.public_inputs.name});
bindingFraction = mean(ismember(publicNames,usedVariables));
rootGraph = root_role_graph(model);

hydraulicPower = sqrt( ...
    q_high(counts.pressure_sources,0,1)* ...
    q_high(counts.reservoirs,0,1));
meteringValve = q_high(counts.directional_or_metering_valves,0,1);
doubleActing = q_high(counts.translational_liquid_converters,1,2);
electromechanical = q_high(counts.electromechanical_converters,0,1);
scissor = sqrt( ...
    q_high(counts.multibody_joints,3,8)* ...
    q_high(counts.solid_or_mass_elements,1,4));
feedback = sqrt( ...
    q_high(counts.translational_motion_sensors,0,1)* ...
    q_high(counts.controller_like,0,1)* ...
    rootGraph.feedback);
physicalOrigins = bottleneck_mean(originScores,ones(size(originScores)));

audit = struct( ...
    "counts",counts, ...
    "output_log_paths",logs, ...
    "output_logs_valid",logsValid, ...
    "output_origin_scores",originScores, ...
    "used_public_inputs",usedVariables(ismember(usedVariables,publicNames)), ...
    "hydraulic_power_path",hydraulicPower, ...
    "metering_valve",meteringValve, ...
    "double_acting_cylinder",doubleActing, ...
    "electromechanical_valve_drive",electromechanical, ...
    "scissor_load",scissor, ...
    "measured_feedback",feedback, ...
    "physical_output_origins",physicalOrigins, ...
    "public_input_bindings",bindingFraction, ...
    "root_role_graph",rootGraph, ...
    "root_physical_path_fraction",rootGraph.path_fraction, ...
    "core_path_qualified", ...
        all(logsValid) && hydraulicPower>=.5 && meteringValve>=.5 && ...
        doubleActing>=.5 && electromechanical>=.5 && scissor>=.5 && ...
        feedback>=.5 && physicalOrigins>=.5 && ...
        bindingFraction>=.99 && rootGraph.path_fraction>=.65);
end

function values = nominal_values(def)
values = struct;
for index = 1:numel(def.public_inputs)
    values.(def.public_inputs(index).name) = def.public_inputs(index).nominal;
end
end

function row = empty_row
row = struct( ...
    "id","","valid",false, ...
    "pressure_step_fraction",NaN, ...
    "pressure_step_time_s",NaN, ...
    "initial_extension_error_mm",Inf, ...
    "cycle_tracking_rmse_mm",Inf, ...
    "cycle_peak_tracking_error_mm",Inf, ...
    "upper_hold_error_mm",Inf, ...
    "return_error_mm",Inf, ...
    "command_motion_fraction",0, ...
    "upper_overshoot_mm",Inf, ...
    "tail_oscillation_mm",Inf, ...
    "tail_velocity_rms_mm_per_s",Inf, ...
    "peak_velocity_mm_per_s",Inf, ...
    "peak_spool_mm",Inf, ...
    "tail_spool_rms_mm",Inf, ...
    "pressure_extension_excursion_mm",Inf, ...
    "pressure_spool_response_peak_mm",Inf, ...
    "pressure_tracking_rmse_mm",Inf, ...
    "pressure_peak_tracking_error_mm",Inf, ...
    "pressure_recovery_s",Inf, ...
    "error","");
end

function pair = paired_causality(drop,control)
pair = struct( ...
    "pressure_extension_difference_mm", ...
        abs(drop.pressure_extension_excursion_mm- ...
        control.pressure_extension_excursion_mm), ...
    "pressure_spool_difference_mm", ...
        abs(drop.pressure_spool_response_peak_mm- ...
        control.pressure_spool_response_peak_mm));
end

function reference = cycle_reference(time,initial,target,t0,t1,t2,t3)
reference = initial*ones(size(time));
raise = time>=t0 & time<t1;
reference(raise) = initial + (target-initial)* ...
    (time(raise)-t0)/max(t1-t0,eps);
hold = time>=t1 & time<t2;
reference(hold) = target;
lower = time>=t2 & time<t3;
reference(lower) = target + (initial-target)* ...
    (time(lower)-t2)/max(t3-t2,eps);
end

function seconds = recovery_in_window(time,errorSignal,startTime,endTime, ...
    tolerance,dwell)
seconds = Inf;
indices = find(time>=startTime & time<=endTime-dwell);
for cursor = 1:numel(indices)
    startIndex = indices(cursor);
    endIndex = find(time>=time(startIndex)+dwell,1);
    if isempty(endIndex) || time(endIndex)>endTime,continue;end
    if all(errorSignal(startIndex:endIndex)<=tolerance)
        seconds = time(startIndex)-startTime;
        return;
    end
end
end

function validate_timeseries(value,channels,stopTime,name)
assert(isa(value,"timeseries"),"F90_XFLUID04_NOT_TIMESERIES:%s",name);
time = double(value.Time(:));
data = double(value.Data);
assert(~isempty(time) && all(isfinite(time)) && all(isfinite(data),"all"), ...
    "F90_XFLUID04_NONFINITE_OUTPUT:%s",name);
assert(time(1)<=1e-9 && time(end)>=stopTime-1e-6, ...
    "F90_XFLUID04_TIME_COVERAGE:%s",name);
assert(numel(data)==numel(time)*channels, ...
    "F90_XFLUID04_CHANNEL_COUNT:%s",name);
end

function data = scalar_data(value)
data = squeeze(double(value.Data));
data = data(:);
end

function score = physical_log_origin(logBlock)
score = 0;
queue = string(logBlock);
seen = strings(0,1);
for depth = 1:5
    next = strings(0,1);
    for index = 1:numel(queue)
        block = queue(index);
        if any(seen==block),continue;end
        seen(end+1,1) = block; %#ok<AGROW>
        text = lower(identity_text(block));
        if contains(text,"ps-simulink") || ...
                contains(text,"translational motion sensor") || ...
                contains(text,"mechanical.sensors.velocity") || ...
                contains(text,"ideal translational motion sensor")
            score = 1;
            return;
        end
        try
            ports = get_param(block,"PortHandles");
            inputs = [];
            if isfield(ports,"Inport"),inputs = [inputs ports.Inport];end %#ok<AGROW>
            for p = inputs
                line = get_param(p,"Line");
                if line<=0,continue;end
                source = get_param(line,"SrcBlockHandle");
                if source>0
                    next(end+1,1) = string(getfullname(source)); %#ok<AGROW>
                end
            end
        catch
        end
    end
    queue = unique(next);
end
end

function graph = root_role_graph(model)
rootBlocks = find_system(model,"SearchDepth",1,"Type","Block");
rootBlocks = rootBlocks(~strcmp(rootBlocks,model));
roles = struct("supply",strings(0,1),"valve",strings(0,1), ...
    "actuator",strings(0,1),"load",strings(0,1), ...
    "servo",strings(0,1),"controller",strings(0,1), ...
    "sensing",strings(0,1));
for index = 1:numel(rootBlocks)
    root = string(rootBlocks{index});
    descendants = find_system(root,"LookUnderMasks","all", ...
        "FollowLinks","on","Type","Block");
    allText = "";
    for j = 1:numel(descendants)
        allText = allText + " " + lower(identity_text(descendants{j}));
    end
    if (contains(allText,"pressure source (il)") || ...
            contains(allText,"pressure_source") || ...
            contains(allText,"hydraulic pressure source") || ...
            contains(allText,"constant pressure source")) && ...
            (contains(allText,"reservoir (il)") || ...
            contains(allText,"isothermal_liquid.elements.reservoir") || ...
            contains(allText,"hydraulic reservoir") || ...
            contains(allText,"hydraulic reference"))
        roles.supply(end+1,1) = root; %#ok<AGROW>
    end
    if contains(allText,"directional valve") || ...
            contains(allText,"local restriction (il)") || ...
            contains(allText,"local_restriction") || ...
            contains(allText,"variable orifice")
        roles.valve(end+1,1) = root; %#ok<AGROW>
    end
    if count(allText,"translational mechanical converter (il)")>=2 || ...
            count(allText,"translational_converter")>=2 || ...
            contains(allText,"double-acting hydraulic cylinder") || ...
            contains(allText,"double-acting actuator")
        roles.actuator(end+1,1) = root; %#ok<AGROW>
    end
    if count(allText,"revolute joint")>=4 && ...
            contains(allText,"solid")
        roles.load(end+1,1) = root; %#ok<AGROW>
    end
    if contains(allText,"rotational electromechanical converter") || ...
            contains(allText,"rotational_converter")
        roles.servo(end+1,1) = root; %#ok<AGROW>
    end
    if (contains(allText,"operational amplifier") || ...
            contains(allText,"op-amp") || contains(allText,"controller") || ...
            contains(allText,"pid") || contains(allText,"compensator")) && ...
            ~contains(allText,"rotational electromechanical converter")
        roles.controller(end+1,1) = root; %#ok<AGROW>
    end
    if contains(allText,"ps-simulink") && ...
            (contains(allText,"motion") || contains(allText,"sensing"))
        roles.sensing(end+1,1) = root; %#ok<AGROW>
    end
end
edges = struct( ...
    "supply_valve",role_edge(roles.supply,roles.valve), ...
    "valve_actuator",role_edge(roles.valve,roles.actuator), ...
    "actuator_load",role_edge(roles.actuator,roles.load), ...
    "controller_servo",role_edge(roles.controller,roles.servo), ...
    "servo_valve",role_edge(roles.servo,roles.valve), ...
    "actuator_controller",role_edge(roles.actuator,roles.controller), ...
    "actuator_sensing",role_edge(roles.actuator,roles.sensing));
pathValues = double(struct_values(edges));
graph = struct("roles",roles,"edges",edges, ...
    "path_fraction",mean(pathValues), ...
    "feedback",double(edges.actuator_controller));
end

function q = bottleneck_mean(values,weights)
values = min(max(double(values(:)),0),1);
weights = double(weights(:));
weights = weights/sum(weights);
q = sqrt(sum(weights.*values)*min(values));
end

function q = q_high(value,bad,good)
if ~isfinite(value),q=0;return;end
q = clip((value-bad)/(good-bad));
end

function text = identity_text(block)
text = strjoin([ ...
    string(block), ...
    string(safe_param(block,"Name")), ...
    string(safe_param(block,"MaskType")), ...
    string(safe_param(block,"SourceType")), ...
    string(safe_param(block,"ReferenceBlock")), ...
    string(safe_param(block,"SourceFile")), ...
    string(safe_param(block,"ComponentPath"))]," ");
% Simscape display names can embed newlines.  Normalize them before every
% topology/origin classifier so line wrapping cannot change audit results.
text = regexprep(text,"\s+"," ");
end

function tf = role_edge(first,second)
tf = false;
for i = 1:numel(first)
    for j = 1:numel(second)
        if first(i)==second(j),continue;end
        if directly_connected(first(i),second(j))
            tf = true;
            return;
        end
    end
end
end

function values = struct_values(source)
names = fieldnames(source);
values = zeros(numel(names),1);
for index = 1:numel(names)
    values(index) = source.(names{index});
end
end

function q = clip(value)
q = min(max(value,0),1);
end

function value = safe_param(block,parameter)
try
    value = get_param(block,parameter);
catch
    value = "";
end
end

function tf = directly_connected(first,second)
% PortConnectivity reports all blocks sharing a branched Simscape
% connection, including DEST_DEST/DEST_SRC physical-signal branches.  The
% ordinary line SrcBlockHandle/DstBlockHandle view can omit those branch
% endpoints, so use it only as a fallback.
tf = port_connectivity_has(first,second) || ...
    port_connectivity_has(second,first);
if tf,return;end
try
    ports = get_param(first,"PortHandles");
    fields = fieldnames(ports);
    for index = 1:numel(fields)
        handles = ports.(fields{index});
        for port = handles(:).'
            if port<=0,continue;end
            line = get_param(port,"Line");
            if isempty(line) || any(line<=0),continue;end
            for lineHandle = line(:).'
                sources = get_param(lineHandle,"SrcBlockHandle");
                destinations = get_param(lineHandle,"DstBlockHandle");
                connected = [sources(:);destinations(:)];
                connected = connected(connected>0);
                if any(string(arrayfun(@getfullname,connected, ...
                        "UniformOutput",false))==second)
                    tf = true;
                    return;
                end
            end
        end
    end
catch
end
end

function tf = port_connectivity_has(first,second)
tf = false;
try
    secondHandle = getSimulinkBlockHandle(second);
    if secondHandle<=0,return;end
    connectivity = get_param(first,"PortConnectivity");
    for index = 1:numel(connectivity)
        sources = connectivity(index).SrcBlock;
        destinations = connectivity(index).DstBlock;
        connected = [sources(:);destinations(:)];
        connected = connected(connected>0);
        if any(connected==secondHandle)
            tf = true;
            return;
        end
    end
catch
end
end
