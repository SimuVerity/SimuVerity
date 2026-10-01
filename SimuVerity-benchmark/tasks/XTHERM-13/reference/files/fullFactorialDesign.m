% Copyright 2023 - 2024 The MathWorks, Inc.

function design = fullFactorialDesign(levels)
    % levels: a vector containing the number of levels for each variable
    
    % Calculate the total number of combinations
    numCombinations = prod(levels);
    
    % Generate the full factorial design matrix
    numVariables = length(levels);
    design = zeros(numCombinations, numVariables);
    
    % Generate the combinations
    for i = 1:numCombinations
        for j = 1:numVariables
            design(i, j) = mod(floor((i-1) / prod(levels(1:j-1))), levels(j)) + 1;
        end
    end
    
end