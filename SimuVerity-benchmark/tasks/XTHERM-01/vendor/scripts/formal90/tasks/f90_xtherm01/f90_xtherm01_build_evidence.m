function facts=f90_xtherm01_build_evidence(runs,spec)
projectRoot=fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename('fullpath'))))));
addpath(fullfile(projectRoot,'scripts','harder_thermal_pilot', ...
    'xtherm02','scorers'),'-begin');
local_bind("htp_score_xtherm02", ...
    "present");
emptyRow=local_handle("htp_score_xtherm02","empty_row");
measureRun=local_handle("htp_score_xtherm02","measure_run");
measureSuite=local_handle("htp_score_xtherm02","measure_suite");
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index),spec);
    allValid=allValid&&rows(index).valid;
end
suite=measureSuite(runs,rows);
valid=allValid&&numel(runs)==1+numel(spec.scenarios);
reasons=strings(0,1);
if ~valid,reasons="SCENARIO_OR_COMPLETE_TIMESERIES_CONTRACT_INVALID";end
facts=struct('score_inputs_valid',valid, ...
    'diagnostics_valid',valid&&suite.valid,'gate_reasons',reasons, ...
    'scenario_rows',rows,'suite_metrics',suite);
end
function h=local_handle(~,name),h=@(varargin)f90_xtherm01_measurement_compatibility(name,varargin{:});end
function local_bind(name,expected)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
assert(strcmpi(xp9_file_presence_file(path),expected),'SOURCE_MEASUREMENT_BINDING_MISMATCH');
end
