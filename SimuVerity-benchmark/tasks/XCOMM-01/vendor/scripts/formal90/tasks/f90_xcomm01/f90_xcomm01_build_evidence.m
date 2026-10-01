function facts=f90_xcomm01_build_evidence(runs,spec)
local_bind("xp9_score_xcomm01", ...
    "present");
selectConvention=local_handle("xp9_score_xcomm01","select_spectral_convention");
emptyRow=local_handle("xp9_score_xcomm01","empty_row");
measureRun=local_handle("xp9_score_xcomm01","measure_run");
interference=local_handle("xp9_score_xcomm01","interference_suite");
rcsProbeFn=local_handle("xp9_score_xcomm01","rcs_probe_suite");
inputProbeFn=local_handle("xp9_score_xcomm01","input_probe_suite");
reportFn=local_handle("xp9_score_xcomm01","report_consistency_suite");
dependencyReasons=local_handle("xp9_score_xcomm01","dependency_gate_reasons");
convention=selectConvention(runs);
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index),convention);
    allValid=allValid&&rows(index).valid;
end
suite=interference(rows);rcsProbe=rcsProbeFn(rows);inputProbe=inputProbeFn(rows);
reportSuite=reportFn(rows);
suite.rcs_probe=rcsProbe;suite.input_probe=inputProbe;
suite.report_consistency=reportSuite;suite.spectral_convention=convention;
valid=allValid&&numel(runs)==1+numel(spec.scenarios);
reasons=strings(0,1);
if ~valid
    reasons=dependencyReasons(runs);
    if isempty(reasons),reasons="SCENARIO_OR_RADAR_OUTPUT_CONTRACT_INVALID";end
end
facts=struct('score_inputs_valid',valid,'diagnostics_valid',allValid, ...
    'gate_reasons',reasons,'scenario_rows',rows,'suite_metrics',suite, ...
    'rcs_probe',rcsProbe,'input_probe',inputProbe, ...
    'report_consistency',reportSuite,'spectral_convention',convention);
end
function h=local_handle(~,name),h=@(varargin)f90_xcomm01_measurement_compat(name,varargin{:});end
function local_bind(name,expected)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
assert(strcmpi(xp9_file_presence_file(path),expected),'SOURCE_MEASUREMENT_BINDING_MISMATCH');
end
