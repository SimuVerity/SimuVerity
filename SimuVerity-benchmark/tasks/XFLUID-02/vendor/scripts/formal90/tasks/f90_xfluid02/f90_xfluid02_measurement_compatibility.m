function varargout = f90_xfluid02_measurement_compatibility(helperName, varargin)
%f90_xfluid02_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xfluid02_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["run_scenario", "static_audit", "nominal_values", "empty_row"];
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
    otherwise
        error("SimuVerity:f90_xfluid02_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function row = run_scenario(model, id, values, def, isReference)
if nargin < 5,isReference=true;end
fields = fieldnames(values);
workspace = get_param(model, "ModelWorkspace");
for k = 1:numel(fields)
    name = fields{k};
    assignin("base", name, values.(name));
    if isReference,assignin(workspace, name, values.(name));end
end
set_param(model, "ReturnWorkspaceOutputs", "on", ...
    "StopTime", num2str(def.sim.stop, "%.15g"));
out = sim(model);
required = string({def.outputs.name});
series = cell(size(required));
valid = true;
for k = 1:numel(required)
    series{k} = simuverity_public_output_compatibility( ...
        out,required(k),def.outputs(k).channels, ...
        AllowBaseWorkspace=true);
    valid = valid && isa(series{k}, "timeseries");
    if valid
        time = double(series{k}.Time(:));
        data = double(series{k}.Data);
        valid = valid && ~isempty(time) && size(data,1) == numel(time) && ...
            all(isfinite(time)) && all(isfinite(data), "all") && ...
            time(1) <= 1e-9 && time(end) >= def.sim.stop-1e-6;
    end
end
assert(valid, "F90_XFLUID02_OUTPUT_CONTRACT");

speed = vector_data(series{1});
torque = vector_data(series{2});
pIn = vector_data(series{3});
qIn = vector_data(series{4}); %#ok<NASGU>
pOut = vector_data(series{5});
qOut = vector_data(series{6});
plunger = [vector_data(series{7}), vector_data(series{8}), ...
    vector_data(series{9})];
t = double(series{1}.Time(:));
tail = t >= def.sim.stop-.22;
pre = t >= max(.15, values.speed_step_time-.20) & ...
    t <= values.speed_step_time-.035;
assert(nnz(tail) >= 10 && nnz(pre) >= 10, "F90_XFLUID02_WINDOWS");

speedTail = mean(speed(tail));
torqueTail = mean(abs(torque(tail)));
pumpDisplacementLPerRev = 3*pi*(.024^2)/4*.030*1000;
flowUnitScaleToLMin = 1;
if ~isReference
    theoreticalCandidate = max(abs(speedTail)*pumpDisplacementLPerRev,1e-9);
    rawCandidate = max(abs(mean(qOut(tail))),1e-18);
    candidateScales = [1,60000];
    scaleError = abs(log((rawCandidate*candidateScales)/theoreticalCandidate));
    [~,scaleIndex] = min(scaleError);
    flowUnitScaleToLMin = candidateScales(scaleIndex);
    qIn = qIn*flowUnitScaleToLMin; %#ok<NASGU>
    qOut = qOut*flowUnitScaleToLMin;
    plunger = plunger*flowUnitScaleToLMin;
end
pInTail = mean(pIn(tail));
pOutTail = mean(pOut(tail));
qOutTail = mean(qOut(tail));
plungerMean = mean(plunger(tail,:), 1);
commandFinal = values.pump_speed_rpm*(1+values.speed_step_fraction);
speedPre = mean(speed(pre));
requestedDelta = values.pump_speed_rpm*values.speed_step_fraction;
actualDelta = speedTail-speedPre;
if abs(requestedDelta) < 1e-9
    stepResponseError = 0;
else
    stepResponseError = abs(actualDelta-requestedDelta)/abs(requestedDelta);
end

displacementLPerRev = pumpDisplacementLPerRev;
theoreticalFlow = max(abs(speedTail)*displacementLPerRev, 1e-9);
volumetricEfficiency = qOutTail/theoreticalFlow;
pressureDelta = pOutTail-pInTail;
hydraulicPower = pressureDelta*1e5*qOutTail/60000;
shaftPower = mean(abs(torque(tail).*speed(tail))*2*pi/60);
powerRatio = hydraulicPower/max(shaftPower, 1e-9);
flowClosureError = abs(qOutTail-sum(plungerMean))/max(abs(qOutTail),1e-9);

row = empty_row;
row.id = id;
row.valid = true;
row.command_final_rpm = commandFinal;
row.shaft_speed_mean = speedTail;
row.final_speed_error = abs(speedTail-commandFinal)/max(abs(commandFinal),1);
row.step_response_error = stepResponseError;
row.shaft_torque_mean_abs = torqueTail;
row.inlet_pressure_mean = pInTail;
row.outlet_pressure_mean = pOutTail;
row.pressure_error = abs(pOutTail-values.output_pressure_bar)/ ...
    max(abs(values.output_pressure_bar),1);
row.outlet_flow_mean = qOutTail;
row.volumetric_efficiency = volumetricEfficiency;
row.pressure_ripple = span(pOut(tail))/max(abs(pOutTail),1e-9);
row.flow_ripple = span(qOut(tail))/max(abs(qOutTail),1e-9);
row.plunger_flow_mean = plungerMean;
row.plunger_balance = span(plungerMean)/max(abs(mean(plungerMean)),1e-9);
row.reverse_flow_ratio = abs(min(0,min(qOut(tail))))/max(abs(qOutTail),1e-9);
row.flow_closure_error = flowClosureError;
row.flow_closure_score = quality_low(flowClosureError, .03, .15);
row.flow_unit_scale_to_L_min = flowUnitScaleToLMin;
row.flow_unit_interpretation = local_flow_unit(flowUnitScaleToLMin);
row.hydraulic_power_w = hydraulicPower;
row.shaft_power_w = shaftPower;
row.power_ratio = powerRatio;
row.power_consistency_score = quality_band(powerRatio, .35, 1.05, .10, 1.35);
end

function value=local_flow_unit(scale)
if scale==60000,value="m^3/s";else,value="L/min";end
end

function audit = static_audit(model)
blocks = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", ...
    "Type", "Block");
plungers = 0;
checkValves = 0;
compliance = 0;
motionSensors = 0;
torqueSensors = 0;
controllerEvidence = false;
faultEvidence = 0;
for k = 1:numel(blocks)
    name = safe_param(blocks{k}, "Name");
    mask = safe_param(blocks{k}, "MaskType");
    reference = safe_param(blocks{k}, "ReferenceBlock");
    text = lower(string(blocks{k})+" "+string(name)+" "+ ...
        string(mask)+" "+string(reference));
    if contains(text,"hydraulic plunger") || ...
            (contains(text,"plunger") && string(mask)~="")
        plungers = plungers+1;
    end
    if contains(text,"check valve (il)")
        checkValves = checkValves+1;
    end
    if contains(text,"constant volume") || contains(text,"pipe (il)")
        compliance = compliance+1;
    end
    if contains(text,"rotational motion sensor")
        motionSensors = motionSensors+1;
    end
    if contains(text,"torque sensor")
        torqueSensors = torqueSensors+1;
    end
    if contains(text,"speed controller") || ...
            (contains(text,"controller") && contains(text,"speed"))
        controllerEvidence = true;
    end
    try
        leak = string(get_param(blocks{k},"leak_cyl_area"));
        blockage = string(get_param(blocks{k},"block_in_factor"));
        if contains(leak,"seal_leak_fraction") && ...
                contains(blockage,"inlet_area_factor") && ...
                contains(leak+blockage,"fault_cylinder")
            faultEvidence = faultEvidence+1;
        end
    catch
    end
end
audit = struct( ...
    "plunger_like_count",plungers, ...
    "check_valve_count",checkValves, ...
    "compliance_or_pipe_count",compliance, ...
    "motion_sensor_count",motionSensors, ...
    "torque_sensor_count",torqueSensors, ...
    "fault_parameterized_plungers",faultEvidence, ...
    "three_plungers",double(plungers>=3), ...
    "six_check_valves",double(checkValves>=6), ...
    "finite_fluid_compliance",double(compliance>=3), ...
    "speed_feedback_loop",double(controllerEvidence && motionSensors>=1), ...
    "physical_torque_sensor",double(torqueSensors>=1), ...
    "fault_parameters_in_plant",double(faultEvidence>=3));
end

function values = nominal_values(def)
values = struct;
for k = 1:numel(def.public_inputs)
    values.(def.public_inputs(k).name) = def.public_inputs(k).nominal;
end
end

function row = empty_row
row = struct("id","","valid",false, ...
    "command_final_rpm",NaN,"shaft_speed_mean",NaN, ...
    "final_speed_error",Inf,"step_response_error",Inf, ...
    "shaft_torque_mean_abs",NaN,"inlet_pressure_mean",NaN, ...
    "outlet_pressure_mean",NaN,"pressure_error",Inf, ...
    "outlet_flow_mean",NaN,"volumetric_efficiency",NaN, ...
    "pressure_ripple",Inf,"flow_ripple",Inf, ...
    "plunger_flow_mean",[NaN NaN NaN],"plunger_balance",Inf, ...
    "reverse_flow_ratio",Inf,"flow_closure_error",Inf, ...
    "flow_closure_score",0,"flow_unit_scale_to_L_min",1, ...
    "flow_unit_interpretation","","hydraulic_power_w",NaN, ...
    "shaft_power_w",NaN,"power_ratio",NaN, ...
    "power_consistency_score",0);
end

function data = vector_data(ts)
data = double(ts.Data);
data = data(:);
end

function y = quality_low(x, good, bad)
if ~isfinite(x), y=0; return; end
y = clip((bad-x)/(bad-good));
end

function y = quality_band(x, lowGood, highGood, lowBad, highBad)
if ~isfinite(x), y=0; return; end
if x>=lowGood && x<=highGood
    y=1;
elseif x<lowGood
    y=quality_high(x,lowBad,lowGood);
else
    y=quality_low(x,highGood,highBad);
end
end

function value = span(x)
value = max(x,[],"all")-min(x,[],"all");
end

function value = safe_param(block, name)
try
    value = get_param(block, name);
catch
    value = "";
end
end

function y = clip(x)
y = min(max(x,0),1);
end

function y = quality_high(x, bad, good)
if ~isfinite(x), y=0; return; end
y = clip((x-bad)/(good-bad));
end
