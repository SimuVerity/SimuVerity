function paramSpace = setSDOParamSpace(varTable,modelName)
%% Description:
% This script creates a parameter space that can be used for the
% sensitivity analysis. The script can distinguish between continuous and
% discrete parameter spaces (using the RowNames of the input table).

% This script is to be use in combination with the function
% sensitivityGlobal. In sensitivityGlobal the user can see how to build the
% varTable input for both discrete and continuous set of parameters

%% Inputs
% varTable:  [table] Contains information on the parameter space to be generated
% modelName: [char] Name of the model for which we are generating the parameter space

%% Output
% paramSpace [GriddedSpace or ParameterSpace] Variable storing all information on how the parameters should be varied for the sensitivity analysis

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% Implementation
% If the table contains a row named "Minimum" then it is a continuous
% parameter space. Otherwise we assume a discrete parameter space
if strcmp(varTable.Row{1},'Minimum'); isContinuous = 1; else; isContinuous = 0; end


% Get parameter handles from Model
parameters = sdo.getParameterFromModel(modelName, varTable.Properties.VariableNames);

%% Continuous parameter space. Use a random distribution to generate the data
if isContinuous==1
   
    % Loop through the table and assign minimum and maximum values
    for i=1:size(varTable,2)
        parameters(i).Minimum = varTable{'Minimum',i};
        parameters(i).Maximum = varTable{'Maximum',i};
    end
    
    % Create the parameter space
    paramSpace  = sdo.ParameterSpace(parameters);
    
    % Set method for continuous space to RANDOM
    paramSpace.Options.Method = 'random';


%% Discrete parameter space. Use discrete sampling
else

    % Loop through the table and assign set of values
    for i=1:size(varTable,2)
        discreteValues{i}= num2cell(varTable{'Values',i});
    end
    
    % Create the parameter space
    paramSpace  = sdo.GriddedSpace(parameters,discreteValues);

    % Set parameter space method to exhaustive
    paramSpace.Options.Method = 'exhaustive';
end

end