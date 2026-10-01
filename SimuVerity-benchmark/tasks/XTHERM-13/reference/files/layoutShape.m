classdef layoutShape < int32
    % Enumeration class for coil layout.
    % Copyright 2023 The MathWorks, Inc.

    enumeration
        HelicalCoil(1) % Helical shaped coils for heating and cooling
        UshapedCoil(2) % Connected U shaped coils for heating and cooling  
    end

    methods(Static)
        function map = displayText()
            map = containers.Map;
            map('HelicalCoil') = 'Helix Shaped Coil';
            map('UshapedCoil') = 'Serpentine Tube';
        end
    end
end