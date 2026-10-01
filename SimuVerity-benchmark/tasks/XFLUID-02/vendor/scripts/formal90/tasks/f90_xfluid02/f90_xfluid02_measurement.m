function receipt = f90_xfluid02_measurement(modelPath, outDir)
%f90_xfluid02_extract_candidate_evidence Dedicated multi-scenario triplex-pump scorer.
% All required scenarios contribute through their worst-condition score.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

repoRoot = fullfile(getenv("SIMUVERITY_TASK_VENDOR_ROOT"));
sourceRoot = fullfile(string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE")), ...
    "Simscape-Triplex-Pump");
addpath(fullfile(repoRoot, "scripts", "xp9"));
addpath(fullfile(repoRoot, "scripts", "formal90", "tasks", "f90_xfluid02"));
def = f90_xfluid02_definition;
if ~isfolder(outDir), mkdir(outDir); end

receipt = struct;
receipt.schema = "simuverity.f90-xfluid02-score.v1";
receipt.task_id = def.id;
receipt.formal_id = def.formal_id;
receipt.model_path = modelPath;
receipt.model_file_presence = "";
receipt.matlab_release = string(version("-release"));
receipt.started_at = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
receipt.platform_valid = false;
receipt.error = "";
receipt.runs = struct([]);
receipt.score = empty_score;

oldDir = pwd;
cleanupDir = onCleanup(@() cd(oldDir)); %#ok<NASGU>
project = [];
try
    assert(isfile(modelPath), "F90_XFLUID02_MODEL_MISSING");
    receipt.model_file_presence = xp9_file_presence_file(modelPath);
    cd(sourceRoot);
    project = openProject(fullfile(sourceRoot, "Triplex_Pump.prj"));
    cleanupProject = onCleanup(@() close_project(project)); %#ok<NASGU>

    load_system(modelPath);
    [~, model] = fileparts(modelPath);
    cleanupModel = onCleanup(@() close_if_loaded(model)); %#ok<NASGU>
    set_param(model, "SimulationCommand", "update");

    static = static_audit(model);
    names = ["nominal", string({def.scenarios.id})];
    values = cell(1, numel(names));
    values{1} = nominal_values(def);
    for k = 1:numel(def.scenarios)
        values{k+1} = def.scenarios(k).values;
    end
    rows = repmat(empty_row, numel(names), 1);
    runRows = repmat(struct("id","","stage","not_run", ...
        "valid",false,"error",""), numel(names), 1);
    for k = 1:numel(names)
        runRows(k).id = names(k);
        try
            rows(k) = run_scenario(model, names(k), values{k}, def);
            runRows(k).stage = "simulated";
            runRows(k).valid = rows(k).valid;
            if ~rows(k).valid
                runRows(k).error = "Timeseries contract or finite-data validation failed";
            end
        catch scenarioError
            runRows(k).stage = "failed";
            runRows(k).error = string(getReport(scenarioError, ...
                "extended", "hyperlinks", "off"));
        end
    end
    receipt.runs = runRows;
    if ~all([rows.valid])
        error("F90_XFLUID02_SCENARIO_INVALID", ...
            "One or more required scenarios are invalid");
    end

    nominal = rows(1);
    A = .45*quality_low(nominal.final_speed_error, .03, .20) + ...
        .20*quality_low(nominal.pressure_error, .05, .20) + ...
        .25*quality_band(nominal.volumetric_efficiency, .72, 1.05, .35, 1.30) + ...
        .10*quality_high(nominal.outlet_flow_mean, 4, 18);
    Q = .25*quality_low(nominal.pressure_ripple, .03, .12) + ...
        .25*quality_low(nominal.flow_ripple, .35, .80) + ...
        .35*quality_low(nominal.plunger_balance, .08, .35) + ...
        .15*quality_low(nominal.reverse_flow_ratio, .02, .15);

    staticMechanism = mean([ ...
        static.three_plungers, static.six_check_valves, ...
        static.finite_fluid_compliance, static.speed_feedback_loop, ...
        static.physical_torque_sensor, static.fault_parameters_in_plant]);
    flowClosure = min([rows.flow_closure_score]);
    powerConsistency = min([rows.power_consistency_score]);
    targetResponse = target_response_score(rows, values);
    M = .45*staticMechanism + .15*flowClosure + ...
        .15*powerConsistency + .25*targetResponse;

    operating = zeros(numel(rows), 1);
    stepScores = zeros(numel(rows), 1);
    for k = 1:numel(rows)
        operating(k) = .45*quality_low(rows(k).final_speed_error, .04, .22) + ...
            .20*quality_low(rows(k).pressure_error, .06, .22) + ...
            .20*quality_band(rows(k).volumetric_efficiency, .68, 1.08, .30, 1.35) + ...
            .15*quality_low(rows(k).plunger_balance, .12, .45);
        stepScores(k) = .60*quality_low(rows(k).final_speed_error, .04, .22) + ...
            .40*quality_low(rows(k).step_response_error, .25, 1.10);
    end
    R = min(operating);

    faultIndex = find(names == "paired_fault", 1);
    controlIndex = find(names == "paired_control", 1);
    pair = paired_fault_score(rows(faultIndex), rows(controlIndex), ...
        values{faultIndex});
    D = .65*min(stepScores) + .35*pair.score;

    weights = def.groups.weights;
    raw = weights.A*A + weights.Q*Q + weights.M*M + ...
        weights.R*R + weights.D*D;
    score = 100*raw;
    % Mechanism and recovery remain explicit M/D dimensions in the
    % geometric aggregation; no post-hoc total-score cap is applied.

    receipt.platform_valid = true;
    receipt.score = struct( ...
        "score_inputs_valid", true, ...
        "diagnostics_valid", true, ...
        "G", true, ...
        "score", score, ...
        "groups", struct("G",1,"A",A,"Q",Q,"M",M,"R",R,"D",D), ...
        "scenario_rows", rows, ...
        "static_audit", static, ...
        "paired_fault_metrics", pair);
catch scorerError
    receipt.error = string(getReport(scorerError, "extended", "hyperlinks", "off"));
end

receipt.finished_at = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
write_json(fullfile(outDir, "receipt.json"), receipt);
end

function row = run_scenario(model, id, values, def)
fields = fieldnames(values);
workspace = get_param(model, "ModelWorkspace");
for k = 1:numel(fields)
    name = fields{k};
    assignin("base", name, values.(name));
    assignin(workspace, name, values.(name));
end
set_param(model, "ReturnWorkspaceOutputs", "on", ...
    "StopTime", num2str(def.sim.stop, "%.15g"));
out = sim(model);
required = string({def.outputs.name});
series = cell(size(required));
valid = true;
for k = 1:numel(required)
    series{k} = out.get(required(k));
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

displacementLPerRev = 3*pi*(.024^2)/4*.030*1000;
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
row.hydraulic_power_w = hydraulicPower;
row.shaft_power_w = shaftPower;
row.power_ratio = powerRatio;
row.power_consistency_score = quality_band(powerRatio, .35, 1.05, .10, 1.35);
end

function result = target_response_score(rows, values)
commands = zeros(numel(rows),1);
speeds = zeros(numel(rows),1);
pressures = zeros(numel(rows),1);
measuredPressure = zeros(numel(rows),1);
for k = 1:numel(rows)
    commands(k) = values{k}.pump_speed_rpm*(1+values{k}.speed_step_fraction);
    speeds(k) = rows(k).shaft_speed_mean;
    pressures(k) = values{k}.output_pressure_bar;
    measuredPressure(k) = rows(k).outlet_pressure_mean;
end
speedCorr = safe_corr(commands, speeds);
pressureCorr = safe_corr(pressures, measuredPressure);
speedSpan = span(speeds)/max(span(commands),1e-9);
result = .40*quality_high(speedCorr,.55,.92) + ...
    .20*quality_band(speedSpan,.45,1.35,.15,1.80) + ...
    .40*quality_high(pressureCorr,.65,.95);
end

function pair = paired_fault_score(fault, control, values)
selected = max(1,min(3,round(values.fault_cylinder)));
controlFlow = max(control.outlet_flow_mean,1e-9);
flowDrop = (control.outlet_flow_mean-fault.outlet_flow_mean)/controlFlow;
selectedDrop = (control.plunger_flow_mean(selected)- ...
    fault.plunger_flow_mean(selected))/ ...
    max(abs(control.plunger_flow_mean(selected)),1e-9);
others = setdiff(1:3, selected);
otherDrop = mean((control.plunger_flow_mean(others)- ...
    fault.plunger_flow_mean(others))./ ...
    max(abs(control.plunger_flow_mean(others)),1e-9));
selectivity = selectedDrop-otherDrop;
effect = .60*quality_high(flowDrop,.015,.10) + ...
    .40*quality_high(selectivity,.015,.12);
continuity = quality_high(fault.outlet_flow_mean/controlFlow,.45,.78);
pair = struct("selected_cylinder",selected, ...
    "outlet_flow_drop_fraction",flowDrop, ...
    "selected_plunger_drop_fraction",selectedDrop, ...
    "other_plunger_drop_fraction",otherDrop, ...
    "selectivity",selectivity, ...
    "fault_continuity_fraction",fault.outlet_flow_mean/controlFlow, ...
    "effect_score",effect,"continuity_score",continuity, ...
    "score",.65*effect+.35*continuity);
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

function value = safe_param(block, name)
try
    value = get_param(block, name);
catch
    value = "";
end
end

function data = vector_data(ts)
data = double(ts.Data);
data = data(:);
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
    "flow_closure_score",0,"hydraulic_power_w",NaN, ...
    "shaft_power_w",NaN,"power_ratio",NaN, ...
    "power_consistency_score",0);
end

function score = empty_score
score = struct("score_inputs_valid",false,"diagnostics_valid",false, ...
    "G",false,"score",0, ...
    "groups",struct("G",0,"A",0,"Q",0,"M",0,"R",0,"D",0), ...
    "scenario_rows",struct([]),"static_audit",struct, ...
    "paired_fault_metrics",struct);
end

function value = safe_corr(a,b)
if numel(unique(a))<2 || numel(unique(b))<2
    value = 0;
    return;
end
c = corrcoef(a,b);
value = max(0,min(1,c(1,2)));
end

function y = quality_low(x, good, bad)
if ~isfinite(x), y=0; return; end
y = clip((bad-x)/(bad-good));
end

function y = quality_high(x, bad, good)
if ~isfinite(x), y=0; return; end
y = clip((x-bad)/(good-bad));
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

function y = clip(x)
y = min(max(x,0),1);
end

function value = span(x)
value = max(x,[],"all")-min(x,[],"all");
end

function close_if_loaded(model)
try
    if bdIsLoaded(model), close_system(model,0); end
catch
end
end

function close_project(project)
try
    if ~isempty(project), close(project); end
catch
end
end

function write_json(path, value)
fid = fopen(path,"w","n","UTF-8");
assert(fid>=0,"F90_XFLUID02_WRITE_FAILED:%s",path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,PrettyPrint=true),"char");
end

