function varargout = f90_xtherm05_measurement_compatibility(helperName, varargin)
%f90_xtherm05_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xtherm05_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["run_scenario", "static_audit", "nominal_values", "empty_row", "paired_flow_metrics", "paired_current_metrics"];
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
    case "paired_flow_metrics"
        if nargout == 0
            paired_flow_metrics(varargin{:});
        else
            [varargout{1:nargout}] = paired_flow_metrics(varargin{:});
        end
    case "paired_current_metrics"
        if nargout == 0
            paired_current_metrics(varargin{:});
        else
            [varargout{1:nargout}] = paired_current_metrics(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xtherm05_measurement_compatibility:UnknownHelper", ...
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
battery = matrix_data(series{1},24);
plate = matrix_data(series{2},24);
deltaT = matrix_data(series{3},1);
deltaP = matrix_data(series{4},1);
current = matrix_data(series{5},1);
voltage = matrix_data(series{6},1);

tb = double(series{1}.Time(:));
tp = double(series{2}.Time(:));
tdt = double(series{3}.Time(:));
tdp = double(series{4}.Time(:));
ti = double(series{5}.Time(:));
tv = double(series{6}.Time(:));
tailStart = def.sim.stop-40;
bTail = tb >= tailStart;
pTail = tp >= tailStart;
dtTail = tdt >= tailStart;
dpTail = tdp >= tailStart;
iTail = ti >= tailStart;
vTail = tv >= tailStart;
pre = ti >= max(10,scenarioValues.charge_step_time_s-35) & ...
    ti <= scenarioValues.charge_step_time_s-5;
post = ti >= min(def.sim.stop-35,scenarioValues.charge_step_time_s+35);
assert(nnz(bTail)>=5 && nnz(pTail)>=5 && nnz(dtTail)>=5 && ...
    nnz(dpTail)>=5 && nnz(pre)>=5 && nnz(post)>=5, ...
    "F90_XTHERM05_METRIC_WINDOWS");

batteryTailMeanByChannel = mean(battery(bTail,:),1);
plateTailMeanByChannel = mean(plate(pTail,:),1);
currentPre = mean(abs(current(pre)));
currentPost = mean(abs(current(post)));
targetPre = scenarioValues.charge_current_A;
targetPost = scenarioValues.charge_current_A* ...
    (1+scenarioValues.charge_step_fraction);
requestedDelta = targetPost-targetPre;
actualDelta = currentPost-currentPre;
if abs(requestedDelta) < 1e-9
    responseError = abs(actualDelta)/max(targetPre,1);
    directionScore = double(abs(actualDelta) <= .03*max(targetPre,1));
else
    responseError = abs(actualDelta-requestedDelta)/abs(requestedDelta);
    directionScore = double(sign(actualDelta)==sign(requestedDelta))* ...
        min(abs(actualDelta)/max(abs(requestedDelta),1e-9),1);
end
settling = settling_after_step(ti,abs(current), ...
    scenarioValues.charge_step_time_s,currentPost,.05*max(abs(currentPost),1));

row = empty_row;
row.id = id;
row.valid = true;
row.initial_temperature_error_K = ...
    max(abs(battery(1,:)-scenarioValues.initial_battery_temperature_K));
row.battery_tail_mean_K = mean(batteryTailMeanByChannel);
row.battery_tail_max_K = max(batteryTailMeanByChannel);
row.battery_tail_min_K = min(batteryTailMeanByChannel);
row.battery_spread_K = max(batteryTailMeanByChannel)- ...
    min(batteryTailMeanByChannel);
row.plate_tail_mean_K = mean(plateTailMeanByChannel);
row.plate_tail_max_K = max(plateTailMeanByChannel);
row.plate_tail_min_K = min(plateTailMeanByChannel);
row.plate_spread_K = max(plateTailMeanByChannel)- ...
    min(plateTailMeanByChannel);
row.battery_tail_drift_K_per_s = linear_slope(tb(bTail), ...
    mean(battery(bTail,:),2));
row.battery_distinct_tail_channels = ...
    distinct_count(batteryTailMeanByChannel,1e-5);
row.plate_distinct_tail_channels = ...
    distinct_count(plateTailMeanByChannel,1e-5);
row.coolant_temperature_rise_K = mean(deltaT(dtTail));
row.coolant_pressure_drop_bar = mean(abs(deltaP(dpTail)));
row.current_pre_A = currentPre;
row.current_post_A = currentPost;
row.current_limit_before_A = targetPre;
row.current_limit_after_A = targetPost;
row.pre_current_utilization = currentPre/max(abs(targetPre),1);
row.post_current_utilization = currentPost/max(abs(targetPost),1);
row.pre_current_error = abs(currentPre-targetPre)/max(abs(targetPre),1);
row.post_current_error = abs(currentPost-targetPost)/max(abs(targetPost),1);
row.current_step_response_error = responseError;
row.current_step_direction_score = directionScore;
row.current_step_settling_s = settling;
row.voltage_tail_V = mean(voltage(vTail));
row.electrical_power_tail_W = mean(abs(current(iTail)))* ...
    mean(abs(voltage(vTail)))*96;
row.error = "";
end

function audit = static_audit(model,def)
blocks = find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "Type","Block");
counts = struct( ...
    "battery_components",0, ...
    "thermal_storage_or_conduction",0, ...
    "thermal_liquid_flow_components",0, ...
    "thermal_liquid_pipes_or_restrictions",0, ...
    "pressure_temperature_sensors",0, ...
    "controlled_current_sources",0, ...
    "electrical_voltage_measurements",0, ...
    "controller_like",0);
for index = 1:numel(blocks)
    text = lower(identity_text(blocks{index}));
    counts.battery_components = counts.battery_components + ...
        double(contains(text,"battery") && ...
        ~contains(text,"to workspace"));
    counts.thermal_storage_or_conduction = ...
        counts.thermal_storage_or_conduction + ...
        double(contains(text,"thermal mass") || ...
        contains(text,"thermal conductor") || ...
        contains(text,"cooling plate"));
    counts.thermal_liquid_flow_components = ...
        counts.thermal_liquid_flow_components + ...
        double(contains(text,"thermal_liquid") || contains(text,"(tl)"));
    counts.thermal_liquid_pipes_or_restrictions = ...
        counts.thermal_liquid_pipes_or_restrictions + ...
        double(contains(text,"pipe (tl)") || ...
        contains(text,"local restriction (tl)") || ...
        contains(text,"thermal_liquid.elements.pipe"));
    counts.pressure_temperature_sensors = ...
        counts.pressure_temperature_sensors + ...
        double((contains(text,"pressure") && contains(text,"temperature") && ...
        contains(text,"sensor")) || ...
        contains(text,"pressure_temperature_sensor"));
    counts.controlled_current_sources = counts.controlled_current_sources + ...
        double(contains(text,"controlled current source") || ...
        contains(text,"controlled_current"));
    counts.electrical_voltage_measurements = ...
        counts.electrical_voltage_measurements + ...
        double(contains(text,"voltage sensor") || ...
        contains(text,"battery voltage"));
    counts.controller_like = counts.controller_like + ...
        double(contains(text,"controller") || contains(text,"control logic"));
end

logs = strings(numel(def.outputs),1);
logsValid = false(numel(def.outputs),1);
for index = 1:numel(def.outputs)
    found = find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
        "BlockType","ToWorkspace","VariableName",def.outputs(index).name);
    if numel(found)==1
        logs(index) = string(found{1});
        logsValid(index) = strcmpi(get_param(found{1},"SaveFormat"),"Timeseries") && ...
            strcmpi(get_param(found{1},"MaxDataPoints"),"inf");
    end
end

usedVariables = strings(0,1);
try
    variables = Simulink.findVars(model);
    usedVariables = string({variables.Name}).';
catch
end
bindingFraction = mean(ismember(string({def.public_inputs.name}),usedVariables));
distributedBattery = q_high(counts.battery_components,4,20);
% A custom finite-capacity plate can contain all 24 partitions inside one
% composite component; spatial independence is separately verified from
% the 24 measured trajectories, so counting 12 visible plate blocks would
% incorrectly reject the exact physical source.
distributedPlate = q_high(counts.thermal_storage_or_conduction,0,2);
thermalLiquidPath = sqrt( ...
    q_high(counts.thermal_liquid_flow_components,4,15)* ...
    q_high(counts.thermal_liquid_pipes_or_restrictions,3,20));
physicalSensing = q_high(counts.pressure_temperature_sensors,0,1);
currentOrigin = upstream_contains(logs(5),["battery"],6);
voltageOrigin = upstream_contains(logs(6),["battery"],6);
outputOrigins = [ ...
    upstream_contains(logs(1),["battery"],6), ...
    upstream_contains(logs(2),["battery","cooling plate"],6), ...
    upstream_contains(logs(3),["ps-simulink"],3), ...
    upstream_contains(logs(4),["ps-simulink"],3), ...
    currentOrigin,voltageOrigin];
voltageSource = immediate_upstream(logs(6));
feedbackConnection = downstream_contains(voltageSource, ...
    ["controller","control logic","cc-cv"],6);
physicalCharging = sqrt( ...
    q_high(counts.controlled_current_sources,0,1)* ...
    q_high(counts.battery_components,1,5)*currentOrigin);
feedbackEvidence = sqrt( ...
    voltageOrigin* ...
    feedbackConnection* ...
    q_high(counts.controller_like,0,1)* ...
    q_high(counts.controlled_current_sources,0,1));
audit = struct( ...
    "counts",counts, ...
    "output_log_paths",logs, ...
    "output_logs_valid",logsValid, ...
    "pack_current_physical_origin",currentOrigin, ...
    "cell_voltage_physical_origin",voltageOrigin, ...
    "output_physical_origins",outputOrigins, ...
    "voltage_feedback_connection",feedbackConnection, ...
    "used_public_inputs",usedVariables(ismember(usedVariables, ...
        string({def.public_inputs.name}))), ...
    "distributed_battery",distributedBattery, ...
    "distributed_plate",distributedPlate, ...
    "thermal_liquid_path",thermalLiquidPath, ...
    "physical_coolant_sensing",physicalSensing, ...
    "physical_charging_path",physicalCharging, ...
    "feedback_evidence",feedbackEvidence, ...
    "public_input_bindings",bindingFraction, ...
    "core_path_qualified", ...
        all(logsValid) && distributedBattery>=.5 && ...
        distributedPlate>=.5 && thermalLiquidPath>=.5 && ...
        physicalSensing>=.5 && physicalCharging>=.5 && ...
        feedbackEvidence>=.5 && all(outputOrigins>=.5) && ...
        bindingFraction>=.85);
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
    "initial_temperature_error_K",Inf, ...
    "battery_tail_mean_K",NaN, ...
    "battery_tail_max_K",NaN, ...
    "battery_tail_min_K",NaN, ...
    "battery_spread_K",Inf, ...
    "plate_tail_mean_K",NaN, ...
    "plate_tail_max_K",NaN, ...
    "plate_tail_min_K",NaN, ...
    "plate_spread_K",Inf, ...
    "battery_tail_drift_K_per_s",Inf, ...
    "battery_distinct_tail_channels",0, ...
    "plate_distinct_tail_channels",0, ...
    "coolant_temperature_rise_K",NaN, ...
    "coolant_pressure_drop_bar",NaN, ...
    "current_pre_A",NaN, ...
    "current_post_A",NaN, ...
    "current_limit_before_A",NaN, ...
    "current_limit_after_A",NaN, ...
    "pre_current_utilization",NaN, ...
    "post_current_utilization",NaN, ...
    "pre_current_error",Inf, ...
    "post_current_error",Inf, ...
    "current_step_response_error",Inf, ...
    "current_step_direction_score",0, ...
    "current_step_settling_s",Inf, ...
    "voltage_tail_V",NaN, ...
    "electrical_power_tail_W",NaN, ...
    "error","");
end

function pair = paired_flow_metrics(low,high)
pair = struct( ...
    "low_pressure_drop_bar",low.coolant_pressure_drop_bar, ...
    "high_pressure_drop_bar",high.coolant_pressure_drop_bar, ...
    "pressure_ratio",high.coolant_pressure_drop_bar/ ...
        max(low.coolant_pressure_drop_bar,1e-12), ...
    "battery_improvement_K",low.battery_tail_mean_K- ...
        high.battery_tail_mean_K, ...
    "plate_improvement_K",low.plate_tail_mean_K- ...
        high.plate_tail_mean_K);
end

function pair = paired_current_metrics(up,control,down)
upRequested = abs(up.current_limit_after_A-control.current_limit_after_A);
downRequested = abs(control.current_limit_after_A-down.current_limit_after_A);
preScale = max(mean([up.current_pre_A,control.current_pre_A, ...
    down.current_pre_A]),1);
pair = struct( ...
    "up_current_separation_A",up.current_post_A-control.current_post_A, ...
    "down_current_separation_A",control.current_post_A-down.current_post_A, ...
    "up_requested_limit_separation_A",upRequested, ...
    "down_requested_limit_separation_A",downRequested, ...
    "up_effect_fraction",(up.current_post_A-control.current_post_A)/ ...
        max(upRequested,1e-9), ...
    "down_effect_fraction",(control.current_post_A-down.current_post_A)/ ...
        max(downRequested,1e-9), ...
    "maximum_pre_pair_relative_difference",max(abs([ ...
        up.current_pre_A-control.current_pre_A, ...
        down.current_pre_A-control.current_pre_A]))/preScale);
end

function validate_timeseries(value,channels,stopTime,name)
assert(isa(value,"timeseries"),"F90_XTHERM05_NOT_TIMESERIES:%s",name);
time = double(value.Time(:));
data = double(value.Data);
assert(~isempty(time) && all(isfinite(time)) && all(isfinite(data),"all"), ...
    "F90_XTHERM05_NONFINITE_OUTPUT:%s",name);
assert(time(1)<=1e-9 && time(end)>=stopTime-1e-6, ...
    "F90_XTHERM05_TIME_COVERAGE:%s",name);
assert(numel(data)==numel(time)*channels, ...
    "F90_XTHERM05_CHANNEL_COUNT:%s",name);
end

function data = matrix_data(value,channels)
time = double(value.Time(:));
data = squeeze(double(value.Data));
if channels==1
    data = data(:);
elseif size(data,1)==numel(time)
    data = reshape(data,numel(time),channels);
elseif size(data,2)==numel(time)
    data = reshape(data,channels,numel(time)).';
else
    data = reshape(data,numel(time),channels);
end
end

function count = distinct_count(values,tolerance)
sorted = sort(values(:));
if isempty(sorted),count=0;return;end
count = 1+sum(diff(sorted)>tolerance);
end

function slope = linear_slope(time,data)
p = polyfit(double(time(:)),double(data(:)),1);
slope = p(1);
end

function seconds = settling_after_step(time,data,stepTime,target,tolerance)
indices = find(time>=stepTime);
seconds = Inf;
for cursor = 1:numel(indices)
    remaining = indices(cursor:end);
    if all(abs(data(remaining)-target)<=tolerance)
        seconds = time(indices(cursor))-stepTime;
        return;
    end
end
end

function score = upstream_contains(logPath,patterns,maxDepth)
score = 0;
if strlength(logPath)==0
    return;
end
try
    handle = getSimulinkBlockHandle(logPath);
catch
    return;
end
if handle<=0,return;end
queue = string(logPath);
seen = strings(0,1);
for depth = 1:maxDepth
    next = strings(0,1);
    for index = 1:numel(queue)
        block = queue(index);
        if any(seen==block),continue;end
        seen(end+1,1) = block; %#ok<AGROW>
        text = lower(identity_text(block));
        if any(contains(text,lower(patterns)))
            score = 1;
            return;
        end
        try
            ports = get_param(block,"PortHandles");
            if ~isfield(ports,"Inport"),continue;end
            for port = ports.Inport(:).'
                line = get_param(port,"Line");
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

function source = immediate_upstream(block)
source = "";
if strlength(block)==0,return;end
try
    ports = get_param(block,"PortHandles");
    if ~isfield(ports,"Inport") || isempty(ports.Inport),return;end
    line = get_param(ports.Inport(1),"Line");
    if line<=0,return;end
    handle = get_param(line,"SrcBlockHandle");
    if handle>0,source = string(getfullname(handle));end
catch
end
end

function score = downstream_contains(source,patterns,maxDepth)
score = 0;
if strlength(source)==0,return;end
queue = string(source);
seen = strings(0,1);
for depth = 1:maxDepth
    next = strings(0,1);
    for index = 1:numel(queue)
        block = queue(index);
        if any(seen==block),continue;end
        seen(end+1,1) = block; %#ok<AGROW>
        if depth>1
            text = lower(identity_text(block));
            if any(contains(text,lower(patterns)))
                score = 1;
                return;
            end
        end
        try
            ports = get_param(block,"PortHandles");
            if ~isfield(ports,"Outport"),continue;end
            for port = ports.Outport(:).'
                line = get_param(port,"Line");
                if line<=0,continue;end
                destinations = get_param(line,"DstBlockHandle");
                destinations = destinations(destinations>0);
                for handle = destinations(:).'
                    next(end+1,1) = string(getfullname(handle)); %#ok<AGROW>
                end
            end
        catch
        end
    end
    queue = unique(next);
end
end

function text = identity_text(block)
text = strjoin([ ...
    string(safe_param(block,"Name")), ...
    string(safe_param(block,"MaskType")), ...
    string(safe_param(block,"SourceType")), ...
    string(safe_param(block,"ReferenceBlock")), ...
    string(safe_param(block,"SourceFile")), ...
    string(safe_param(block,"ComponentPath"))]," ");
end

function q = q_high(value,bad,good)
if ~isfinite(value),q=0;return;end
q = clip((value-bad)/(good-bad));
end

function value = safe_param(block,parameter)
try
    value = get_param(block,parameter);
catch
    value = "";
end
end

function q = clip(value)
q = min(max(value,0),1);
end
