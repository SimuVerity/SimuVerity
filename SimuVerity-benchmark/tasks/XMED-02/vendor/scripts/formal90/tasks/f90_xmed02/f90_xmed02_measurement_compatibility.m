function varargout = f90_xmed02_measurement_compatibility(helperName, varargin)
%f90_xmed02_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xmed02_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["localAssignScenario", "localTimeseries", "localHeartRateEstimate"];
        end
    case "localAssignScenario"
        if nargout == 0
            localAssignScenario(varargin{:});
        else
            [varargout{1:nargout}] = localAssignScenario(varargin{:});
        end
    case "localTimeseries"
        if nargout == 0
            localTimeseries(varargin{:});
        else
            [varargout{1:nargout}] = localTimeseries(varargin{:});
        end
    case "localHeartRateEstimate"
        if nargout == 0
            localHeartRateEstimate(varargin{:});
        else
            [varargout{1:nargout}] = localHeartRateEstimate(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xmed02_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function localAssignScenario(scenario)
names = string(fieldnames(scenario));
for index = 1:numel(names)
    name = char(names(index));
    if strcmp(name, "id"), continue; end
    assignin("base", name, scenario.(name));
end
end

function signal = localTimeseries(output, variable, channels, stopTime, minSamples)
signal = struct("valid", false, "reasons", strings(0, 1), ...
    "time", zeros(0, 1), "data", zeros(0, channels));
try
    value = simuverity_public_output_compatibility( ...
        output, string(variable), channels, AllowBaseWorkspace=true);
catch ME
    signal.reasons(end + 1, 1) = ...
        "public_output_contract:" + string(ME.identifier) + ":" + ...
        string(ME.message);
    return;
end
time = double(value.Time(:));
data = squeeze(double(value.Data));
if isvector(data), data = data(:); end
if size(data, 1) ~= numel(time) && size(data, 2) == numel(time)
    data = data.';
end
if size(data, 1) ~= numel(time)
    signal.reasons(end + 1, 1) = variable + "_time_data_mismatch";
elseif size(data, 2) ~= channels
    signal.reasons(end + 1, 1) = variable + "_wrong_channel_count";
elseif numel(time) < minSamples
    signal.reasons(end + 1, 1) = variable + "_too_few_samples";
elseif isempty(time) || time(1) > 1e-6 || time(end) < stopTime - 0.02
    signal.reasons(end + 1, 1) = variable + "_incomplete_time_coverage";
elseif any(diff(time) <= 0)
    signal.reasons(end + 1, 1) = variable + "_nonmonotonic_time";
elseif ~all(isfinite(data), "all")
    signal.reasons(end + 1, 1) = variable + "_nonfinite_data";
else
    signal.valid = true;
end
signal.time = time;
signal.data = data;
end

function bpm = localHeartRateEstimate(time, signal, expectedBpm)
mask = time >= max(time(end) - 4.5, time(1) + 0.5);
t = time(mask);
y = signal(mask);
if numel(y) < 20
    bpm = NaN;
    return;
end
dt = median(diff(t));
y = detrend(y, 1);
expectedPeriod = 60 / expectedBpm;
minimumLag = max(2, round(0.75 * expectedPeriod / dt));
maximumLag = min(numel(y) - 2, round(1.25 * expectedPeriod / dt));
if maximumLag <= minimumLag
    bpm = NaN;
    return;
end
scores = -Inf(maximumLag - minimumLag + 1, 1);
for lag = minimumLag:maximumLag
    left = y(1:end-lag);
    right = y(1+lag:end);
    denominator = sqrt(sum(left .^ 2) * sum(right .^ 2));
    if denominator > 0
        scores(lag - minimumLag + 1) = ...
            sum(left .* right) / denominator;
    end
end
[~, bestIndex] = max(scores);
bestLag = minimumLag + bestIndex - 1;
if bestIndex > 1 && bestIndex < numel(scores)
    leftScore = scores(bestIndex - 1);
    centerScore = scores(bestIndex);
    rightScore = scores(bestIndex + 1);
    curvature = leftScore - 2 * centerScore + rightScore;
    if isfinite(curvature) && abs(curvature) > eps
        bestLag = bestLag + 0.5 * ...
            (leftScore - rightScore) / curvature;
    end
end
bpm = 60 / (bestLag * dt);
end
