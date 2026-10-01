function receipt = f90_xrobo04_score_model(modelPath, outDir, evaluationMode)
%f90_xrobo04_score_model Evidence extraction with public-grid repair.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
    evaluationMode (1,1) string = "reference"
end
candidateMode = strcmpi(evaluationMode, "candidate");

root = string(getenv("SIMUVERITY_TASK_VENDOR_ROOT"));
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
referenceRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
assert(strlength(modelPath) > 0, "SimuVerity:F90:XROBO04:ModelRequired", ...
    "Public extraction requires an explicit model path.");
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XROBO04:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(outDir) == 0
    outDir = fullfile(tempdir, "SimuVerity", "F90-XROBO-04", generationRunId);
end
assert(~isfolder(outDir), "SimuVerity:F90:XROBO04:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

official = jsondecode(fileread(simuverity_official_scenarios_path()));
cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XROBO04:Isolation");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

addpath(fullfile(root, "scripts", "xp9"));
sourceBindingBefore = lower(string(xp9_file_presence_file(modelPath)));
expectedBinding = "present";
candidateAlias = fullfile(referenceRoot, "mars_rover_terrain.slx");
assert(candidateMode || sourceBindingBefore == expectedBinding, ...
    "SimuVerity:F90:XROBO04:ReferenceBinding", "Direct golden file presence mismatch.");

receipt = struct;
receipt.schema = "simuverity.f90-xrobo04-evidence.v1";
receipt.task_id = "F90-XROBO-04";
receipt.evaluation_subject = lower(string(evaluationMode));
receipt.adapter = ...
    "native_roverbus_ctrlbus_physical_torque_with_unit_normalization";
if candidateMode
    receipt.reference_substantive_modifications = "N/A_FOR_CANDIDATE";
    receipt.reference_substantive_modifications_applicability = ...
        "reference-only; not applicable to a candidate";
else
    receipt.reference_substantive_modifications = 0;
    receipt.reference_substantive_modifications_applicability = ...
        "REFERENCE_ONLY";
end
receipt.extraction_only = true;
receipt.contains_score_decisions = false;
receipt.load_pass = false;
receipt.update_pass = false;
receipt.compile_pass = false;
receipt.nominal_smoke_pass = false;
receipt.static_audit = struct;
receipt.scenarios = struct([]);
receipt.errors = struct;
receipt.started_at = localNow;
receipt.runtime = struct( ...
    "generation_run_id", generationRunId, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", cacheDir, "codegen", codegenDir, ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));

old = pwd;
cleanupDir = onCleanup(@() cd(old)); %#ok<NASGU>
[~, model] = fileparts(modelPath);
project = [];
scenarioArtifacts = repmat(struct("id", "", "time_s", [], ...
    "outputs", struct), numel(official.scenarios), 1);
rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
try
    if candidateMode
        cd(fileparts(modelPath)); addpath(fileparts(modelPath), "-begin");
        load_system(modelPath);
    else
        cd(referenceRoot);
        project = openProject(fullfile(referenceRoot, "Mars_Rover_Terrain.prj"));
        projectCleanup = onCleanup(@() localCloseProject(project)); %#ok<NASGU>
        assert(evalin("base", "exist('rover_path1','var')==1") && ...
        evalin("base", "exist('rover_path2','var')==1") && ...
        evalin("base", "exist('mars_terrain_grid','var')==1") && ...
        evalin("base", "exist('Rover','var')==1"), ...
        "SimuVerity:F90:XROBO04:StartupData", ...
        "Project startup did not create the native parameter workspace.");
        if bdIsLoaded(model)
            loadedModelPath = string(get_param(model, "FileName"));
            assert(localSamePath(loadedModelPath, modelPath) || ...
                localSamePath(loadedModelPath, candidateAlias), ...
                "SimuVerity:F90:XROBO04:ReferenceModelPath", ...
                "Project StartUp loaded a model outside the bound runtime closure.");
            assert(lower(string(xp9_file_presence_file(loadedModelPath))) == expectedBinding, ...
                "SimuVerity:F90:XROBO04:ReferenceBinding", ...
                "Project StartUp loaded a binding-mismatched Mars rover model.");
        else
            load_system(modelPath);
        end
    end
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    receipt.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "StopTime", num2str(double( ...
        official.simulation.maximum_stop_s), "%.15g"));

    if candidateMode
        localApplyCandidateScenario(official.scenarios(1));
    else
        localApplyScenario(model, official.scenarios(1));
    end
    receipt.static_audit = localStructureEvidence(model);
    try
        set_param(model, "SimulationCommand", "update");
        receipt.update_pass = true;
    catch ME
        receipt.errors.update = localError(ME);
    end
    if receipt.update_pass
        compiled = false;
        try
            feval(model, [], [], [], "compile");
            compiled = true;
            receipt.compile_pass = true;
        catch ME
            receipt.errors.compile = localError(ME);
        end
        if compiled
            try, feval(model, [], [], [], "term"); catch, end
        end
    end

    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = localRequestedInputs(scenario);
        scenarioArtifacts(index).id = string(scenario.id);
        if index > 1 && ~rows(1).valid
            rows(index).error = struct( ...
                "identifier", "SimuVerity:F90:XROBO04:NominalFailed", ...
                "message", "Remaining scenarios were not run after nominal failure.");
            continue;
        end
        try
            if candidateMode
                localApplyCandidateScenario(scenario);
            else
                localApplyScenario(model, scenario);
            end
            started = tic;
            simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).wall_seconds = toc(started);
            [time, outputs] = localExtractOutputs(simOut, candidateMode);
            localValidateOutputs(time, outputs);
            rows(index).simulation_pass = true;
            rows(index).valid = true;
            rows(index).time_start_s = time(1);
            rows(index).time_end_s = time(end);
            rows(index).sample_count = numel(time);
            rows(index).summary = localSummary(time, outputs, scenario);
            scenarioArtifacts(index).time_s = time;
            scenarioArtifacts(index).outputs = outputs;
            if index == 1
                receipt.nominal_smoke_pass = ...
                    rows(index).simulation_pass && rows(index).valid;
                localWriteJson(fullfile(outDir, ...
                    "nominal_complete.json"), struct( ...
                    "generation_run_id", generationRunId, ...
                    "wall_seconds", rows(index).wall_seconds, ...
                    "terminal_complete", ...
                    rows(index).summary.mission_terminal_complete, ...
                    "finished_at", localNow));
            end
        catch ME
            rows(index).simulation_pass = false;
            rows(index).valid = false;
            rows(index).error = localError(ME);
        end
    end
    receipt.scenarios = rows;
    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "scenarioArtifacts", "-v7.3");
    receipt.raw_artifact = struct( ...
        "path", string(rawPath), ...
        "file_presence", lower(string(xp9_file_presence_file(rawPath))), ...
        "format", "MAT-v7.3", "variable", "scenarioArtifacts");
catch ME
    receipt.errors.session = localError(ME);
    receipt.scenarios = rows;
end

localCloseModel(model);
localCloseProject(project);
sourceBindingAfter = lower(string(xp9_file_presence_file(modelPath)));
receipt.reference_integrity = struct( ...
    "expected_file_presence", expectedBinding, ...
    "before_file_presence", sourceBindingBefore, ...
    "after_file_presence", sourceBindingAfter, ...
    "unchanged", sourceBindingBefore == sourceBindingAfter && ...
        (candidateMode || sourceBindingAfter == expectedBinding), ...
    "model_saved", false);
receipt.model_closed_without_save = ~bdIsLoaded(model);
receipt.binding_preserved = receipt.reference_integrity.unchanged;
validRows = ~isempty(receipt.scenarios) && ...
    numel(receipt.scenarios) == numel(official.scenarios) && ...
    all([receipt.scenarios.valid]);
receipt.nominal_smoke_pass = ~isempty(receipt.scenarios) && ...
    receipt.scenarios(1).valid;
receipt.score_inputs_valid = receipt.load_pass && receipt.update_pass && ...
    receipt.compile_pass && receipt.nominal_smoke_pass && validRows && ...
    receipt.model_closed_without_save && receipt.binding_preserved;
receipt.diagnostics_valid = receipt.score_inputs_valid;
receipt.evidence_complete = receipt.score_inputs_valid;
receipt.public_grid_orientation_recovery = struct( ...
    "method", "meshgrid_provider_normalization", ...
    "reason", "public contract supplies X/Y/Z as same-size meshgrid matrices", ...
    "normalization", ...
        "supply conventional X/Y meshgrid matrices matching Z Ny-by-Nx before update/simulation", ...
    "candidate_modified", false, ...
    "runtime_model_saved", false, ...
    "public_prompt_modified", false, ...
    "scenarios_modified", false, ...
    "offline_scorer_modified", false);
receipt.finished_at = localNow;
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, receipt);
fprintf("F90_XROBO04_EVIDENCE load=%d update=%d compile=%d valid=%d/%d path=%s\n", ...
    receipt.load_pass, receipt.update_pass, receipt.compile_pass, ...
    sum([receipt.scenarios.valid]), numel(receipt.scenarios), evidencePath);
end

function localApplyScenario(model, scenario)
if double(scenario.path_id) == 1
    evalin("base", "rover_path = rover_path1;");
else
    evalin("base", "rover_path = rover_path2;");
end
mars_terrain_set_z(char(string(scenario.terrain)));

Rover = evalin("base", "Rover");
Rover.Wheel_Surface.Friction.mu_static = ...
    double(scenario.TerrainMuStatic);
Rover.Wheel_Surface.Friction.mu_dynamic = ...
    double(scenario.TerrainMuDynamic);
assignin("base", "Rover", Rover);
Control = evalin("base", "Control");
Control.Drive.TargetSpeed = double(scenario.TargetSpeed_mps);
assignin("base", "Control", Control);

roverPath = evalin("base", "rover_path");
terrain = evalin("base", "mars_terrain_grid");
sample = evalin("base", "sample_position");
assignin("base", "RoverPath_XYZ", ...
    [roverPath.x(:), roverPath.y(:), roverPath.z(:)]);
assignin("base", "TerrainGrid_X_m", double(terrain.xg(:)'));
assignin("base", "TerrainGrid_Y_m", double(terrain.yg(:)'));
assignin("base", "TerrainGrid_Z_m", double(terrain.z_heights));
assignin("base", "SamplePosition_m", double(sample(:)'));
assignin("base", "TargetSpeed_mps", ...
    double(scenario.TargetSpeed_mps));
assignin("base", "TerrainMuStatic", ...
    double(scenario.TerrainMuStatic));
assignin("base", "TerrainMuDynamic", ...
    double(scenario.TerrainMuDynamic));

powertrain = model + "/Rover/Chassis/Powertrain";
set_param(powertrain, "popup_powertrain", "Electrical");
set_param(model + "/Rover", "AttributesFormatString", ...
    get_param(powertrain, "LabelModeActiveChoice"));
end

function [time, outputs] = localExtractOutputs(simOut, candidateMode)
if candidateMode
    names=["rover_state","drive_wheel_state","steer_state","arm_joint_state", ...
        "end_effector_position","sample_mission_state","chassis_motor_state","chassis_energy"];
    widths=[7,12,8,12,3,6,30,3]; outputs=struct; time=[];
    for index=1:numel(names)
        value=simuverity_public_output_compatibility( ...
            simOut,names(index),widths(index),AllowBaseWorkspace=true);
        raw=squeeze(double(value.Data));if isvector(raw),raw=raw(:);end
        if size(raw,1)~=numel(value.Time)&&size(raw,2)==numel(value.Time),raw=raw';end
        assert(size(raw,2)==widths(index)&&all(isfinite(raw),"all"));
        if isempty(time),time=double(value.Time(:));rawAligned=raw;else
            rawAligned=interp1(double(value.Time(:)),raw,time,"linear","extrap");
        end
        outputs.(char(names(index)))=rawAligned;
    end
    return;
end
logsout = localGetLogsout(simOut);
rover = logsout.get("RoverBus").Values;
ctrl = logsout.get("CtrlBus").Values;
assert(~isempty(rover) && ~isempty(ctrl), ...
    "SimuVerity:F90:XROBO04:NativeBuses", ...
    "Native RoverBus or CtrlBus is missing.");

nativeTime = double(rover.Body.xyz.Time(:));
assert(numel(nativeTime) >= 2 && all(diff(nativeTime) > 0), ...
    "SimuVerity:F90:XROBO04:NativeTime");
count = max(2, ceil((nativeTime(end)-nativeTime(1))/0.25)+1);
time = linspace(nativeTime(1), nativeTime(end), count)';

xyz = localTs(rover.Body.xyz, time);
rpy = localTs(rover.Body.rpy, time);
speed = localTs(rover.Body.v, time);
outputs.rover_state = [xyz(:,1:3), rpy(:,1:3), speed(:,1)];

wheelNames = ["L1","L2","L3","R1","R2","R3"];
wheelW = localBusGroup(rover.Chassis.Wheels.Drive.w, ...
    wheelNames, time);
wheelTrq = localBusGroup(rover.Chassis.Wheels.Drive.trq, ...
    wheelNames, time);
outputs.drive_wheel_state = [wheelW, wheelTrq];

steerNames = ["L1","L3","R1","R3"];
steerAngle = deg2rad(localBusGroup( ...
    rover.Chassis.Wheels.Steer.q, steerNames, time));
steerApplied = localBusGroup(rover.Chassis.Wheels.Steer.trq, ...
    steerNames, time);
outputs.steer_state = [steerAngle, steerApplied];

jointNames = ["q1","q2","q3","q4","q5","q6"];
q = localBusGroup(rover.Arm.q, jointNames, time);
qCmd = localBusGroup(ctrl.Arm.qCmd, jointNames, time);
outputs.arm_joint_state = deg2rad([q, qCmd]);
outputs.end_effector_position = localTs(rover.Arm.EExyz, time);

sampleLocation = localTs(ctrl.Arm.Sample.Location, time);
hold = localTs(ctrl.Arm.Sample.Hold, time);
stored = localTs(ctrl.Arm.Sample.Stored, time);
mode = localTs(ctrl.Arm.Mode, time);
outputs.sample_mission_state = [sampleLocation(:,1:3), ...
    hold(:,1), stored(:,1), mode(:,1)];

driveW = localBusGroup(rover.Chassis.Powertrain.Drive.w, ...
    wheelNames, time);
steerW = localBusGroup(rover.Chassis.Powertrain.Steer.w, ...
    steerNames, time);
driveI = localBusGroup(rover.Chassis.Powertrain.Drive.i, ...
    wheelNames, time);
steerI = localBusGroup(rover.Chassis.Powertrain.Steer.i, ...
    steerNames, time);
driveMotorTrq = localBusGroup(rover.Chassis.Powertrain.Drive.trq, ...
    wheelNames, time);
steerMotorTrq = localBusGroup(rover.Chassis.Powertrain.Steer.trq, ...
    steerNames, time);
outputs.chassis_motor_state = [driveW, steerW, ...
    driveMotorTrq, steerMotorTrq, driveI, steerI];
drivePower = sum(driveW .* driveMotorTrq, 2);
steerPower = sum(steerW .* steerMotorTrq, 2);
energy = cumtrapz(time, max(drivePower + steerPower, 0)) / 3600;
outputs.chassis_energy = [drivePower, steerPower, energy];
end

function localApplyCandidateScenario(scenario)
t=(0:1:300)'; angle=linspace(0,2*pi,numel(t))';
radius=4+double(scenario.path_id);
path=[radius*cos(angle),radius*sin(angle),zeros(size(angle))];
x=linspace(-6,6,49);y=x;[X,Y]=meshgrid(x,y);
if strcmpi(string(scenario.terrain),"flat"),Z=zeros(size(X));else,Z=0.08*sin(X).*cos(Y);end
assignin("base","RoverPath_XYZ",path);
assert(numel(x) == size(Z,2) && numel(y) == size(Z,1), ...
    "SimuVerity:F90:XROBO04:PublicGridShape");
[gridX,gridY]=meshgrid(reshape(x,1,[]),reshape(y,[],1));
assignin("base","TerrainGrid_X_m",gridX);
assignin("base","TerrainGrid_Y_m",gridY);
assignin("base","TerrainGrid_Z_m",Z);assignin("base","SamplePosition_m",path(end,:));
assignin("base","TargetSpeed_mps",double(scenario.TargetSpeed_mps));
assignin("base","TerrainMuStatic",double(scenario.TerrainMuStatic));
assignin("base","TerrainMuDynamic",double(scenario.TerrainMuDynamic));
end

function audit=localStructureEvidence(~)
audit=struct( ...
    "schema","simuverity.f90-xrobo04-structure-evidence.v1", ...
    "semantic_block_names_used_for_score",false, ...
    "block_path_names_used_for_score",false, ...
    "mechanism_assessment", ...
        "offline waveform behavior and causal official input-output interventions", ...
    "weak_mechanism_clears_qualification",false);
end

function logsout = localGetLogsout(simOut)
logsout = [];
for name = ["logsout_mars_rover_terrain", "logsout"]
    try
        candidate = simOut.get(char(name));
        if isa(candidate, "Simulink.SimulationData.Dataset")
            logsout = candidate;
            break;
        end
    catch
    end
end
if isempty(logsout)
    for name = ["logsout_mars_rover_terrain", "logsout"]
        try
            candidate = evalin("base", name);
            if isa(candidate, "Simulink.SimulationData.Dataset")
                logsout = candidate;
                break;
            end
        catch
        end
    end
end
assert(~isempty(logsout), "SimuVerity:F90:XROBO04:LogsoutMissing");
end

function data = localBusGroup(bus, names, time)
data = zeros(numel(time), numel(names));
for index = 1:numel(names)
    data(:,index) = localTs(bus.(char(names(index))), time);
end
end

function data = localTs(ts, time)
assert(isa(ts, "timeseries"), "SimuVerity:F90:XROBO04:Timeseries");
sourceTime = double(ts.Time(:));
raw = squeeze(double(ts.Data));
if isvector(raw)
    raw = raw(:);
elseif size(raw,1) ~= numel(sourceTime)
    if size(raw,2) == numel(sourceTime)
        raw = raw';
    else
        raw = reshape(raw, [], numel(sourceTime))';
    end
end
[sourceTime, uniqueIndex] = unique(sourceTime, "stable");
raw = raw(uniqueIndex,:);
assert(numel(sourceTime) >= 2 && all(diff(sourceTime) > 0), ...
    "SimuVerity:F90:XROBO04:TimeseriesTime");
data = interp1(sourceTime, raw, time, "linear", "extrap");
assert(all(isfinite(data), "all"), ...
    "SimuVerity:F90:XROBO04:TimeseriesFinite");
end

function localValidateOutputs(time, outputs)
assert(numel(time) >= 20 && time(1) <= 1e-6 && ...
    time(end) > 100, "SimuVerity:F90:XROBO04:MissionHorizon", ...
    "The mission evidence is too short.");
expected = struct("rover_state",7, "drive_wheel_state",12, ...
    "steer_state",8, "arm_joint_state",12, ...
    "end_effector_position",3, "sample_mission_state",6, ...
    "chassis_motor_state",30, "chassis_energy",3);
names = string(fieldnames(expected));
for index = 1:numel(names)
    value = double(outputs.(names(index)));
    assert(size(value,1) == numel(time) && ...
        size(value,2) == expected.(names(index)) && ...
        all(isfinite(value), "all"), ...
        "SimuVerity:F90:XROBO04:OutputContract", ...
        "Output %s violates its finite channel contract.", names(index));
end
end

function summary = localSummary(time, outputs, scenario)
rover = outputs.rover_state;
wheel = outputs.drive_wheel_state;
arm = outputs.arm_joint_state;
mission = outputs.sample_mission_state;
path = evalin("base", "RoverPath_XYZ");
pathError = localPathError(rover(:,1:2), path(:,1:2));
driveActive = time >= 5 & mission(:,6) < 0.5;
driveIndices = find(driveActive);
% A prematurely asserted mission phase is poor behavior, not missing
% evidence.  Keep it scoreable by using the complete post-start interval
% when the declared drive-phase mask supplies too few samples.
if numel(driveIndices) < 20
    driveActive = time >= 5;
    driveIndices = find(driveActive);
end
if numel(driveIndices) < 20
    driveActive = true(size(time));
    driveIndices = find(driveActive);
end
tailCount = min(20, numel(driveIndices));
driveTail = driveIndices(end-tailCount+1:end);
speedError = rover(:,7) - double(scenario.TargetSpeed_mps);
bodySpeed = max(abs(rover(:,7)), 0.02);
slip = (wheel(:,1:6) * 0.215 - rover(:,7)) ./ bodySpeed;
attitude = max(abs(rover(:,4:5)), [], 2);
armError = arm(:,1:6) - arm(:,7:12);
energy = outputs.chassis_energy(:,3);
summary = struct( ...
    "mission_terminal_complete", mission(end,5) > 0.5, ...
    "pickup_latched", max(mission(:,4)) > 0.5, ...
    "stored_latched", max(mission(:,5)) > 0.5, ...
    "path_rmse_m", sqrt(mean(pathError(driveActive).^2)), ...
    "path_p95_m", prctile(pathError(driveActive), 95), ...
    "path_tail_mean_m", mean(pathError(driveTail)), ...
    "speed_mean_mps", mean(rover(driveActive,7)), ...
    "speed_rmse_mps", sqrt(mean(speedError(driveActive).^2)), ...
    "speed_tail_error_mps", abs(mean(speedError(driveTail))), ...
    "max_abs_roll_pitch_rad", max(attitude), ...
    "p95_abs_roll_pitch_rad", prctile(attitude,95), ...
    "wheel_slip_rms", sqrt(mean(slip(driveActive,:).^2, "all")), ...
    "wheel_slip_p95_abs", ...
        prctile(abs(slip(driveActive,:)),95,"all"), ...
    "wheel_torque_peak_Nm", max(abs(wheel(:,7:12)),[],"all"), ...
    "arm_joint_rmse_rad", sqrt(mean(armError.^2,"all")), ...
    "arm_joint_peak_error_rad", max(abs(armError),[],"all"), ...
    "minimum_ee_sample_distance_m", ...
        min(vecnorm(outputs.end_effector_position - ...
        mission(:,1:3), 2, 2)), ...
    "final_energy_Wh", energy(end), ...
    "distance_travelled_m", sum(vecnorm(diff(rover(:,1:3)),2,2)), ...
    "final_xy_m", rover(end,1:2), ...
    "drive_phase_sample_count", numel(driveIndices), ...
    "drive_phase_end_s", time(driveIndices(end)), ...
    "simulation_end_s", time(end));
end

function error = localPathError(xy, path)
error = zeros(size(xy,1),1);
for index = 1:size(xy,1)
    error(index) = min(vecnorm(path - xy(index,:),2,2));
end
end

function out = localRequestedInputs(scenario)
out = struct("path_id", double(scenario.path_id), ...
    "terrain", string(scenario.terrain), ...
    "TargetSpeed_mps", double(scenario.TargetSpeed_mps), ...
    "TerrainMuStatic", double(scenario.TerrainMuStatic), ...
    "TerrainMuDynamic", double(scenario.TerrainMuDynamic));
end

function row = localEmptyScenario
row = struct("id", "", "class", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, "valid", false, ...
    "wall_seconds", NaN, "time_start_s", NaN, ...
    "time_end_s", NaN, "sample_count", 0, ...
    "summary", struct, "error", struct);
end

function localCloseModel(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function localCloseProject(project)
try
    if ~isempty(project), close(project); end
catch
end
end

function same = localSamePath(leftPath, rightPath)
leftCanonical = string(java.io.File(char(leftPath)).getCanonicalPath());
rightCanonical = string(java.io.File(char(rightPath)).getCanonicalPath());
if ispc
    same = strcmpi(leftCanonical, rightCanonical);
else
    same = leftCanonical == rightCanonical;
end
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function out = localError(ME)
out = struct("identifier", string(ME.identifier), ...
    "message", string(ME.message), ...
    "report", string(getReport(ME, "extended", ...
    "hyperlinks", "off")));
end

function localWriteJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XROBO04:WriteJson");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end
