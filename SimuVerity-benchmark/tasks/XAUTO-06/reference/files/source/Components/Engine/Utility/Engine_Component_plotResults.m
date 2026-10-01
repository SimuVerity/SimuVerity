function Engine_Component_plotResults(nvpairs)
% plots the simulation result.

% Copyright 2022 The MathWorks, Inc.

arguments
  nvpairs.SimData timetable
  nvpairs.FigureHeight (1,1) {mustBePositive} = 300
end

sigNames = [ ...
  "Engine torque command", ...
  "Engine power", ...
  "Engine torque", ...
  "Axle torque", ...
  "Engine speed", ...
  "Axle speed" ];

for i = 1 : numel(sigNames)
  fig = plotSimulationResultSignal(SimData = nvpairs.SimData, SignalName = sigNames(i));
  fig.Position(4) = nvpairs.FigureHeight;
end

end  % function
