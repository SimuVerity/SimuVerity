function evidence = f90_xmed04_extract_evidence(modelPath, outDir)
%f90_xmed04_extract_evidence Bound outputs and port-level causal graph.
%   SCORING_CORE remains the current owner of simulation and dynamic evidence. COMPATIBILITY
%   replaces structural evidence with an opaque port graph. Public output
%   candidates mirror simuverity_public_output_compatibility precedence: one exact
%   To Workspace container wins over lower-priority logging aliases; exact
%   logsout elements are considered only when no direct container exists.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

taskDir = string(fileparts(mfilename("fullpath")));
root = localProjectRoot;
localRequireBinding(fullfile(taskDir, ...
    "f90_xmed04_extract_evidence_core.m"), ...
    "present");
localRequireBinding(fullfile(root, "scripts", "unified", ...
    "public_output", "simuverity_public_output_compatibility.m"), ...
    "present");

definition = f90_xmed04_definition;
if strlength(modelPath) == 0
    modelPath = string(definition.runner.reference_model);
end
if strlength(outDir) == 0
    generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
    assert(strlength(generationRunId) > 0, "SimuVerity:F90:XMED04:GenerationRunId", ...
        "SIMUVERITY_GENERATION_RUN_ID is required.");
    outDir = fullfile(tempdir, "SimuVerity", "F90-XMED-04", generationRunId);
end
assert(isfile(modelPath), "SimuVerity:F90:XMED04:ModelMissing", ...
    "Model under evaluation is missing: %s", modelPath);
if ~isfolder(outDir), mkdir(outDir); end
evidencePath = fullfile(outDir, "evidence.json");
assert(~isfile(evidencePath), "SimuVerity:F90:XMED04:EvaluationReuse", ...
    "COMPATIBILITY evidence output already exists.");

modelPresenceBefore = localFilePresence(modelPath);
dependencyOutDir = fullfile(outDir, "current_extraction_dependency");
assert(~isfolder(dependencyOutDir), "SimuVerity:F90:XMED04:DependencyOutputReuse", ...
    "The SCORING_CORE dependency output directory already exists.");
mkdir(dependencyOutDir);
evidence = f90_xmed04_extract_evidence_core(modelPath, dependencyOutDir);
dependencyEvidencePath = fullfile(dependencyOutDir, "evidence.json");
retainedDependencyEvidencePath = fullfile(dependencyOutDir, "native_current_evidence.json");
assert(isfile(dependencyEvidencePath) && ~isfile(retainedDependencyEvidencePath), ...
    "SimuVerity:F90:XMED04:DependencyEvidence", ...
    "The SCORING_CORE dependency evidence output is missing or was reused.");
movefile(dependencyEvidencePath, retainedDependencyEvidencePath);
assert(isfile(retainedDependencyEvidencePath) && ~isfile(dependencyEvidencePath), ...
    "SimuVerity:F90:XMED04:DependencyEvidence", ...
    "The SCORING_CORE dependency evidence could not be retained safely.");
audit = localStaticAudit(modelPath, logical(evidence.reference_subject));
modelPresenceAfter = localFilePresence(modelPath);
assert(modelPresenceBefore == modelPresenceAfter && ...
    string(evidence.model_file_presence) == modelPresenceAfter, ...
    "SimuVerity:F90:XMED04:CandidateBinding", ...
    "Simulation and COMPATIBILITY structural evidence do not bind the same model.");

evidence.schema = "simuverity.f90-xmed04-evidence.v1";
evidence.adapter = "xmed04-bound-output-port-graph";
evidence.static_audit = audit;
evidence.model_closed_without_save = ...
    logical(evidence.model_closed_without_save) && ...
    logical(audit.model_closed_without_save);
evidence.reference_binding_preserved = ...
    logical(evidence.reference_binding_preserved) && ...
    modelPresenceAfter == modelPresenceBefore;
evidence.candidate_evidence_ready = true;
evidence.current_evidence_reusable_as = false;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.score_fields_present = false;
evidence.candidate_file_presence_before_current_audit = modelPresenceBefore;
evidence.candidate_file_presence_after_current_audit = modelPresenceAfter;
evidence.candidate_binding_preserved_by_current_audit = true;
evidence.current_simulation_evidence_engine_file_presence = localFilePresence(fullfile( ...
    taskDir, "f90_xmed04_extract_evidence_core.m"));
evidence.public_output_compat_file_presence = localFilePresence(fullfile(root, ...
    "scripts", "unified", "public_output", ...
    "simuverity_public_output_compatibility.m"));
localWriteJson(evidencePath, evidence);
end

function audit = localStaticAudit(modelPath, isReference)
loadedBefore = string(find_system("type", "block_diagram"));
modelHandle = load_system(char(modelPath));
model = string(getfullname(modelHandle));
cleanup = onCleanup(@() localCloseNewModel(model, loadedBefore)); %#ok<NASGU>

nodes = localNodes(model);
edges = localSignalLineEdges(nodes);
edges = localHierarchyEdges(nodes, edges);
edges = localGenericInternalRoutes(nodes, edges);
[edges, exactBusRouteCount] = localExactBusElementRoutes(nodes, edges);
[outputCandidates, collisions] = localPublicOutputCandidates( ...
    model, nodes, isReference);

publicNodes = repmat(struct( ...
    "id", "", "block_type", "", "sf_block_type", "", ...
    "input_ports", strings(0, 1), ...
    "output_ports", strings(0, 1), ...
    "signal_in", 0, "signal_out", 0), numel(nodes), 1);
for index = 1:numel(nodes)
    publicNodes(index) = struct( ...
        "id", nodes(index).id, ...
        "block_type", nodes(index).block_type, ...
        "sf_block_type", nodes(index).sf_block_type, ...
        "input_ports", nodes(index).input_ids, ...
        "output_ports", nodes(index).output_ids, ...
        "signal_in", numel(nodes(index).input_ids), ...
        "signal_out", numel(nodes(index).output_ids));
end

graph = struct( ...
    "schema", "simuverity.f90-xmed04-port-graph.v1", ...
    "nodes", publicNodes, ...
    "edges", {edges}, ...
    "public_output_candidates", outputCandidates, ...
    "unsupported_direct_name_collisions", collisions, ...
    "reference_subject", logical(isReference), ...
    "candidate_display_names_emitted", false, ...
    "candidate_mask_types_emitted", false, ...
    "node_identity", "evaluator_owned_opaque_index", ...
    "port_identity_complete", true, ...
    "topology_basis", ...
        "native signal line endpoints plus explicit internal port routes", ...
    "public_output_resolution", ...
        "simuverity_public_output_compatibility direct-before-logsout precedence", ...
    "candidate_logging_aliases_union_with_direct_outputs", false, ...
    "bus_creator_selector_all_to_all", false, ...
    "bus_routing_mode", "exact_element_routes_or_safe_barrier", ...
    "exact_bus_element_route_count", exactBusRouteCount);

wasLoaded = any(loadedBefore == model);
closedWithoutSave = true;
if ~wasLoaded
    try, close_system(model, 0); catch, end
    closedWithoutSave = ~bdIsLoaded(model);
end
audit = struct( ...
    "schema", "simuverity.f90-xmed04-static-audit.v1", ...
    "port_graph", graph, ...
    "decision_deferred_to_offline_policy", true, ...
    "model_closed_without_save", logical(closedWithoutSave), ...
    "display_name_used_for_role_discovery", false, ...
    "mask_type_used_for_role_discovery", false);
end

function nodes = localNodes(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
blocks = blocks(blocks ~= model);
template = struct( ...
    "id", "", "path", "", "handle", 0, "parent", "", ...
    "block_type", "", "sf_block_type", "", ...
    "input_handles", zeros(0, 1), ...
    "output_handles", zeros(0, 1), ...
    "input_ids", strings(0, 1), ...
    "output_ids", strings(0, 1));
nodes = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    inputs = localPortHandles(block, "Inport");
    outputs = localPortHandles(block, "Outport");
    id = "n" + string(index);
    nodes(index) = struct( ...
        "id", id, "path", block, ...
        "handle", double(get_param(block, "Handle")), ...
        "parent", localGet(block, "Parent"), ...
        "block_type", localGet(block, "BlockType"), ...
        "sf_block_type", localGet(block, "SFBlockType"), ...
        "input_handles", inputs, "output_handles", outputs, ...
        "input_ids", id + ":i" + string((1:numel(inputs)).'), ...
        "output_ids", id + ":o" + string((1:numel(outputs)).'));
end
end

function edges = localSignalLineEdges(nodes)
edges = cell(0, 3);
for sourceNode = 1:numel(nodes)
    for sourceOrdinal = 1:numel(nodes(sourceNode).output_handles)
        sourcePort = nodes(sourceNode).output_handles(sourceOrdinal);
        destinations = localDestinationPorts(sourcePort);
        for destinationPort = reshape(destinations, 1, [])
            destinationNode = localNodeForPort(nodes, destinationPort);
            if destinationNode <= 0, continue, end
            destinationOrdinal = find( ...
                nodes(destinationNode).input_handles == destinationPort, 1);
            if isempty(destinationOrdinal), continue, end
            edges = localAddEdge(edges, ...
                nodes(sourceNode).output_ids(sourceOrdinal), ...
                nodes(destinationNode).input_ids(destinationOrdinal), ...
                "signal_line");
        end
    end
end
end

function edges = localHierarchyEdges(nodes, edges)
for child = 1:numel(nodes)
    blockType = lower(nodes(child).block_type);
    if blockType ~= "inport" && blockType ~= "outport", continue, end
    parent = find(string({nodes.path}) == nodes(child).parent, 1);
    if isempty(parent), continue, end
    portNumber = localNumericBlockParameter(nodes(child).path, "Port");
    if ~isfinite(portNumber) || portNumber < 1, continue, end
    portNumber = floor(portNumber);
    if blockType == "inport" && ...
            portNumber <= numel(nodes(parent).input_ids) && ...
            ~isempty(nodes(child).output_ids)
        edges = localAddEdge(edges, ...
            nodes(parent).input_ids(portNumber), ...
            nodes(child).output_ids(1), "hierarchy_in");
    elseif blockType == "outport" && ...
            portNumber <= numel(nodes(parent).output_ids) && ...
            ~isempty(nodes(child).input_ids)
        edges = localAddEdge(edges, ...
            nodes(child).input_ids(1), ...
            nodes(parent).output_ids(portNumber), "hierarchy_out");
    end
end
end

function edges = localGenericInternalRoutes(nodes, edges)
safeBarriers = ["subsystem", "inport", "outport", "toworkspace", ...
    "terminator", "scope", "goto", "from", ...
    "buscreator", "busselector"];
for index = 1:numel(nodes)
    blockType = lower(nodes(index).block_type);
    if any(blockType == safeBarriers), continue, end
    for input = reshape(nodes(index).input_ids, 1, [])
        for output = reshape(nodes(index).output_ids, 1, [])
            edges = localAddEdge(edges, input, output, "block_transfer");
        end
    end
end
end

function [edges, routeCount] = localExactBusElementRoutes(nodes, edges)
routeCount = 0;
for selector = 1:numel(nodes)
    if lower(nodes(selector).block_type) ~= "busselector" || ...
            numel(nodes(selector).input_handles) ~= 1
        continue
    end
    sourcePorts = localSourcePorts( ...
        nodes(selector).input_handles(1));
    if numel(sourcePorts) ~= 1, continue, end
    creator = localNodeForPort(nodes, sourcePorts(1));
    if creator <= 0 || lower(nodes(creator).block_type) ~= "buscreator"
        continue
    end
    creatorElements = localBusCreatorElements(nodes(creator));
    selectedElements = localParameterList( ...
        nodes(selector).path, "OutputSignals");
    if numel(creatorElements) ~= numel(nodes(creator).input_ids) || ...
            numel(selectedElements) ~= numel(nodes(selector).output_ids) || ...
            any(strlength(creatorElements) == 0) || ...
            any(strlength(selectedElements) == 0) || ...
            numel(unique(creatorElements)) ~= numel(creatorElements) || ...
            numel(unique(selectedElements)) ~= numel(selectedElements)
        continue
    end
    for outputOrdinal = 1:numel(selectedElements)
        inputOrdinal = find(creatorElements == ...
            selectedElements(outputOrdinal));
        if numel(inputOrdinal) ~= 1, continue, end
        edges = localAddEdge(edges, ...
            nodes(creator).input_ids(inputOrdinal), ...
            nodes(selector).output_ids(outputOrdinal), ...
            "bus_element_route");
        routeCount = routeCount + 1;
    end
end
end

function values = localBusCreatorElements(node)
values = localParameterList(node.path, "InputSignalNames");
if numel(values) == numel(node.input_handles) && ...
        all(strlength(values) > 0)
    return
end
values = strings(numel(node.input_handles), 1);
for index = 1:numel(node.input_handles)
    values(index) = localIncomingSignalName(node.input_handles(index));
end
end

function [candidates, collisions] = localPublicOutputCandidates( ...
        model, nodes, isReference)
publicNames = [ ...
    "MealCarbohydrateRate_g_s", ...
    "AbsorbedGlucoseRate_mmol_s", ...
    "TrueGlucose_mg_dL", ...
    "ObservedGlucose_mg_dL", ...
    "InsulinInfusion_mU_min"];
nativeNames = [ ...
    "f90_xmed04_meal_rate", ...
    "f90_xmed04_absorbed_rate", ...
    "f90_xmed04_true_glucose", ...
    "f90_xmed04_observed_glucose", ...
    "f90_xmed04_insulin"];
template = struct( ...
    "container_kind", "", "container_node_id", "", ...
    "anchor_port_id", "");
candidates = struct;
collisions = struct;
for outputIndex = 1:numel(publicNames)
    publicName = publicNames(outputIndex);
    rows = repmat(template, 0, 1);
    if isReference
        loggedName = nativeNames(outputIndex);
        rows = localLoggedCandidates(nodes, loggedName, ...
            "reference_logsout_exact_element", rows);
    else
        for node = 1:numel(nodes)
            if lower(nodes(node).block_type) ~= "toworkspace" || ...
                    localGet(nodes(node).path, "VariableName") ~= publicName || ...
                    numel(nodes(node).input_handles) ~= 1
                continue
            end
            sources = localSourcePorts(nodes(node).input_handles(1));
            if numel(sources) ~= 1, continue, end
            sourceNode = localNodeForPort(nodes, sources(1));
            if sourceNode <= 0, continue, end
            ordinal = find(nodes(sourceNode).output_handles == sources(1), 1);
            if isempty(ordinal), continue, end
            rows(end + 1, 1) = struct( ... %#ok<AGROW>
                "container_kind", "simulation_output_toworkspace", ...
                "container_node_id", nodes(node).id, ...
                "anchor_port_id", nodes(sourceNode).output_ids(ordinal));
        end
        rows = localLoggedCandidates(nodes, publicName, ...
            "logsout_exact_element", rows);
    end
    candidates.(publicName) = rows;
    collisions.(publicName) = localUnsupportedDirectCollisionCount( ...
        model, nodes, publicName, isReference);
end
end

function rows = localLoggedCandidates(nodes, name, kind, rows)
for node = 1:numel(nodes)
    for ordinal = 1:numel(nodes(node).output_handles)
        port = nodes(node).output_handles(ordinal);
        if localOn(localPortGet(port, "DataLogging")) && ...
                localEffectiveLoggingName(port) == string(name)
            rows(end + 1, 1) = struct( ... %#ok<AGROW>
                "container_kind", string(kind), ...
                "container_node_id", nodes(node).id, ...
                "anchor_port_id", nodes(node).output_ids(ordinal));
        end
    end
end
end

function count = localUnsupportedDirectCollisionCount( ...
        model, nodes, outputName, isReference)
count = 0;
if isReference, return, end
for node = 1:numel(nodes)
    if lower(nodes(node).block_type) == "scope" && ...
            localOn(localGet(nodes(node).path, "SaveToWorkspace")) && ...
            localGet(nodes(node).path, "SaveName") == outputName
        count = count + 1;
    end
end
pairs = [ ...
    "SaveOutput", "OutputSaveName"; ...
    "SaveState", "StateSaveName"; ...
    "SaveTime", "TimeSaveName"; ...
    "SaveFinalState", "FinalStateName"; ...
    "DSMLogging", "DSMLoggingName"];
for index = 1:size(pairs, 1)
    if localOn(localGet(model, pairs(index, 1))) && ...
            localGet(model, pairs(index, 2)) == outputName
        count = count + 1;
    end
end
end

function values = localParameterList(block, parameter)
values = strings(0, 1);
try
    raw = get_param(block, parameter);
    if iscell(raw)
        values = string(raw(:));
    else
        text = string(raw);
        if ~isscalar(text), values = text(:);
        elseif strlength(text) > 0, values = split(text, ",");
        end
    end
catch
    return
end
values = arrayfun(@localBusToken, values);
values = reshape(values, [], 1);
end

function value = localBusToken(value)
value = strtrim(string(value));
if startsWith(value, "<") && endsWith(value, ">") && ...
        strlength(value) >= 2
    value = extractBetween(value, 2, strlength(value) - 1);
end
if ismissing(value), value = ""; end
end

function value = localIncomingSignalName(inputPort)
value = "";
try
    line = double(get_param(inputPort, "Line"));
    if isempty(line) || line(1) < 0, return, end
    family = localLineFamily(line(1));
    for item = reshape(family, 1, [])
        candidate = localGet(item, "Name");
        if strlength(candidate) > 0
            value = localBusToken(candidate);
            return
        end
    end
catch
end
end

function value = localEffectiveLoggingName(port)
value = strtrim(localPortGet(port, "DataLoggingName"));
if strlength(value) > 0, return, end
try
    line = double(get_param(port, "Line"));
    if isempty(line) || line(1) < 0, return, end
    family = localLineFamily(line(1));
    for item = reshape(family, 1, [])
        candidate = strtrim(localGet(item, "Name"));
        if strlength(candidate) > 0, value = candidate; return, end
    end
catch
end
end

function destinations = localDestinationPorts(sourcePort)
destinations = zeros(0, 1);
try
    line = double(get_param(sourcePort, "Line"));
    if isempty(line) || line(1) < 0, return, end
    family = localLineFamily(line(1));
    for item = reshape(family, 1, [])
        value = double(get_param(item, "DstPortHandle"));
        destinations = [destinations; value(:)]; %#ok<AGROW>
    end
catch
end
destinations = unique(destinations( ...
    isfinite(destinations) & destinations > 0), "stable");
end

function sources = localSourcePorts(destinationPort)
sources = zeros(0, 1);
try
    line = double(get_param(destinationPort, "Line"));
    if isempty(line) || line(1) < 0, return, end
    family = localLineFamily(line(1));
    for item = reshape(family, 1, [])
        value = double(get_param(item, "SrcPortHandle"));
        sources = [sources; value(:)]; %#ok<AGROW>
    end
catch
end
sources = unique(sources(isfinite(sources) & sources > 0), "stable");
end

function family = localLineFamily(seed)
family = zeros(0, 1);
pending = unique(double(seed(seed > 0)));
while ~isempty(pending)
    current = pending(1);
    pending(1) = [];
    if any(family == current), continue, end
    family(end + 1, 1) = current; %#ok<AGROW>
    relatives = zeros(0, 1);
    for property = ["LineParent", "LineChildren"]
        try
            value = double(get_param(current, property));
            relatives = [relatives; value(:)]; %#ok<AGROW>
        catch
        end
    end
    relatives = relatives(isfinite(relatives) & relatives > 0);
    pending = unique([pending(:); relatives(:)]);
end
end

function edges = localAddEdge(edges, source, target, kind)
source = string(source);
target = string(target);
kind = string(kind);
if strlength(source) == 0 || strlength(target) == 0 || source == target
    return
end
if ~isempty(edges)
    duplicate = string(edges(:, 1)) == source & ...
        string(edges(:, 2)) == target & string(edges(:, 3)) == kind;
    if any(duplicate), return, end
end
edges(end + 1, :) = {char(source), char(target), char(kind)};
end

function handles = localPortHandles(block, field)
handles = zeros(0, 1);
try
    ports = get_param(block, "PortHandles");
    if isfield(ports, field)
        handles = reshape(double(ports.(field)), [], 1);
    end
catch
end
end

function index = localNodeForPort(nodes, port)
index = 0;
try
    parent = get_param(port, "Parent");
    if isnumeric(parent), owner = double(parent);
    else, owner = double(get_param(parent, "Handle"));
    end
    match = find(double([nodes.handle]) == owner, 1);
    if ~isempty(match), index = match; end
catch
end
end

function value = localNumericBlockParameter(block, parameter)
value = nan;
try
    raw = get_param(block, parameter);
    if isnumeric(raw) && isscalar(raw), value = double(raw);
    else, value = str2double(string(raw));
    end
catch
end
end

function value = localGet(object, parameter)
value = "";
try
    value = string(get_param(object, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
    if ismissing(value), value = ""; end
catch
end
end

function value = localPortGet(port, parameter)
value = "";
try
    value = string(get_param(port, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
    if ismissing(value), value = ""; end
catch
end
end

function pass = localOn(value)
pass = any(lower(strtrim(string(value))) == ["on", "true", "1", "yes"]);
end

function localCloseNewModel(model, loadedBefore)
if ~any(loadedBefore == model)
    try, close_system(model, 0); catch, end
end
end

function localRequireBinding(pathValue, expected)
assert(isfile(pathValue) && localFilePresence(pathValue) == lower(string(expected)), ...
    "SimuVerity:F90:XMED04:DependencyBinding", ...
    "A declared COMPATIBILITY dependency is missing or changed.");
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMED04:WriteJson", ...
    "Cannot write COMPATIBILITY evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
