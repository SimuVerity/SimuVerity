classdef ImplementType < int32
% Enumeration class for tractor implement options in custom block implement.

% Copyright 2024 The MathWorks, Inc.

enumeration
    Subsoiler(1)
    MoldboardPlow(2)
    ChiselPlow(3)
    SweepPlow(4)
    FieldCultivator(5)
end

methods (Static, Hidden)
    function map = displayText()
        map = containers.Map;
        map('Subsoiler') = 'Subsoiler - narrow point';
        map('MoldboardPlow') = 'Moldboard Plow';
        map('ChiselPlow') = 'Chisel Plow - 5 cm straight point';
        map('SweepPlow') = 'Sweep Plow for primary tillage';
        map('FieldCultivator') = 'Field Cultivator for primary tillage';
    end
end
end