classdef ForceComputation < int32
% Enumeration class for tractor implement options in custom block implement.

% Copyright 2024 The MathWorks, Inc.

enumeration
    Calculate(1)
    UserInput(2)
end

methods (Static, Hidden)
    function map = displayText()
        map = containers.Map;
        map('Calculate') = 'Draft force prediction based on ASABE D497.5 standard';
        map('UserInput') = 'Specify vectors for draft force, vertical force and velocity';
    end
end
end