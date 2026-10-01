function evidence = f90_xaero09_extract_candidate_evidence(modelPath, outputDir)
%F90_XAERO09_EXTRACT_CANDIDATE_EVIDENCE Unified public-output adapter.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
end

[taskRoot, sharedRoot, compatRoot] = localRoots("F90-XAERO-09");
pathBefore = path;
addpath(sharedRoot, compatRoot, "-begin");
cleanup = onCleanup(@() path(pathBefore)); %#ok<NASGU>
official = jsondecode(fileread(simuverity_official_scenarios_path()));

spec = struct;
spec.schema = "simuverity.f90-xaero09-evidence.v1";
spec.task_id = "F90-XAERO-09";
spec.scenarios = official.scenarios;
spec.output_contract = localOutputs;
spec.input_builder = @localInputs;
spec.requested_input_builder = @localRequestedInputs;
spec.stop_time = @(~,~) double(official.simulation.duration_seconds);
spec.evidence_sample_s = double(official.simulation.evidence_grid_step_seconds);
spec.postprocess = @localPostprocess;
spec.static_audit = @localAudit;

evidence = simuverity_run_candidate_evidence(modelPath, outputDir, spec);
evidence.scenarios = localFinalizeScenarios(evidence.scenarios);
evidence.simulate_pass = all([evidence.scenarios.simulation_pass]);
evidence.all_scenarios_valid = all([evidence.scenarios.valid]);
evidence.evidence_complete = evidence.score_inputs_valid;
evidence.runtime_model_unchanged = evidence.binding_preserved;
evidence.scenario_count = numel(evidence.scenarios);
evidence.evidence_path = "evidence.json";
localWriteJson(fullfile(outputDir, "evidence.json"), evidence);
end

function rows = localOutputs
names = ["attitude_state", "phase_plane_state", "rcs_state"];
rows = repmat(struct("name", "", "evidence_name", "", ...
    "width", 6, "interpolation", "linear"), numel(names), 1);
for index = 1:numel(names)
    rows(index).name = names(index);
    rows(index).evidence_name = names(index);
end
rows(3).interpolation = "previous";
rows(3).event_columns = 1:3;
end

function inputs = localInputs(scenario, ~)
inputs = struct("lunar_dap_case_input", rmfield(scenario, "id"));
end

function requested = localRequestedInputs(scenario, ~)
requested = rmfield(scenario, "id");
end

function row = localPostprocess(row, outputs, ~, ~)
attitude = outputs.attitude_state;
phase = outputs.phase_plane_state;
rcs = outputs.rcs_state;
time = outputs.time_s;
tail = time >= 24;
rates = attitude(:,4:6);
relative = atan2(sin(attitude(:,1:3) - attitude(1,1:3)), ...
    cos(attitude(:,1:3) - attitude(1,1:3)));
trackingError = phase(:,4:6);
jets = rcs(:,1:3);
row.metrics = struct( ...
    "initial_rate_norm_rad_s", norm(rates(1,:)), ...
    "tail_rate_rms_rad_s", sqrt(mean(sum(rates(tail,:).^2, 2))), ...
    "tail_tracking_error_rms_rad", ...
        sqrt(mean(sum(trackingError(tail,:).^2, 2))), ...
    "peak_tracking_error_rad", max(vecnorm(trackingError, 2, 2)), ...
    "jet_activity_mean", mean(abs(jets), "all"), ...
    "jet_activity_peak", max(abs(jets), [], "all"), ...
    "jet_switch_count", sum(abs(diff(jets, 1, 1)) > 0.25, "all"), ...
    "final_relative_attitude_rad", relative(end,:), ...
    "final_rate_rad_s", rates(end,:), ...
    "all_finite", all(isfinite([time; attitude(:); phase(:); rcs(:)])));
row.valid = row.output_contract.all_required_pass && numel(time) == 601 && ...
    row.metrics.all_finite;
end

function rows = localFinalizeScenarios(rows)
for index = 1:numel(rows)
    outputs = rows(index).outputs;
    rows(index).time_s = outputs.time_s;
    rows(index).attitude_state = outputs.attitude_state;
    rows(index).phase_plane_state = outputs.phase_plane_state;
    rows(index).rcs_state = outputs.rcs_state;
    rows(index).logs = struct( ...
        "attitude_state", struct("channels", 6, ...
            "samples", numel(outputs.time_s)), ...
        "phase_plane_state", struct("channels", 6, ...
            "samples", numel(outputs.time_s)), ...
        "rcs_state", struct("channels", 6, ...
            "samples", numel(outputs.time_s)));
end
end

function audit = localAudit(model, spec)
structure = simuverity_candidate_structure( ...
    model, string({spec.output_contract.name})');
semantic = structure.semantic_types;
chartCount = localChartCount(model);
plantCount = nnz(contains(semantic, ["6dof", "six-dof", ...
    "rigid body", "state-space", "quaternion"]));
switchCount = nnz(contains(semantic, ["relay", "switch", "stateflow"]));
audit = struct( ...
    "dynamic_block_count", structure.dynamic_block_count, ...
    "executable_chart_count", chartCount, ...
    "plant_mechanism_count", plantCount, ...
    "switching_mechanism_count", switchCount, ...
    "signal_cycle_present", structure.signal_cycle_present, ...
    "connected_public_output_count", structure.connected_output_count, ...
    "core_path_qualified", ...
        structure.connected_output_count == numel(spec.output_contract) && ...
        structure.nontrivial_output_source_count == numel(spec.output_contract) && ...
        structure.dynamic_block_count + chartCount >= 1 && ...
        plantCount + chartCount >= 1 && ...
        switchCount + chartCount >= 1 && structure.signal_cycle_present);
end

function count = localChartCount(model)
count = 0;
try
    root = sfroot;
    charts = root.find("-isa", "Stateflow.EMChart");
    for index = 1:numel(charts)
        pathValue = string(charts(index).Path);
        if pathValue == model || startsWith(pathValue, model + "/")
            count = count + 1;
        end
    end
catch
end
end

function localWriteJson(pathOut, payload)
fid = fopen(pathOut, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAERO09:EvidenceWrite", ...
    "Cannot publish candidate evidence JSON.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(payload, PrettyPrint=true), "char");
fwrite(fid, newline, "char");
end

function [taskRoot, sharedRoot, compatRoot] = localRoots(taskId)
scriptRoot = fileparts(mfilename("fullpath"));
tasksRoot = fileparts(scriptRoot);
sharedRoot = fullfile(tasksRoot, "_shared");
repoRoot = tasksRoot;
for index = 1:3, repoRoot = fileparts(repoRoot); end
compatRoot = fullfile(repoRoot, "scripts", "unified", "public_output");
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
end
