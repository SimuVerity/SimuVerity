function [blocks,phaseCoverage,ok,reason,evidence] = ...
        sat_d007_current_outputs(base)
%SAT_D007_CURRENT_OUTPUTS Resolve physical three-phase Igrid provenance.
% A single trusted SPS Three-Phase V-I Measurement block is a three-phase
% sensor when the output contract proves three channels with three distinct
% channel origins.  The existing three-discrete-sensor route is retained.

blocks = strings(0,1);
phaseCoverage = false;
ok = false;
reason = "IGRID_PHYSICAL_CURRENT_TRACE_MISSING";
evidence = empty_evidence();
items = field_items(base, "output_reports");
matches = {};
for i = 1:numel(items)
    row = items{i};
    if ~isstruct(row) || ~isfield(row,"name") || string(row.name) ~= "Igrid" ...
            || ~logical_field(row,"ok") || ~logical_field(row,"provenance_ok") ...
            || ~isfield(row,"trace") || ~isstruct(row.trace) || isempty(row.trace)
        continue;
    end
    channels = scalar_number(row,"channels",NaN);
    origins = origin_strings(row);
    distinctOrigins = unique(origins(strlength(origins)>0),"stable");
    if channels ~= 3 || numel(distinctOrigins) ~= 3
        continue;
    end
    currentRows = false(1,numel(row.trace));
    threePhaseRows = false(1,numel(row.trace));
    for q = 1:numel(row.trace)
        descriptor = trace_descriptor(row.trace(q));
        currentRows(q) = ~isempty(regexpi(char(descriptor), ...
            'current (measurement|sensor)','once'));
        threePhaseRows(q) = contains(descriptor,"three-phase vi measurement") ...
            || contains(descriptor,"three-phase v-i measurement");
    end
    if ~any(currentRows), continue; end
    currentBlocks = strings(0,1);
    for q = find(currentRows)
        if isfield(row.trace(q),"path")
            currentBlocks(end+1,1) = string(row.trace(q).path); %#ok<AGROW>
        end
    end
    currentBlocks = unique(currentBlocks(strlength(currentBlocks)>0),"stable");
    aggregate = numel(currentBlocks) == 1 && any(currentRows & threePhaseRows);
    discrete = numel(currentBlocks) >= 3;
    if ~(aggregate || discrete), continue; end
    matches{end+1} = struct( ... %#ok<AGROW>
        "blocks",currentBlocks,"channels",channels, ...
        "origins",distinctOrigins,"three_phase_vi_aggregate",aggregate);
end
if numel(matches) ~= 1
    if numel(matches) > 1
        reason = "IGRID_PHYSICAL_CURRENT_TRACE_AMBIGUOUS";
    elseif any_igrid_contract_row(items)
        reason = "IGRID_THREE_PHASE_CURRENT_ENDPOINTS_MISSING";
    end
    return;
end
match = matches{1};
blocks = match.blocks;
phaseCoverage = true;
ok = true;
reason = "OK";
evidence = struct( ...
    "channels",match.channels, ...
    "distinct_channel_origins",match.origins, ...
    "distinct_channel_origin_count",numel(match.origins), ...
    "measurement_blocks",blocks, ...
    "three_phase_vi_aggregate",logical(match.three_phase_vi_aggregate));
end

function descriptor = trace_descriptor(trace)
parts = strings(0,1);
for field = {"name","block_type","mask_type","reference_block", ...
        "trusted_semantic","descriptor"}
    if isfield(trace,field{1})
        parts(end+1) = string(trace.(field{1})); %#ok<AGROW>
    end
end
descriptor = lower(strjoin(parts,"|"));
end

function origins = origin_strings(row)
origins = strings(0,1);
if isfield(row,"channel_origins") && ~isempty(row.channel_origins)
    origins = string(row.channel_origins(:));
end
end

function tf = any_igrid_contract_row(items)
tf = false;
for i = 1:numel(items)
    row = items{i};
    if isstruct(row) && isfield(row,"name") && string(row.name) == "Igrid"
        tf = true;
        return;
    end
end
end

function value = scalar_number(row,name,default)
value = default;
if isstruct(row) && isfield(row,name) && isnumeric(row.(name)) ...
        && isscalar(row.(name)) && isfinite(row.(name))
    value = double(row.(name));
end
end

function value = logical_field(row,name)
value = isstruct(row) && isfield(row,name) && isscalar(row.(name)) ...
    && logical(row.(name));
end

function items = field_items(value,name)
if ~isstruct(value) || ~isscalar(value) || ~isfield(value,name) ...
        || isempty(value.(name))
    items = {};
elseif iscell(value.(name))
    items = value.(name)(:).';
else
    items = arrayfun(@(x)x,value.(name),"UniformOutput",false);
end
end

function value = empty_evidence()
value = struct( ...
    "channels",0,"distinct_channel_origins",strings(0,1), ...
    "distinct_channel_origin_count",0,"measurement_blocks",strings(0,1), ...
    "three_phase_vi_aggregate",false);
end
