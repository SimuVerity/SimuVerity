function facts=f90_xauto01_build_evidence(runs,spec)
local_bind("xp9_score_xauto01", ...
    "present");
selectSlip=local_handle("xp9_score_xauto01","select_slip_orientation");
sharedDynamics=local_handle("xp9_score_xauto01","shared_vehicle_dynamics");
brakeDemand=local_handle("xp9_score_xauto01","brake_demand_probe");
emptyRow=local_handle("xp9_score_xauto01","empty_row");
measureRun=local_handle("xp9_score_xauto01","measure_run");
[slipSign,slipOrientation]=selectSlip(runs);
[suite,forceSign,brakeSign]=sharedDynamics(runs);
brakeProbe=brakeDemand(runs);suite.brake_demand_probe=brakeProbe;
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index),slipSign,forceSign,brakeSign);
    allValid=allValid&&rows(index).valid;
end
valid=allValid&&numel(runs)==1+numel(spec.scenarios);
reasons=strings(0,1);
if ~valid,reasons="SCENARIO_OR_PHYSICAL_OUTPUT_CONTRACT_INVALID";end
facts=struct('score_inputs_valid',valid,'diagnostics_valid',allValid, ...
    'gate_reasons',reasons,'scenario_rows',rows,'suite_metrics',suite, ...
    'slip_orientation',slipOrientation,'brake_probe',brakeProbe);
end
function h=local_handle(~,name),h=@(varargin)f90_xauto01_measurement_compat(name,varargin{:});end
function local_bind(name,expected)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
assert(strcmpi(xp9_file_presence_file(path),expected),'SOURCE_MEASUREMENT_BINDING_MISMATCH');
end
