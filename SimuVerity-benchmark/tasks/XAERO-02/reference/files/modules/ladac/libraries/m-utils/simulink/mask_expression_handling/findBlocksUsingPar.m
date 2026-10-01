function [results, blks_idxs_bool] = findBlocksUsingPar(blks_h, par_name, par_name_rep)
% FINDBLOCKSUSINGPAR searches for the use of parameters in Simulink blocks.
% 
% Inputs (required):
%   blks_h            Array of Simulink block handles
%   par_name          Parameter name to search for
%
% Inputs (optional):
%   par_name_rep      Replacement for par_name
% 
% Outputs:
%   results           Results returned as struct
%   blks_idxs_bool    Logical indexes of blks_h that use par_name

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************



% ToDo:
% - Add recognition of parameter index access (e. g. par_a(3)), such a
%   thing cannot be handled easily! If par_a = c+d, where c = [1,2,3] and
%   d = [4,5,6], it is okay to do par_a(3), but it doesn't work to do
%   (c+d)(3). Only c(3)+d(3) would be possible.
% - Handle Array of par_names?!



%% Config
% Parameter detection pattern
%   Assuming par_name = 'omega'
%   - Make sure that 'par_name' is not matched if it is fieldname of a
%     structure, e. g. structA.omega.b
%   - Make sure that 'par_name' can be matched with a trailing math
%     operation, e. g. omega.*omega

regex_pattern = ['(?<=([^a-zA-Z0-9_.]|^))' ...
                regexptranslate('escape', par_name) ...
                '(?=([^a-zA-Z0-9_.]|\.[^a-zA-Z]|$))'];

% Debugging
debug = false;



if debug
    msg = sprintf('%s ''%s''', bold('DEBUG:'), sprintf('<a href = "matlab:open(''%1$s'')">%1$s</a>', mfilename));
    fprintf('%s\n\n', msg);
end


results = struct.empty;
idx_res = 1;

blks_idxs_bool = false(size(blks_h));

for blk_idx = 1:numel(blks_h)
    blk_h = blks_h(blk_idx);
    
    % get dialog parameters of block
    blk_dia_pars = get_param(blk_h, 'DialogParameters');
    if isempty(blk_dia_pars)
        continue
    end
    blk_dia_pars = fieldnames(blk_dia_pars);
    
    if debug
        blk_dia_par_vals = cell(size(blk_dia_pars));
    end
    
    
    % search for matches in dialog parameters
    matches = struct.empty;
    idx_mtch = 1;
    for par_idx = 1:numel(blk_dia_pars)
        dia_par_val = get_param(blk_h, blk_dia_pars{par_idx});
        
        if debug
            if iscell(dia_par_val)
                [rows, clmns] = size(dia_par_val);
                descr = sprintf('%ix%i cell', rows, clmns);
                blk_dia_par_vals(par_idx) = {bold(descr)};
            else
                blk_dia_par_vals(par_idx) = {dia_par_val};
            end
        end
        
        % dialog parameter is a cell, no handling for that
        if iscell(dia_par_val)
            continue;
        end
        
        if ~isempty(dia_par_val)
            if nargin == 2
                idx_a = regexp(dia_par_val, regex_pattern, 'once');
                if ~isempty(idx_a)
                    matches(idx_mtch).blk_par = blk_dia_pars{par_idx};
                    idx_mtch = idx_mtch + 1;
                    blks_idxs_bool(blk_idx) = true;
                    break;
                end
            else
                dia_par_rep = regexprep(dia_par_val, regex_pattern, par_name_rep);
                if ~strcmp(dia_par_val, dia_par_rep)
                    matches(idx_mtch).blk_par = blk_dia_pars{par_idx};
                    matches(idx_mtch).blk_par_rep = dia_par_rep;                    
                    idx_mtch = idx_mtch + 1;
                end
            end
        end
    end
    
    if debug
        blk_type = get_param(blk_h, 'BlockType');
        blk_mask = get_param(blk_h, 'Mask');
        fprintf('\n%s:\n', get_link_to_blk_h(blk_h));
        msg = sprintf('\nBlockType: %s', blk_type);
        if strcmp(blk_mask, 'on')
            msg = [msg, ' with mask'];
        end
        fprintf('%s\n\n', msg);
        
        header = {'DialogParameter', 'Value'};
        data = [blk_dia_pars, blk_dia_par_vals];
        printData(header, data, 'headerstyle', 'bold')
        fprintf('%s\n\n', msg);
    end
    
    if ~isempty(matches)
        results(idx_res).blk_h = blk_h;
        results(idx_res).matches = matches;
        idx_res = idx_res + 1;
    end
    
end

end
