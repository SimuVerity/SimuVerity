function facts=f90_xfluid01_build_evidence(runs,spec)
local_bind("xp9_score_xfluid01", ...
    "present");
emptyRow=local_handle("empty_row");measureRun=local_handle("measure_run");
measureSuite=local_handle("measure_suite");corePath=local_handle("core_hydraulic_path_present");
coreEvent=local_handle("core_leak_event_present");
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index));allValid=allValid&&rows(index).valid;
end
suite=measureSuite(runs,rows);suite.core_hydraulic_path=corePath(suite,rows);
suite.core_leak_event=coreEvent(suite,rows);
valid=allValid&&numel(runs)==1+numel(spec.scenarios);reasons=strings(0,1);
if ~valid,reasons="SCENARIO_OR_HYDRAULIC_OUTPUT_CONTRACT_INVALID";end
facts=struct('score_inputs_valid',valid,'diagnostics_valid',valid&&suite.valid, ...
    'gate_reasons',reasons,'scenario_rows',rows,'suite_metrics',suite);
end
function h=local_handle(name)
h=@(varargin)f90_xfluid01_measurement_compat(name,varargin{:});
end
function local_bind(name,expected)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
assert(strcmpi(xp9_file_presence_file(path),expected),'SOURCE_MEASUREMENT_BINDING_MISMATCH');
end
