function [series, metadata] = simuverity_public_output_compatibility( ...
        source, outputName, allowedWidths, options)
%SIMUVERITY_PUBLIC_OUTPUT_COMPATIBILITY Lossless public-output canonicalization.
%
% This is the single SimuVerity output-compatibility boundary.  It accepts only
% representations that can be converted to a MATLAB Timeseries without
% inventing, deleting, resampling, padding, truncating, or interpolating
% candidate data.  Task-specific semantics remain in each task extractor.
arguments
    source
    outputName (1,1) string
    allowedWidths double = []
    options.ExternalTime = []
    options.AllowBaseWorkspace (1,1) logical = false
end

localValidateEvaluatorContract(outputName, allowedWidths);
metadata = localMetadata(outputName, allowedWidths);
[value, externalTime, sourceMeta] = localResolveSource( ...
    source, outputName, options.ExternalTime, options.AllowBaseWorkspace);
metadata.source_container = sourceMeta.container;
metadata.source_type = sourceMeta.type;
metadata.actions = sourceMeta.actions;

if isempty(value)
    localCandidateFailure("MISSING_OUTPUT", ...
        "Required public output " + outputName + " is missing.");
end

[time, data, valueMeta] = localExtractTimeAndData(value, externalTime);
metadata.actions = [metadata.actions; valueMeta.actions];
metadata.source_type = valueMeta.type;
[data, shapeMeta] = localCanonicalShape(data, numel(time));
metadata.actions = [metadata.actions; shapeMeta.actions];
metadata.source_channels = size(data, 2);

if ~isempty(allowedWidths) && ...
        ~any(metadata.source_channels == allowedWidths)
    if metadata.source_channels == 1 && ~isreal(data) && ...
            any(allowedWidths == 2)
        data = [real(data), imag(data)];
        metadata.actions(end+1, 1) = "complex_scalar_to_real_imag";
    else
        localCandidateFailure("CHANNEL_COUNT", sprintf( ...
            "Public output %s has %d channel(s); allowed width(s): %s.", ...
            outputName, metadata.source_channels, ...
            strjoin(string(allowedWidths), ",")));
    end
end

time = double(time(:));
try
    data = double(data);
catch ME
    localCandidateFailure("NON_NUMERIC_DATA", ...
        "Public output " + outputName + ...
        " cannot be represented as numeric evidence: " + string(ME.message));
end
if numel(time) < 2 || any(~isfinite(time)) || any(diff(time) <= 0)
    localCandidateFailure("INVALID_TIMEBASE", ...
        "Public output " + outputName + ...
        " must have at least two finite, strictly increasing time points.");
end
if any(~isfinite(data), "all")
    localCandidateFailure("NONFINITE_DATA", ...
        "Public output " + outputName + " contains nonfinite data.");
end

series = timeseries(data, time);
try, series.Name = char(outputName); catch, end
metadata.target_channels = size(data, 2);
metadata.applied = any(metadata.actions ~= "none");
metadata.actions = unique(metadata.actions(metadata.actions ~= "none"), ...
    "stable");
if isempty(metadata.actions), metadata.actions = "none"; end
metadata.accepted = true;
metadata.failure_attribution = "";
metadata.reason = "accepted_lossless_representation";
end

function localValidateEvaluatorContract(outputName, allowedWidths)
if strlength(outputName) == 0
    localEvaluatorFailure("OUTPUT_NAME", ...
        "The evaluator supplied an empty public-output name.");
end
if ~isempty(allowedWidths) && (any(~isfinite(allowedWidths)) || ...
        any(allowedWidths < 1) || any(mod(allowedWidths, 1) ~= 0))
    localEvaluatorFailure("ALLOWED_WIDTHS", ...
        "The evaluator supplied invalid allowed channel widths.");
end
end

function metadata = localMetadata(outputName, allowedWidths)
metadata = struct( ...
    "schema", "simuverity.unified-public-output-compat.v1", ...
    "policy_id", "simuverity-public-output-compatibility", ...
    "output_name", outputName, ...
    "allowed_widths", double(allowedWidths(:))', ...
    "accepted", false, ...
    "applied", false, ...
    "lossless", true, ...
    "source_container", "", ...
    "source_type", "", ...
    "source_channels", 0, ...
    "target_channels", 0, ...
    "actions", "none", ...
    "failure_attribution", "candidate", ...
    "reason", "not_evaluated");
end

function [value, externalTime, meta] = localResolveSource( ...
        source, outputName, externalTime, allowBaseWorkspace)
value = source;
meta = struct("container", string(class(source)), ...
    "type", string(class(source)), "actions", "none");
if isa(source, "Simulink.SimulationData.Dataset")
    value = [];
    try
        element = source.getElement(char(outputName));
        if ~isempty(element)
            value = element;
            meta.actions = "resolve_exact_dataset_element";
        end
    catch
    end
    meta.type = string(class(value));
    return
end
if ~isa(source, "Simulink.SimulationOutput")
    return
end

value = [];
meta.container = "Simulink.SimulationOutput";
try
    value = source.get(char(outputName));
catch
end
if isempty(value)
    try
        logsout = source.get("logsout");
        if isa(logsout, "Simulink.SimulationData.Dataset")
            element = logsout.getElement(char(outputName));
            if ~isempty(element)
                value = element;
                meta.actions = "resolve_exact_logsout_element";
            end
        end
    catch
    end
end
if isempty(value) && allowBaseWorkspace && isvarname(char(outputName))
    try
        if evalin("base", "exist('" + ...
                replace(outputName, "'", "''") + "','var') == 1")
            value = evalin("base", outputName);
            meta.actions = "resolve_base_workspace_variable";
        end
    catch
    end
end
if isempty(externalTime)
    try, externalTime = source.get("tout"); catch, end
end
meta.type = string(class(value));
end

function [time, data, meta] = localExtractTimeAndData(value, externalTime)
meta = struct("type", string(class(value)), "actions", "none");
while isa(value, "Simulink.SimulationData.Signal")
    value = value.Values;
    meta.actions(end+1, 1) = "unwrap_simulink_signal";
end
if isa(value, "Simulink.SimulationData.Dataset")
    localCandidateFailure("AMBIGUOUS_DATASET", ...
        "A Dataset must contain one exact named element for the required output.");
end
if isstruct(value) && isscalar(value) && isfield(value, "Values")
    value = value.Values;
    meta.actions(end+1, 1) = "unwrap_values_field";
end
meta.type = string(class(value));

if isa(value, "timeseries")
    time = value.Time;
    data = value.Data;
    return
end
if istimetable(value)
    rows = value.Properties.RowTimes;
    if isduration(rows)
        time = seconds(rows);
    elseif isnumeric(rows)
        time = rows;
    else
        localCandidateFailure("TIMETABLE_TIME_TYPE", ...
            "Timetable row times must be numeric or duration values.");
    end
    values = value.Variables;
    if ~isnumeric(values) && ~islogical(values)
        localCandidateFailure("TIMETABLE_DATA_TYPE", ...
            "Timetable public-output variables must be numeric.");
    end
    data = values;
    meta.actions(end+1, 1) = "timetable_to_timeseries";
    return
end
if isstruct(value) && isscalar(value) && ...
        isfield(value, "Time") && isfield(value, "Data")
    time = value.Time;
    data = value.Data;
    meta.actions(end+1, 1) = "time_data_struct_to_timeseries";
    return
end
if isnumeric(value) || islogical(value)
    if isempty(externalTime)
        localCandidateFailure("NUMERIC_WITHOUT_TIME", ...
            "A numeric public output requires the simulation's explicit time vector.");
    end
    time = externalTime;
    data = value;
    meta.actions(end+1, 1) = "numeric_with_explicit_time_to_timeseries";
    return
end
localCandidateFailure("UNSUPPORTED_CONTAINER", ...
    "Unsupported public-output container: " + string(class(value)) + ".");
end

function [data, meta] = localCanonicalShape(data, timeCount)
meta = struct("actions", "none");
if ~(isnumeric(data) || islogical(data))
    localCandidateFailure("NON_NUMERIC_DATA", ...
        "Public-output data must be numeric or logical.");
end
if isempty(data)
    localCandidateFailure("EMPTY_DATA", "Public-output data is empty.");
end
dimensions = size(data);
if isvector(data) && numel(data) == timeCount
    data = reshape(data, timeCount, 1);
    if dimensions(1) ~= timeCount
        meta.actions = "orient_vector_time_first";
    end
    return
end
if dimensions(1) == timeCount
    data = reshape(data, timeCount, []);
    if numel(dimensions) > 2
        meta.actions = "flatten_non_time_dimensions";
    end
    return
end
matches = find(dimensions == timeCount);
if numel(matches) ~= 1
    localCandidateFailure("AMBIGUOUS_TIME_DIMENSION", ...
        "The public-output time dimension cannot be identified losslessly.");
end
order = [matches, setdiff(1:numel(dimensions), matches, "stable")];
data = permute(data, order);
data = reshape(data, timeCount, []);
meta.actions = "move_unique_time_dimension_first";
end

function localCandidateFailure(reason, message)
error("SimuVerity:UnifiedOutput:CandidateContract", ...
    "%s: %s", reason, message);
end

function localEvaluatorFailure(reason, message)
error("SimuVerity:UnifiedOutput:EvaluatorContract", ...
    "%s: %s", reason, message);
end
