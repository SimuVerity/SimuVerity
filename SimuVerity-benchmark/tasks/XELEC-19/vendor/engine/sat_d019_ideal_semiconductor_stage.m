function [ok,evidence,reason] = ...
        sat_d019_ideal_semiconductor_stage(modelOrFacts,base)
%SAT_D019_IDEAL_SEMICONDUCTOR_STAGE Exact D019 compatibility proof.
% Acceptance never uses candidate block names.  It requires exact linked
% MathWorks ReferenceBlock/ComponentPath identities, native conserving nets,
% a complete three-phase-by-three-rail switch matrix, connected gate drives,
% and the trusted physical Vout measurement already required by the output
% contract.  A struct input is a narrow test seam for the pure fact validator.

if nargin < 2 || isempty(base), base = struct(); end
if isstruct(modelOrFacts)
    facts = modelOrFacts;
else
    modelName = char(string(modelOrFacts));
    assert(bdIsLoaded(modelName),"SimuVerity:D019SemiconductorStage:ModelNotLoaded", ...
        "Model must be loaded before D019 compatibility inspection.");
    facts = collect_facts(modelName,base);
end
[ok,evidence,reason] = validate_facts(facts);
end

function facts = collect_facts(modelName,base)
switchRef = "ee_lib/semiconductors & converters/ideal semiconductor switch";
switchComponent = "ee.semiconductors.ideal.semiconductor_switch";
resistorRef = "fl_lib/electrical/electrical elements/resistor";
resistorComponent = "foundation.electrical.elements.resistor";
sourceRef = "fl_lib/electrical/electrical sources/dc voltage source";
sourceComponent = "foundation.electrical.sources.dc_voltage";
sensorRef = "fl_lib/electrical/electrical sensors/voltage sensor";
sensorComponent = "foundation.electrical.sensors.voltage";
converterRef = "nesl_utility/simulink-ps converter";

blocks = find_system(modelName,"LookUnderMasks","on", ...
    "FollowLinks","on","Type","Block");
allPhysicalHandles = physical_port_handles(blocks);
[netByLine,netStats] = sat_native_physical_line_nets( ...
    modelName,allPhysicalHandles);

switches = strings(0,1); switchTerms = zeros(0,2); switchGates = zeros(0,1);
switchRefExact = false(0,1); switchComponentExact = false(0,1);
loads = strings(0,1); loadTerms = zeros(0,2); loadRefExact = false(0,1);
loadComponentExact = false(0,1); loadParameterNames = strings(0,1);
loadUsesPload = false(0,1);
sources = strings(0,1); sourceTerms = zeros(0,2); sourceRefExact = false(0,1);
sourceComponentExact = false(0,1);
sensorBlocks = strings(0,1); sensorTerms = zeros(0,2);
sensorRefExact = false(0,1); sensorComponentExact = false(0,1);
controlledGateNets = zeros(0,1); gateConverterBlocks = strings(0,1);

for i = 1:numel(blocks)
    block = blocks{i};
    reference = normtext(getp(block,"ReferenceBlock"));
    component = normtext(getp(block,"ComponentPath"));
    if reference == switchRef && component == switchComponent
        electrical = field_nets(block,"RConn",netByLine);
        gate = field_nets(block,"LConn",netByLine);
        if numel(electrical) == 2 && numel(gate) == 1
            switches(end+1,1) = string(block); %#ok<AGROW>
            switchTerms(end+1,:) = electrical; %#ok<AGROW>
            switchGates(end+1,1) = gate; %#ok<AGROW>
            switchRefExact(end+1,1) = true; %#ok<AGROW>
            switchComponentExact(end+1,1) = true; %#ok<AGROW>
        end
    elseif reference == resistorRef && component == resistorComponent
        expression = string(getp(block,"R"));
        if contains_identifier(expression,"P_load")
            terminals = [field_nets(block,"LConn",netByLine), ...
                field_nets(block,"RConn",netByLine)];
            if numel(terminals) == 2
                loads(end+1,1) = string(block); %#ok<AGROW>
                loadTerms(end+1,:) = terminals; %#ok<AGROW>
                loadRefExact(end+1,1) = true; %#ok<AGROW>
                loadComponentExact(end+1,1) = true; %#ok<AGROW>
                loadParameterNames(end+1,1) = "R"; %#ok<AGROW>
                loadUsesPload(end+1,1) = true; %#ok<AGROW>
            end
        end
    elseif reference == sourceRef && component == sourceComponent
        terminals = [field_nets(block,"LConn",netByLine), ...
            field_nets(block,"RConn",netByLine)];
        if numel(terminals) == 2
            sources(end+1,1) = string(block); %#ok<AGROW>
            sourceTerms(end+1,:) = terminals; %#ok<AGROW>
            sourceRefExact(end+1,1) = true; %#ok<AGROW>
            sourceComponentExact(end+1,1) = true; %#ok<AGROW>
        end
    elseif reference == sensorRef && component == sensorComponent
        left = field_nets(block,"LConn",netByLine);
        right = field_nets(block,"RConn",netByLine);
        % The exact foundation Voltage Sensor has electrical p on LConn1,
        % physical-signal V on RConn1, and electrical n on RConn2.
        if numel(left) == 1 && numel(right) == 2
            terminals = [left,right(2)];
            sensorBlocks(end+1,1) = string(block); %#ok<AGROW>
            sensorTerms(end+1,:) = terminals; %#ok<AGROW>
            sensorRefExact(end+1,1) = true; %#ok<AGROW>
            sensorComponentExact(end+1,1) = true; %#ok<AGROW>
        end
    elseif reference == converterRef
        physical = field_nets(block,"RConn",netByLine);
        if numel(physical) == 1 && signal_input_driven(block)
            controlledGateNets(end+1,1) = physical; %#ok<AGROW>
            gateConverterBlocks(end+1,1) = string(block); %#ok<AGROW>
        end
    end
end

[voutReportOk,traceSensorBlocks,traceIdentityOk] = ...
    trusted_vout_trace(base,sensorBlocks,sensorRef);
keep = ismember(sensorBlocks,traceSensorBlocks);
facts = struct( ...
    "universal_bridge_absent",structure_report_ok(base,"no_universal_bridge"), ...
    "switch_blocks",switches, ...
    "switch_reference_exact",switchRefExact, ...
    "switch_component_exact",switchComponentExact, ...
    "switch_terminal_nets",switchTerms, ...
    "switch_gate_nets",switchGates, ...
    "controlled_gate_nets",controlledGateNets, ...
    "gate_converter_blocks",gateConverterBlocks, ...
    "load_blocks",loads, ...
    "load_reference_exact",loadRefExact, ...
    "load_component_exact",loadComponentExact, ...
    "load_parameter_names",loadParameterNames, ...
    "load_uses_p_load",loadUsesPload, ...
    "load_terminal_nets",loadTerms, ...
    "dc_source_blocks",sources, ...
    "dc_source_reference_exact",sourceRefExact, ...
    "dc_source_component_exact",sourceComponentExact, ...
    "dc_source_terminal_nets",sourceTerms, ...
    "vout_report_ok",voutReportOk, ...
    "vout_trace_identity_ok",traceIdentityOk, ...
    "vout_sensor_blocks",sensorBlocks(keep), ...
    "vout_sensor_reference_exact",sensorRefExact(keep), ...
    "vout_sensor_component_exact",sensorComponentExact(keep), ...
    "vout_sensor_terminal_nets",sensorTerms(keep,:), ...
    "native_net_stats",netStats);
end

function [ok,evidence,reason] = validate_facts(facts)
ok = false; reason = "UNINITIALIZED"; evidence = empty_evidence();
if ~getbool(facts,"universal_bridge_absent",false)
    reason = "UNIVERSAL_BRIDGE_FORBIDDEN"; return;
end

switchTerms = getmatrix(facts,"switch_terminal_nets",2);
switchGates = getvector(facts,"switch_gate_nets");
switchCount = size(switchTerms,1);
if switchCount ~= 9 || numel(switchGates) ~= 9
    reason = "TRUSTED_IDEAL_SEMICONDUCTOR_SWITCH_COUNT_NOT_NINE"; return;
end
if ~all_exact(facts,"switch_reference_exact",9) || ...
        ~all_exact(facts,"switch_component_exact",9)
    reason = "UNTRUSTED_IDEAL_SEMICONDUCTOR_SWITCH_IDENTITY"; return;
end
if any(~isfinite(switchTerms),"all") || ...
        any(switchTerms(:,1) == switchTerms(:,2))
    reason = "SWITCH_ELECTRICAL_TERMINAL_NET_INVALID"; return;
end
controlled = getvector(facts,"controlled_gate_nets");
if numel(unique(switchGates)) ~= 9 || any(~isfinite(switchGates))
    reason = "SWITCH_GATE_NETS_NOT_DISTINCT"; return;
end
gateCounts = arrayfun(@(x)sum(controlled == x),switchGates);
if any(gateCounts ~= 1)
    reason = "SWITCH_GATE_NOT_DRIVEN_BY_TRUSTED_SIMULINK_PS_CONVERTER"; return;
end

loadTerms = getmatrix(facts,"load_terminal_nets",2);
if size(loadTerms,1) ~= 3 || ...
        ~all_exact(facts,"load_reference_exact",3) || ...
        ~all_exact(facts,"load_component_exact",3)
    reason = "TRUSTED_P_LOAD_RESISTOR_COUNT_NOT_THREE"; return;
end
parameterNames = lower(string(getfield_default( ...
    facts,"load_parameter_names",strings(0,1))));
usesPload = logical(getfield_default(facts,"load_uses_p_load",false(0,1)));
if numel(parameterNames) ~= 3 || any(parameterNames ~= "r") || ...
        numel(usesPload) ~= 3 || ~all(usesPload)
    reason = "P_LOAD_NOT_BOUND_THROUGH_EXACT_SIMSCOPE_RESISTOR_R"; return;
end
if any(~isfinite(loadTerms),"all") || any(loadTerms(:,1) == loadTerms(:,2))
    reason = "P_LOAD_RESISTOR_TERMINAL_NET_INVALID"; return;
end

sourceTerms = getmatrix(facts,"dc_source_terminal_nets",2);
sourceCount = size(sourceTerms,1);
if sourceCount < 1 || ...
        ~all_exact(facts,"dc_source_reference_exact",sourceCount) || ...
        ~all_exact(facts,"dc_source_component_exact",sourceCount)
    reason = "TRUSTED_DC_VOLTAGE_SOURCE_MISSING"; return;
end

commonCandidates = common_load_nets(loadTerms);
topologies = struct('midpoint',{},'phases',{},'rails',{}, ...
    'matrix',{},'source_index',{});
for common = commonCandidates(:)'
    phases = zeros(1,3);
    for i = 1:3
        phases(i) = loadTerms(i,loadTerms(i,:) ~= common);
    end
    if numel(unique(phases)) ~= 3, continue; end
    for s = 1:sourceCount
        rails = [sourceTerms(s,1),common,sourceTerms(s,2)];
        if numel(unique(rails)) ~= 3 || any(ismember(phases,rails)), continue; end
        [matrix,validBranches] = phase_rail_matrix(switchTerms,phases,rails);
        if validBranches && all(matrix(:) == 1)
            topologies(end+1) = struct( ... %#ok<AGROW>
                'midpoint',common,'phases',phases,'rails',rails, ...
                'matrix',matrix,'source_index',s);
        end
    end
end
if isempty(topologies)
    reason = "INCOMPLETE_THREE_PHASE_BY_THREE_RAIL_SWITCH_MATRIX"; return;
elseif numel(topologies) ~= 1
    reason = "AMBIGUOUS_THREE_PHASE_BY_THREE_RAIL_SWITCH_MATRIX"; return;
end
topology = topologies(1);

sensorTerms = getmatrix(facts,"vout_sensor_terminal_nets",2);
sensorCount = size(sensorTerms,1);
if ~getbool(facts,"vout_report_ok",false) || ...
        ~getbool(facts,"vout_trace_identity_ok",false) || sensorCount < 1 || ...
        ~all_exact(facts,"vout_sensor_reference_exact",sensorCount) || ...
        ~all_exact(facts,"vout_sensor_component_exact",sensorCount)
    reason = "TRUSTED_PHYSICAL_VOUT_MEASUREMENT_MISSING"; return;
end
sensorMatch = false(sensorCount,1);
for i = 1:sensorCount
    pair = sensorTerms(i,:);
    sensorMatch(i) = any(pair == topology.midpoint) && ...
        any(ismember(pair,topology.phases)) && ...
        numel(unique(pair)) == 2;
end
if sum(sensorMatch) ~= 1
    reason = "VOUT_SENSOR_NOT_ONE_PHASE_TO_MIDPOINT"; return;
end

ok = true; reason = "OK";
sourceBlocks = string(getfield_default(facts,"dc_source_blocks",strings(0,1)));
loadBlocks = string(getfield_default(facts,"load_blocks",strings(0,1)));
switchBlocks = string(getfield_default(facts,"switch_blocks",strings(0,1)));
sensorBlocks = string(getfield_default(facts,"vout_sensor_blocks",strings(0,1)));
converterBlocks = string(getfield_default( ...
    facts,"gate_converter_blocks",strings(0,1)));
sourceBlock = "";
if numel(sourceBlocks) >= topology.source_index
    sourceBlock = sourceBlocks(topology.source_index);
end
measurementBlock = "";
matched = find(sensorMatch,1);
if numel(sensorBlocks) >= matched, measurementBlock = sensorBlocks(matched); end
evidence = struct( ...
    "trusted_switch_count",switchCount, ...
    "trusted_switch_blocks",switchBlocks, ...
    "controlled_gate_count",sum(gateCounts == 1), ...
    "gate_converter_blocks",converterBlocks, ...
    "phase_count",3,"rail_count",3, ...
    "phase_rail_branch_matrix",topology.matrix, ...
    "phase_nets",topology.phases, ...
    "rail_nets",topology.rails, ...
    "midpoint_net",topology.midpoint, ...
    "dc_source_block",sourceBlock, ...
    "p_load_resistor_blocks",loadBlocks, ...
    "vout_measurement_block",measurementBlock, ...
    "dc_source_to_switch_to_load_path",true, ...
    "vout_phase_to_midpoint",true, ...
    "native_net_stats",getfield_default(facts,"native_net_stats",struct()));
end

function [matrix,valid] = phase_rail_matrix(switchTerms,phases,rails)
matrix = zeros(3,3); valid = true;
for i = 1:size(switchTerms,1)
    pair = switchTerms(i,:);
    phaseHits = find(ismember(phases,pair));
    railHits = find(ismember(rails,pair));
    if numel(phaseHits) ~= 1 || numel(railHits) ~= 1
        valid = false; return;
    end
    matrix(phaseHits,railHits) = matrix(phaseHits,railHits) + 1;
end
end

function values = common_load_nets(loadTerms)
values = unique(loadTerms(:)); keep = false(size(values));
for i = 1:numel(values)
    keep(i) = all(sum(loadTerms == values(i),2) == 1);
end
values = values(keep);
end

function handles = physical_port_handles(blocks)
handles = zeros(0,1);
for i = 1:numel(blocks)
    try, ports = get_param(blocks{i},"PortHandles"); catch, continue; end
    fields = fieldnames(ports);
    for f = 1:numel(fields)
        values = double(ports.(fields{f})(:));
        for h = values(:)'
            try, physical = strcmpi(get_param(h,"PortType"),"connection");
            catch, physical = false; end
            if physical, handles(end+1,1) = h; end %#ok<AGROW>
        end
    end
end
handles = unique(handles);
end

function nets = field_nets(block,field,netByLine)
nets = zeros(0,1);
try, ports = get_param(block,"PortHandles"); catch, return; end
if ~isfield(ports,field), return; end
handles = double(ports.(field)(:));
for i = 1:numel(handles)
    line = -1; try, line = double(get_param(handles(i),"Line")); catch, end
    key = sprintf('%.15g',line);
    if line <= 0 || ~isKey(netByLine,key), nets(end+1,1) = NaN; %#ok<AGROW>
    else, nets(end+1,1) = netByLine(key); %#ok<AGROW>
    end
end
nets = nets(:)';
end

function yes = signal_input_driven(block)
yes = false;
try, ports = get_param(block,"PortHandles"); catch, return; end
if ~isfield(ports,"Inport") || numel(ports.Inport) ~= 1, return; end
line = -1; try, line = double(get_param(ports.Inport(1),"Line")); catch, end
if line <= 0, return; end
source = -1; try, source = double(get_param(line,"SrcPortHandle")); catch, end
yes = any(isfinite(source(:)) & source(:) > 0);
end

function [reportOk,blocks,identityOk] = trusted_vout_trace(base,sensors,sensorRef)
reportOk = false; blocks = strings(0,1); identityOk = false;
rows = field_items(base,"output_reports");
for i = 1:numel(rows)
    row = rows{i};
    if ~isstruct(row) || ~isfield(row,"name") || string(row.name) ~= "Vout" ...
            || ~getbool(row,"ok",false) || ~getbool(row,"provenance_ok",false)
        continue;
    end
    reportOk = true;
    traces = field_items(row,"trace");
    for q = 1:numel(traces)
        trace = traces{q};
        if ~isstruct(trace) || ~isfield(trace,"path"), continue; end
        reference = normtext(getfield_default(trace,"reference_block",""));
        semantic = normtext(getfield_default(trace,"trusted_semantic",""));
        path = string(trace.path);
        if reference == sensorRef && contains(semantic,"voltage measurement") ...
                && any(sensors == path)
            blocks(end+1,1) = path; %#ok<AGROW>
        end
    end
end
blocks = unique(blocks,"stable"); identityOk = numel(blocks) == 1;
end

function ok = structure_report_ok(base,id)
ok = false; rows = field_items(base,"struct_reports");
for i = 1:numel(rows)
    row = rows{i};
    if isstruct(row) && isfield(row,"id") && string(row.id) == string(id)
        ok = getbool(row,"ok",false); return;
    end
end
end

function yes = contains_identifier(value,name)
pattern = ['(?<![A-Za-z0-9_])' ...
    regexptranslate('escape',char(name)) '(?![A-Za-z0-9_])'];
yes = ~isempty(regexp(char(value),pattern,'once'));
end

function value = normtext(value)
value = lower(regexprep(strtrim(string(value)),'\s+',' '));
value = replace(value,'\','/');
end
function value = getp(block,name)
value = ""; try, value = string(get_param(block,char(name))); catch, end
end
function value = getfield_default(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value = s.(name); end
end
function value = getbool(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && isscalar(s.(name)), value = logical(s.(name)); end
end
function rows = field_items(s,name)
if ~isstruct(s) || ~isscalar(s) || ~isfield(s,name) || isempty(s.(name))
    rows = {};
elseif iscell(s.(name)), rows = s.(name)(:).';
else, rows = arrayfun(@(x)x,s.(name),"UniformOutput",false);
end
end
function value = getvector(s,name)
value = double(getfield_default(s,name,zeros(0,1))); value = value(:);
end
function value = getmatrix(s,name,columns)
value = double(getfield_default(s,name,zeros(0,columns)));
if isempty(value), value = zeros(0,columns); end
if size(value,2) ~= columns, value = zeros(0,columns); end
end
function yes = all_exact(s,name,count)
value = logical(getfield_default(s,name,false(0,1)));
yes = numel(value) == count && all(value(:));
end
function evidence = empty_evidence()
evidence = struct( ...
    "trusted_switch_count",0,"trusted_switch_blocks",strings(0,1), ...
    "controlled_gate_count",0,"gate_converter_blocks",strings(0,1), ...
    "phase_count",0,"rail_count",0,"phase_rail_branch_matrix",zeros(0), ...
    "phase_nets",zeros(0,1),"rail_nets",zeros(0,1), ...
    "midpoint_net",NaN,"dc_source_block","", ...
    "p_load_resistor_blocks",strings(0,1), ...
    "vout_measurement_block","", ...
    "dc_source_to_switch_to_load_path",false, ...
    "vout_phase_to_midpoint",false,"native_net_stats",struct());
end
