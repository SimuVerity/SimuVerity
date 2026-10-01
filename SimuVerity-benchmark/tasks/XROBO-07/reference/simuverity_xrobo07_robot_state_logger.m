function simuverity_xrobo07_robot_state_logger(block)
%SIMUVERITY_XROBO07_ROBOT_STATE_LOGGER Preserve independent tap timing.
% The official reference exposes pose and velocity on separate measurement
% paths.  This sink reconstructs the public five-channel Timeseries with the
% same linear-pose/previous-velocity sampling semantics used by the current
% reference extractor.  It does not feed any signal back into the model.
setup(block);
end

function setup(block)
block.NumDialogPrms = 0;
block.NumInputPorts = 1;
block.NumOutputPorts = 0;
block.SetPreCompInpPortInfoToDynamic;
block.InputPort(1).Dimensions = 5;
block.InputPort(1).DatatypeID = 0;
block.InputPort(1).Complexity = "Real";
block.InputPort(1).DirectFeedthrough = true;
block.SampleTimes = [0.1 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("Start", @localStart);
block.RegBlockMethod("Outputs", @localOutputs);
block.RegBlockMethod("Terminate", @localTerminate);
end

function localStart(block)
key = localKey(block);
state = struct("time", zeros(0, 1), "data", zeros(0, 5));
localState("set", key, state);
end

function localOutputs(block)
key = localKey(block);
state = localState("get", key);
state.time(end + 1, 1) = double(block.CurrentTime);
state.data(end + 1, :) = double(block.InputPort(1).Data(:).');
localState("set", key, state);
end

function localTerminate(block)
key = localKey(block);
state = localState("get", key);
cleanup = onCleanup(@() localState("remove", key)); %#ok<NASGU>
% Simulink invokes Terminate once for compile-only lifecycle checks at t=0.
% That phase has no run evidence to publish.
if numel(state.time) < 2, return, end
[rawTime, indices] = unique(double(state.time(:)), "stable");
rawData = double(state.data(indices, :));
endTime = max(rawTime);
sampleTime = (0:0.1:endTime)';
if sampleTime(end) < endTime - 1e-9
    sampleTime(end + 1, 1) = endTime;
end
pose = interp1(rawTime, rawData(:, 1:3), sampleTime, ...
    "linear", "extrap");
velocity = interp1(rawTime, rawData(:, 4:5), sampleTime, ...
    "previous", "extrap");
publicTime = linspace(0, endTime, numel(sampleTime))';
assignin("base", "robot_state", ...
    timeseries([pose, velocity], publicTime));
end

function key = localKey(block)
key = char(getfullname(block.BlockHandle));
end

function value = localState(action, key, value)
persistent states
if isempty(states)
    states = containers.Map("KeyType", "char", "ValueType", "any");
end
switch string(action)
    case "set"
        states(key) = value;
    case "get"
        assert(isKey(states, key), ...
            "SimuVerity:XROBO07:RobotStateLogger", ...
            "Robot-state logger state is unavailable.");
        value = states(key);
    case "remove"
        if isKey(states, key), remove(states, key); end
        value = [];
    otherwise
        error("SimuVerity:XROBO07:RobotStateLogger", ...
            "Unsupported logger state action: %s", action);
end
end
