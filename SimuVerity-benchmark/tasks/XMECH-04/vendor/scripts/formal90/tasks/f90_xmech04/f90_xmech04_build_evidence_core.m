function facts=f90_xmech04_build_evidence_core(runs,spec)
local_bind("xp9_score_xmech04");
emptyRow=local_handle("xp9_score_xmech04","empty_row");
measureRun=local_handle("xp9_score_xmech04","measure_run");
measurePair=local_handle("xp9_score_xmech04","measure_pair");
rows=repmat(emptyRow(),numel(runs),1);allValid=true;
for index=1:numel(runs)
    rows(index)=measureRun(runs(index));
    allValid=allValid&&rows(index).valid;
end
pair=measurePair(runs,rows,"heavy_corner","heavy_corner_no_disturbance");
valid=allValid&&numel(runs)==1+numel(spec.scenarios);
reasons=strings(0,1);
if ~valid,reasons="SCENARIO_OR_PHYSICAL_OUTPUT_CONTRACT_INVALID";end
facts=struct('score_inputs_valid',valid,'diagnostics_valid',valid, ...
    'gate_reasons',reasons,'scenario_rows',rows,'pair_metrics',pair);
end
function h=local_handle(~,name),h=@(varargin)f90_xmech04_measurement_compatibility(name,varargin{:});end
function local_bind(name)
path=string(which(char(name)));assert(strlength(path)>0,'SOURCE_MEASUREMENT_MISSING');
end
