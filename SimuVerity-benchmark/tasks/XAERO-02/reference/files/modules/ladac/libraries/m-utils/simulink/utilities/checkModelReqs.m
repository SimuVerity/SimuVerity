function varargout = checkModelReqs(model, model_reqs)
% CHECKMODELREQS checks whether the Simulink model fulfills the model
%   parameter requirements in 'model_reqs'. CheckModelReqs throws an error
%   with a tabular overview of the parameters that have not fulfilled the
%   requirements. The model must be loaded for usage.
%
%   The parameter requirements must be provided in the form of a struct
%   (model_reqs) with the required fields 'param' and 'value' and the
%   optional field 'err_desc', whereby the values of the fields must be
%   cell arrays, e.g.
%       model_reqs.param{1}    = 'TargetLang';
%       model_reqs.value{1}    = 'C++';
%       model_reqs.err_desc{1} = 'Wrong target language';
%    
%   The value check can also be provided as a function handle to a function
%   that must return a boolean as the check result, e.g.
%       model_reqs.value{1}    = @(a) strcmp(a, C++);
% 
%   The parameter requirements can also be provided with a parameter file.
%   In this case, 'model_reqs' must be a path to the parameter file.
% 
% Inputs:
%   model           Handle or path to a top-level Simulink model
%                   (model root)
%   model_reqs      Model requirements struct as specified above or
%                   a path to a model requirements file
% 
% Outputs (optional):
%   varargout{1}    No error is thrown, but instead an boolean array with
%                   the indices of all failed parameter requirements is
%                   returned

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% ToDo:
% - change model_reqs to struct array instead of cell arrays?


% Input checks
err_msg = char.empty;

if nargin ~=2
    error('MATLAB:checkModelReqs:inputError', ...
          'Wrong number of input arguments!');
end

if ~bdIsRoot(model)
    msg = sprintf(' - %s\n', 'expected input ''model'' to be a loaded top-level Simulink model');
    err_msg = [err_msg, msg];
end

if ischar(model_reqs)
    model_reqs = loadParams(model_reqs);
end

if ~all(isfield(model_reqs, {'param', 'value'}))
    msg = sprintf(' - %s\n', 'expected input ''model_reqs'' to be of type struct with at least two fields named ''param'' and ''value''');
    err_msg = [err_msg, msg];
elseif any(size(model_reqs.param) ~= size(model_reqs.value))
    msg = sprintf(' - %s\n', '''model_reqs.param'' and ''model_reqs.value'' must have the same size');
    err_msg = [err_msg, msg];
end

if ~isempty(err_msg)
    err_title = sprintf('Input error');
    error('MATLAB:checkModelReqs:inputError', ...
          '\n%s:\n%s', err_title, err_msg);
end

has_err_desc = isfield(model_reqs, 'err_desc');     % ToDo: size check?


% Do model requirement checks
errs = {};
idxs = false(size(model_reqs.param));
for idx = 1:numel(model_reqs.param)

    % ToDo:
    % - Check that value is scalar and of type char?
    %   -> Scalar is usefull, char could be dismissed, because a function
    %      handle check could still succeed
    % - Check that param is an actual param of the model, raise error if
    %   not
    value = get_param(model, model_reqs.param{idx});

    switch class(model_reqs.value{idx})
        case 'function_handle'
            is_ok = model_reqs.value{idx}(value);
        case {'char', 'string'}
            is_ok = strcmp(model_reqs.value{idx}, value);
        otherwise
            error('MATLAB:checkModelReqs:inputError', '''model_reqs.value{%i}'' not supported!', idx);
    end

    if ~is_ok
        idxs(idx) = true;
        
        err = repmat({char.empty}, 1, 4);
        err(1) = model_reqs.param(idx);
        err(3) = {value};
        if has_err_desc
            err(4) = model_reqs.err_desc(idx);
        end
        switch class(model_reqs.value{idx})
            case 'function_handle'
                err(2) = {func2str(model_reqs.value{idx})};
            case {'char', 'string'}
                err(2) = model_reqs.value(idx);
        end
        errs = [errs; err];
    end
end


if ~isempty(errs)
    header = {'Param:', 'Expected:', 'Actual:', char.empty};
    if has_err_desc
        header(4) = {'Description:'};
    end

    err_id    = 'MATLAB:checkModelReqs:requirementsFailed';
    err_title = 'Model parameter requirements failed for';
    err_msg   = printData(header, errs, 'headerstyle', 'bold', 'indent', 4, 'column_spacing', 2);

    ME = MException(err_id, '\n%s:\n%s', err_title, err_msg);

    if nargout ~= 1
        throw(ME);
    end
end

if nargout == 1
    varargout{1} = idxs;
end
   
end
