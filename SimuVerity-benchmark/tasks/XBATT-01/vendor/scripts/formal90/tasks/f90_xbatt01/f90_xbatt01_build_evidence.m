function facts=f90_xbatt01_build_evidence(runs,spec)
local_bind("xp9_score_xbatt01", ...
    "present");
emptyRow=local_handle("xp9_score_xbatt01","empty_row");
measureRun=local_handle("xp9_score_xbatt01","measure_run");
sharedPack=local_handle("xp9_score_xbatt01","shared_pack_evidence");
faultPair=local_handle("xp9_score_xbatt01","fault_pair_evidence");
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index));
    allValid=allValid&&rows(index).valid;
end
[spreadEvidence,coolingEvidence]=sharedPack(runs,rows);
faultEvidence=faultPair(runs,"nominal","fault_pair_none");
controlEvidence=faultPair(runs,"warm_spread","warm_spread_fault_pair_none");
valid=allValid&&numel(runs)==1+numel(spec.scenarios);
reasons=strings(0,1);
if ~valid,reasons="SCENARIO_OR_ELECTRO_THERMAL_OUTPUT_CONTRACT_INVALID";end
facts=struct('score_inputs_valid',valid,'diagnostics_valid',allValid, ...
    'gate_reasons',reasons,'scenario_rows',rows, ...
    'spread_evidence',spreadEvidence,'cooling_evidence',coolingEvidence, ...
    'fault_evidence',faultEvidence,'control_evidence',controlEvidence);
end
function h=local_handle(~,name),h=@(varargin)f90_xbatt01_measurement_compat(name,varargin{:});end
function local_bind(name,expected)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
assert(strcmpi(xp9_file_presence_file(path),expected),'SOURCE_MEASUREMENT_BINDING_MISMATCH');
end
