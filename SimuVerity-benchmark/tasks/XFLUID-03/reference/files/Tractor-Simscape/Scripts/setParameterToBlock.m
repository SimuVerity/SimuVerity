function simIn = setParameterToBlock(simIn, blockPath, partDataSet)
% This function applies parameter values in Simscape block using 
% Simulink.SimulationInput or Simulation object.
% The function needs data set to be written in a specific format.
% The parameter fields should be having same name as available parameter
% description as the block parameters.
% Inputs to function are:
% simIn : Simulink.SimulationInput object to make changes to model for 
% multiple or individual simulations
% blockPath : 'TractorEnergyComputation/Tractor/Tractor Body and Powertrain/
% Hydrostatic CVT/Main Pump/Pump'
% OR
% 'TractorEnergyComputation/Tractor/
% Tractor Body and Powertrain/Hydrostatic CVT/Front Motor/Front Axle
% Motor'
% OR
% 'TractorEnergyComputation/Tractor/
% Tractor Body and Powertrain/Hydrostatic CVT/Rear Motor/Rear Axle
% Motor'
% partDataSet : Simscape block data set for example
% pump data set or motor data set
% Output of function is:
% simIn: Simulink.SimulationInput object


% Copyright 2024 - 2025 The MathWorks, Inc.

availableFields = fieldnames(partDataSet.parameters);
fieldSize = numel (availableFields);
for i = 1:fieldSize
    
    if ischar(partDataSet.parameters.(availableFields{i}).value)
        % If parameter field is string
        simIn = setBlockParameter(simIn,blockPath,availableFields{i},partDataSet.parameters.(availableFields{i}).value);
    elseif size(size(partDataSet.parameters.(availableFields{i}).value),2)<=2
        % If parameter field is numeric scalar or 2D matrix
        simIn = setBlockParameter(simIn,blockPath,availableFields{i},mat2str(partDataSet.parameters.(availableFields{i}).value));
    else
        % If parameter field is 3D matrix
        matSize = size(partDataSet.parameters.(availableFields{i}).value);
        newMat = zeros(matSize(1),matSize(2)*matSize(3));
        for jdx = 1:matSize(3)
            % Concatenating 3D matrix to 2D form
            newMat(1:matSize(1),matSize(2)*(jdx-1)+1:matSize(2)*(jdx))=...
                partDataSet.parameters.(availableFields{i}).value(1:matSize(1),1:matSize(2));
        end
        % Reshaping from 2D matrix to 3D form for setting parameter on the
        % block
        simIn = setBlockParameter(simIn,blockPath,availableFields{i},...
            ['reshape(',mat2str(newMat),',',mat2str(matSize),')']);
    end

    if isfield(partDataSet.parameters.(availableFields{i}),'unit')
        % Setting up unit where ever it's applicable
        simIn = setBlockParameter(simIn,blockPath,[(availableFields{i}),'_unit'],partDataSet.parameters.(availableFields{i}).unit);
    end
end
end