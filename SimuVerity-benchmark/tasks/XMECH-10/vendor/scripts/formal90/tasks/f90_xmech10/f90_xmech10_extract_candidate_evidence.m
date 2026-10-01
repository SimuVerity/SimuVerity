function evidence = f90_xmech10_extract_candidate_evidence( ...
        candidatePath, outDir)
%f90_xmech10_extract_candidate_evidence Candidate file-bound evidence extraction.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end
[taskRoot, sharedRoot] = localRoots("F90-XMECH-10");
addpath(sharedRoot, "-begin");
cleanup = onCleanup(@() rmpath(sharedRoot)); %#ok<NASGU>

publicPath = fullfile(taskRoot, "public_spec.json");
expectedContractId = "f90-xmech10-public-contract";
expectedPresence = "present";
actualPresence = lower(string(localFilePresence(publicPath)));
assert(actualPresence == expectedPresence, "SimuVerity:F90:XMECH10:PublicContractBinding", ...
    "XMECH-10 public contract file binding does not match the declared identity.");
public = jsondecode(fileread(publicPath));
assert(string(public.public_contract_id) == expectedContractId, ...
    "SimuVerity:F90:XMECH10:PublicContractIdentity", ...
    "XMECH-10 public contract identity does not match the declared identity.");
official = jsondecode(fileread(simuverity_official_scenarios_path()));
localValidateNominalFirst(official, public);

spec = struct( ...
    "schema", "simuverity.f90-xmech10-evidence.v1", ...
    "task_id", "F90-XMECH-10", ...
    "scenarios", official.scenarios, ...
    "output_contract", localOutputs, ...
    "input_builder", @localInputs, ...
    "requested_input_builder", @localInputs, ...
    "stop_time", @(~,~) double(official.simulation.stop_s), ...
    "postprocess", @localPostprocess, ...
    "static_audit", @localAudit, ...
    "finalize_evidence", @localFinalize, ...
    "evidence_sample_s", double(official.simulation.evidence_sample_s), ...
    "public_contract_id", expectedContractId, ...
    "public_contract_file_presence", expectedPresence);
evidence = simuverity_run_candidate_evidence(candidatePath, outDir, spec);
end

function localValidateNominalFirst(official, public)
assert(double(official.simulation.start_s) == 0.0 && ...
    double(official.simulation.stop_s) == 20.0, ...
    "SimuVerity:F90:XMECH10:EvaluationWindow", ...
    "The current evaluator must retain the public 0--20 s window.");
window = double(public.evaluation_window_s(:));
assert(isequal(window, [0.0; 20.0]), ...
    "SimuVerity:F90:XMECH10:PublicWindow", ...
    "The current public contract must declare the 0--20 s window.");
nominal = official.scenarios(1);
assert(string(nominal.id) == "nominal_transfer", ...
    "SimuVerity:F90:XMECH10:NominalFirst", ...
    "The nominal scenario must be first so inputs precede initial compile.");
names = ["SupplyVoltage_V", "PayloadMass_kg", ...
    "JointFrictionScale", "SequenceDelayScale"];
for name = names
    expected = double(public.public_inputs.(name).nominal);
    actual = double(nominal.(name));
    assert(actual == expected, "SimuVerity:F90:XMECH10:NominalInput", ...
        "First-scenario %s must match the public nominal.", name);
end
end

function rows = localOutputs
rows = localRows(["joint_command", "joint_position", "motor_current", ...
    "joint_effort", "payload_pose", "sensor_state"], [7 7 7 7 3 4]);
rows(6).interpolation = "previous";
end

function inputs = localInputs(scenario, ~)
inputs = rmfield(scenario, "id");
end

function row = localPostprocess(row, ~, ~, ~)
row.metrics = struct( ...
    "candidate_public_derivations", ...
    "offline_only_from_payload_pose_sensor_state_and_finger_channels", ...
    "nonpublic_belt_command_used", false);
row.valid = row.output_contract.all_required_pass;
end

function evidence = localFinalize(evidence, spec)
evidence.public_contract_id = spec.public_contract_id;
evidence.public_contract_file_presence = spec.public_contract_file_presence;
evidence.public_contract_binding = struct( ...
    "first_scenario_nominal_validated_before_runner", true, ...
    "runner_installs_first_scenario_before_initial_update_compile", true, ...
    "evaluation_window_s", [0.0 20.0], ...
    "payload_pose_frame", "world_xyz_z_up_m", ...
    "nonpublic_belt_command_used", false);
end

function audit = localAudit(model, spec)
audit = struct( ...
    "port_graph", localPortGraph(model), ...
    "public_output_count", numel(spec.output_contract), ...
    "structure_decision_deferred_to_offline_policy", true, ...
    "display_names_used_for_capability_classification", false, ...
    "canvas_coordinates_used", false);
end

function graph = localPortGraph(model)
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
blocks = blocks(blocks ~= model);
handles = zeros(numel(blocks), 1);
nodes = repmat(struct("id", "", "capabilities", strings(0,1)), ...
    numel(blocks), 1);
for index = 1:numel(blocks)
    handles(index) = double(get_param(blocks(index), "Handle"));
    nodes(index).id = "n" + string(index);
    nodes(index).capabilities = localCapabilities(blocks(index));
end

edges = repmat(struct("from", "", "to", "", "kind", ""), 0, 1);
for index = 1:numel(blocks)
    try
        ports = get_param(blocks(index), "PortHandles");
        for port = reshape(ports.Outport, 1, [])
            line = get_param(port, "Line");
            if isempty(line) || any(double(line) < 0), continue, end
            destinations = double(reshape( ...
                get_param(line, "DstBlockHandle"), [], 1));
            for destination = reshape(destinations, 1, [])
                target = find(handles == destination, 1);
                if ~isempty(target)
                    edges = localAddEdge(edges, index, target, "signal");
                end
            end
        end
    catch
    end
end

lineHandles = find_system(model, "FindAll", "on", ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "line");
for line = reshape(lineHandles, 1, [])
    try
        if ~strcmpi(string(get_param(line, "LineType")), "connection")
            continue
        end
        ports = [double(get_param(line, "SrcPortHandle")); ...
            reshape(double(get_param(line, "DstPortHandle")), [], 1)];
        ports = ports(isfinite(ports) & ports > 0);
        owners = zeros(0, 1);
        for port = reshape(ports, 1, [])
            parent = get_param(port, "Parent");
            if isnumeric(parent)
                ownerHandle = double(parent);
            else
                ownerHandle = double(get_param(parent, "Handle"));
            end
            owner = find(handles == ownerHandle, 1);
            if ~isempty(owner), owners(end+1, 1) = owner; end %#ok<AGROW>
        end
        owners = unique(owners);
        for leftIndex = 1:numel(owners)
            for rightIndex = leftIndex + 1:numel(owners)
                edges = localAddEdge(edges, owners(leftIndex), ...
                    owners(rightIndex), "physical");
            end
        end
    catch
    end
end

graph = struct( ...
    "schema", "simuverity.f90-xmech10-port-graph.v1", ...
    "node_identity", "opaque_index_not_display_name", ...
    "capability_sources", ...
        "BlockType_SourceBlock_ReferenceBlock_MaskType_and_real_ports", ...
    "nodes", nodes, ...
    "edges", edges);
end

function edges = localAddEdge(edges, left, right, kind)
if left == right, return, end
row = struct("from", "n" + string(left), ...
    "to", "n" + string(right), "kind", string(kind));
if ~isempty(edges)
    duplicate = arrayfun(@(existing) ...
        string(existing.from) == row.from && ...
        string(existing.to) == row.to && ...
        string(existing.kind) == row.kind, edges);
    if any(duplicate), return, end
end
edges(end+1, 1) = row;
end

function capabilities = localCapabilities(block)
descriptor = lower(strjoin([ ...
    localGet(block, "BlockType"), ...
    localGet(block, "SourceBlock"), ...
    localGet(block, "ReferenceBlock"), ...
    localGet(block, "MaskType")], " "));
physical = localHasPhysicalPorts(block);
capabilities = strings(0, 1);
if physical && localAny(descriptor, ...
        ["dc voltage source", "battery", "dc source"])
    capabilities(end+1, 1) = "dc_source";
end
if physical && localAny(descriptor, ["h-bridge", "h bridge"])
    capabilities(end+1, 1) = "hbridge";
end
if physical && ~contains(descriptor, "joint actuator") && ...
        localAny(descriptor, ...
        ["dc motor", "electromechanical converter", "motor"])
    capabilities(end+1, 1) = "motor";
end
if physical && localAny(descriptor, ...
        ["gear", "transmission", "belt drive"])
    capabilities(end+1, 1) = "transmission";
end
if physical && localAny(descriptor, ...
        ["revolute joint", "revolute primitive"])
    capabilities(end+1, 1) = "joint";
end
if physical && localAny(descriptor, ["prismatic joint", "prismatic primitive"])
    capabilities(end+1, 1) = "finger_joint";
    capabilities(end+1, 1) = "gripper_body";
end
if localAny(descriptor, ...
        ["motion sensor", "joint sensor", "transform sensor", "sensor"])
    capabilities(end+1, 1) = "sensor";
end
if localAny(descriptor, ...
        ["pid controller", "stateflow", "controller", "control logic"])
    capabilities(end+1, 1) = "controller";
end
if physical && localAny(descriptor, ...
        ["friction", "rotational damper", "translational damper"])
    capabilities(end+1, 1) = "friction";
end
if physical && localAny(descriptor, ...
        ["electrical load", "current source", "resistor", "motor constant"])
    capabilities(end+1, 1) = "electrical_load";
end
if physical && localAny(descriptor, ...
        ["spatial contact force", "contact force", "penalty contact"])
    capabilities(end+1, 1) = "compliant_contact";
end
if physical && localAny(descriptor, ...
        ["6-dof joint", "6 dof joint", "six-dof joint"])
    capabilities(end+1, 1) = "free_payload";
end
capabilities = unique(capabilities, "stable");
end

function present = localAny(value, patterns)
present = any(contains(value, patterns));
end

function present = localHasPhysicalPorts(block)
present = false;
try
    ports = get_param(block, "PortHandles");
    present = ~isempty(ports.LConn) || ~isempty(ports.RConn);
catch
end
end

function value = localGet(block, parameter)
value = "";
try, value = string(get_param(block, parameter)); catch, end
end

function rows = localRows(names, widths)
rows = repmat(struct("name", "", "evidence_name", "", "width", 0, ...
    "interpolation", "linear"), numel(names), 1);
for index = 1:numel(names)
    rows(index).name = names(index);
    rows(index).evidence_name = names(index);
    rows(index).width = widths(index);
end
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end

function [taskRoot, sharedRoot] = localRoots(taskId)
scriptRoot = fileparts(mfilename("fullpath"));
tasksRoot = fileparts(scriptRoot);
sharedRoot = fullfile(tasksRoot, "_shared");
repoRoot = tasksRoot;
for index = 1:3, repoRoot = fileparts(repoRoot); end
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
end
