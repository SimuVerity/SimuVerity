function varargout = printData(header, data, varargin)
% PRINTDATA displays tabular data on the Matlab command window.
% 
% Inputs (required):
%   header      nx1 row cell containing the header strings / character
%               arrays. An empty cell means no header.
%   data        nxm matrix cell containing the data strings / character
%               arrays.
% 
% Inputs (optional):
%   varargin    'indent':               Indentation of the table
%               'column_spacing':       Distance between columns
%               'headerstyle':          'normal', 'bold'
%               'data_postprocessing':  Add postprocessing to the data
%                                       columns, e. g. if a column should
%                                       be bold
% 
% Outputs (optional):
%   varargout{1}    Formatted table is not displayed, but returned as an
%                   ouput argument

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************



% ToDo's / Upgrades:
% - Better implementation of Pre -and Postprocessing
% - Introduction of a parameter, that limits the width of an entry
%   and autoformats with multiline...
% - Handle '\n' in given data... (similar to the option above)
% - Wrapper function that converts numeric data to strings
%   (printDataNumeric)



%% Input Parser
[~, data_width] = size(data);

is_header = ~isempty(header);
is_header_bold = false;

headerstyles = {'normal', 'bold'};

p = inputParser;

addParameter(p, 'indent',               0,          @(a) isnumeric(a) && isscalar(a) );
addParameter(p, 'column_spacing',       1,          @(a) isnumeric(a) && isscalar(a) );
addParameter(p, 'headerstyle',          'normal',   @(a) ischar(validatestring(a, headerstyles)) );
addParameter(p, 'data_postprocessing',  cell.empty, @(a) size(a, 2) == data_width );

parse(p, varargin{:});

indent = p.Results.indent;
space = p.Results.column_spacing;
data_postprocessing = p.Results.data_postprocessing;

if is_header
    headerstyle = validatestring(p.Results.headerstyle, headerstyles);
    if strcmp(headerstyle, 'bold')
        is_header_bold = true;
    end
end



%% Output Parser
switch nargout
    case 0
        disp_data = true;
    case 1
        disp_data = false;
    otherwise
        error('Only one output argument allowed!')
end



%% Processing
% Preprocessing
% - ToBeFilled if needed


% Sizes Calculation
if is_header
    all = [header; data];
    data_start_row = 2;
else
    all = data;
    data_start_row = 1;
end

sizes = zeros(size(all));    
for idx=1:size(all,1)
    sizes(idx,:) = cellfun(@(x) numel(x), all(idx,:));
end
sizes_max = max(sizes, [], 1);


% Postprocessing data
if ~isempty(data_postprocessing)
    for c_idx = 1:numel(data_postprocessing)
        fcn_h = data_postprocessing{c_idx};
        if isa(fcn_h, 'function_handle') && ~isempty(fcn_h)
            for r_idx = data_start_row:size(all,1)
                all(r_idx, c_idx) = {fcn_h(all{r_idx, c_idx})};
            end
        end
    end
end


% Bold header
if is_header_bold
    all(1,:) = bold(all(1,:));
end



%% Output
if ~disp_data
    out = [];
end

indent_str = repmat(' ', 1, indent);

for r_idx=1:size(all,1)
    
    str = indent_str;
    for c_idx=1:(size(all,2)-1)
        str = [str all{r_idx, c_idx} repmat(' ', 1, (sizes_max(c_idx) - sizes(r_idx, c_idx) + space) )];
    end
    str = [str all{r_idx, size(all,2)}];

    if disp_data
        fprintf('%s\n', str);
    else
        out = [out sprintf('%s\n', str)];
    end
end

if ~disp_data
    varargout{1} = out;
end

end
