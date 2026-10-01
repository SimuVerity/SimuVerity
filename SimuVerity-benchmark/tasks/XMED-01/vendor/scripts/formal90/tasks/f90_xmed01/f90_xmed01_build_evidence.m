function facts=f90_xmed01_build_evidence(runs,spec)
local_bind("xp9_score_xmed01", ...
    "present");
emptyRow=local_handle("xp9_score_xmed01","empty_row");
measureRun=local_handle("xp9_score_xmed01","measure_run");
futureCausal=local_handle("xp9_score_xmed01","future_valve_causality");
sharedLeak=local_handle("xp9_score_xmed01","shared_leak_evidence");
sharedAirway=local_handle("xp9_score_xmed01","shared_airway_evidence");
alignedMargin=local_handle("xp9_score_xmed01","aligned_actuator_role_margin");
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index));
    allValid=allValid&&rows(index).valid;
end
[causalError,causalFit]=futureCausal(runs);
leakEvidence=sharedLeak(rows);airwayEvidence=sharedAirway(runs);
actuatorMargin=NaN;
if ~isempty(rows)
    actuatorMargin=alignedMargin(runs(1),causalFit.selected_delay_seconds);
end
valid=allValid&&numel(runs)==1+numel(spec.scenarios);
reasons=strings(0,1);
if ~valid,reasons="SCENARIO_OR_OUTPUT_CONTRACT_INVALID";end
facts=struct('score_inputs_valid',valid,'diagnostics_valid',allValid, ...
    'gate_reasons',reasons,'scenario_rows',rows, ...
    'causal_error',causalError,'causal_fit',causalFit, ...
    'leak_evidence',leakEvidence,'airway_evidence',airwayEvidence, ...
    'aligned_actuator_margin',actuatorMargin);
end
function h=local_handle(~,name),h=@(varargin)f90_xmed01_measurement_compat(name,varargin{:});end
function local_bind(name,expected)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
assert(strcmpi(xp9_file_presence_file(path),expected),'SOURCE_MEASUREMENT_BINDING_MISMATCH');
end
