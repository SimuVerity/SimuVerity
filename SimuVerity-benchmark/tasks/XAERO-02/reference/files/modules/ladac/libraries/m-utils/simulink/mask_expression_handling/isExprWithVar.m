function is_expr_with_var = isExprWithVar(expr)
% ISEXPRWITHVAR checks if an input string is an expression with variable.
% 
% Inputs:
%   expr                Charracter array or String
% 
% Outputs:
%   is_expr_with_var    Logical (true, false)

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************



% ToDo:
% - At the moment, this probably only makes sense for expressions using
%   scalar variables?!



%% Examples:

% expr:                                                  is_expr_with_var:
% 2             -> numeric,             no expression:   false
% 2 ./ 7        -> numeric,             expression:      false
% 1e-3 .* 2     -> numeric,             expression:      false (with scientific notation)
% par           -> variable,            no expression:   false
% parA .* parB  -> variable,            expression:      true
% 2 .* par      -> numeric & variable,  expression:      true
% 1e-3 .* e     -> numeric & variable,  expression:      true (with scientific notation)



% https://mathworks.com/help/matlab/matlab_prog/matlab-operators-and-special-characters.html
% https://mathworks.com/help/matlab/matlab_prog/array-vs-matrix-operations.html
math_operators = {'+'; '-'; '*'; '/'; '\'; '^'};

% str2num conversion only suceeds if input contains no variables
% (letters) and handles scientific notations and math operations
expr_num = str2num(expr);

if ~isempty(expr_num)
    % catch numeric with or without expression
    is_expr_with_var = false;
elseif contains(expr, math_operators)
    % catch variable with expression
    is_expr_with_var = true;
else
    % catch variable only (e. g. par)
    is_expr_with_var = false;
end

end
