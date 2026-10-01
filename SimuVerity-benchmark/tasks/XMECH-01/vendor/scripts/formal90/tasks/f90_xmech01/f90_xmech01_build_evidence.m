function facts=f90_xmech01_build_evidence(runs,spec)
%F90_XMECH01_BUILD_EVIDENCE Add the fixed binding-probe pair contract.
local_bind("f90_xmech01_measurement_compat", ...
    "present");
local_bind("f90_xmech01_fixed_probe_pair", ...
    "present");
emptyRow=local_handle("empty_row");measureRun=local_handle("measure_run");
measureSuite=local_handle("measure_suite");
coreContact=local_handle("core_vehicle_contact_present");
coreEvent=local_handle("core_traction_event_present");
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index));
    allValid=allValid&&rows(index).valid;
end
suite=measureSuite(runs,rows);
suite.core_vehicle_contact=coreContact(suite);
suite.core_traction_event=coreEvent(rows,suite);
suite.fixed_probe_pair=f90_xmech01_fixed_probe_pair(runs);
suite.valid=suite.valid&&suite.fixed_probe_pair.valid;

scenarioContractValid=allValid&&numel(runs)==1+numel(spec.scenarios);
valid=scenarioContractValid&&suite.fixed_probe_pair.valid;
reasons=strings(0,1);
if ~scenarioContractValid
    reasons(end+1)="SCENARIO_OR_PHYSICAL_OUTPUT_CONTRACT_INVALID"; %#ok<AGROW>
end
if ~suite.fixed_probe_pair.valid
    reason=string(suite.fixed_probe_pair.failure_reason);
    if strlength(reason)==0
        reason="FIXED_TRACTION_BINDING_PROBE_PAIR_MISSING_OR_INVALID";
    end
    reasons(end+1)=reason; %#ok<AGROW>
end
facts=struct( ...
    'score_inputs_valid',valid, ...
    'diagnostics_valid',valid&&suite.valid, ...
    'gate_reasons',unique(reasons,'stable'), ...
    'scenario_rows',rows, ...
    'suite_metrics',suite);
end

function handle=local_handle(name)
handle=@(varargin)f90_xmech01_measurement_compat(name,varargin{:});
end

function local_bind(name,expected)
path=string(which(char(name)));
assert(strlength(path)>0,'XMECH01_SUCCESSOR_DEPENDENCY_MISSING:%s',name);
assert(strcmpi(xp9_file_presence_file(path),expected), ...
    'XMECH01_SUCCESSOR_DEPENDENCY_BINDING_MISMATCH:%s',name);
end
