function [fieldpaths, classes, sizes, values] = unpackStruct(s, varargin)
% UNPACKSTRUCT returns informations about all fields in an arbitrarily deep
%   nested struct.
% 
% Inputs (required):
%   s       arbitrarily deep nested struct
% 
% Inputs (optional):
%   varargin    'tln':          Toggle if the field names should include
%                               the name of the top level struct, bool
%               'tln_name':     Override the top level name, char array /
%                               string
%               'delimiter':    Define the delimiter character used for the
%                               field name, char
% 
% Outputs:
%   fieldpaths  Full paths of the fields, separated by 'delimiter', cell
%               array of char arrays
%   classes     Classes (names) of the fields, cell array of char arrays
%   sizes       Dimensions of the fields, cell array of double arrays
%   values      Data of the fields, cell array
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% ToDo:
%  - Add support for structure arrays?
%  - Add fieldparts as additional output?

% Input Checks
if nargin == 0 || ~isstruct(s)
    error('MATLAB:unpackStruct:inputError', 'Please provide input of type struct!')
end


% Input Parser
p = inputParser;

addParameter( p, 'tln',       false,      @(x) islogical(x) );
addParameter( p, 'tln_name',  char.empty, @(x) ischar(x) || isstring(x) );
addParameter( p, 'delimiter', '.',        @(x) ischar(x) || isstring(x) );

parse(p, varargin{:});


% Configuration
if p.Results.tln || ~isempty(p.Results.tln_name)
    if isempty(p.Results.tln_name)
        tln = inputname(1);
    else
        tln = p.Results.tln_name;
    end
else
    tln = char.empty;
end

delim = p.Results.delimiter;


% Processing
fieldpaths = {};
classes    = {};
sizes      = {};
values     = {};

fnames = fieldnames(s);

for idx = 1:numel(fnames)
    fname = fnames{idx};
    
    if isa(s.(fname), 'struct')
        [fieldpaths_temp, classes_temp, sizes_temp, values_temp] = unpackStruct(s.(fname), 'delimiter', delim);
        
        % Alternative to cellfun
        % fields_temp = strcat(fname, sep, fieldpaths_temp);
        
        if isempty(tln)
            fieldpaths_temp = cellfun(@(x) [fname delim x],           fieldpaths_temp, 'UniformOutput', false);
        else
            fieldpaths_temp = cellfun(@(x) [tln delim fname delim x], fieldpaths_temp, 'UniformOutput', false);
        end
    else
        if isempty(tln)
            fieldpaths_temp = {fname};
        else
            fieldpaths_temp = {[tln delim fname]};
        end
        classes_temp = {class(s.(fname))};
        sizes_temp   = size(s.(fname));
        values_temp  = s.(fname);
    end
    if isempty(values_temp)
        error('Empty variables are not allowed.');
    end
    fieldpaths = [fieldpaths; fieldpaths_temp];
    classes    = [classes; classes_temp];
    sizes      = [sizes; sizes_temp];
    values     = [values; values_temp];
end

end
