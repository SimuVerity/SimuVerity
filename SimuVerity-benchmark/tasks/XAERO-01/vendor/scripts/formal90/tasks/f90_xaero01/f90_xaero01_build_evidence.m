function facts=f90_xaero01_build_evidence(runs,spec)
local_bind("xp9_score_xaero01", ...
    "present");
emptyRow=local_handle("xp9_score_xaero01","empty_row");
measureRun=local_handle("xp9_score_xaero01","measure_run");
sharedFlight=local_handle("xp9_score_xaero01","shared_flight_evidence");
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index));
    allValid=allValid&&rows(index).valid;
end
[flightEvidence,angularEvidence,propulsionEvidence]=sharedFlight(runs);
valid=allValid&&numel(runs)==1+numel(spec.scenarios);
reasons=strings(0,1);
if ~valid,reasons="SCENARIO_OR_FLIGHT_PROPULSION_OUTPUT_CONTRACT_INVALID";end
facts=struct('score_inputs_valid',valid,'diagnostics_valid',allValid, ...
    'gate_reasons',reasons,'scenario_rows',rows, ...
    'flight_evidence',flightEvidence,'angular_evidence',angularEvidence, ...
    'propulsion_evidence',propulsionEvidence);
end
function h=local_handle(~,name),h=@(varargin)f90_xaero01_measurement_compat(name,varargin{:});end
function local_bind(name,expected)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
assert(strcmpi(xp9_file_presence_file(path),expected),'SOURCE_MEASUREMENT_BINDING_MISMATCH');
end
