function evidence = f90_xtherm11_extract_candidate_evidence(modelPath,outputDir,evaluationMode)
%f90_xtherm11_extract_candidate_evidence Integrity-only extraction.
% METRICS simulations and score-free metrics are retained.  Its structure and
% performance thresholds no longer decide whether Unified may lock the
% complete evidence; those observations are consumed by the offline scorer.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
    evaluationMode (1,1) string {mustBeMember(evaluationMode,["candidate","reference"])} = "candidate"
end
evidence=f90_xtherm11_extract_reference_evidence(modelPath,outputDir,evaluationMode);
source=false;
if isfield(evidence,"EVIDENCE_COMPLETE")
    source=logical(evidence.EVIDENCE_COMPLETE);
    evidence=rmfield(evidence,"EVIDENCE_COMPLETE");
end
[passed,gate]=localIntegrity(evidence);
evidence.schema="simuverity.f90-xtherm11-evidence.v1";
evidence.source_task_evidence_complete=source;
evidence.task_evidence_integrity=gate;
evidence.score_inputs_valid=passed;evidence.diagnostics_valid=passed;
evidence.platform_valid=passed;evidence.evidence_freeze_candidate=passed;
evidence.extraction_only=true;evidence.contains_score_decisions=false;
evidence.evidence_lock_authority="Unified outer evidence_lock.json";
localWrite(fullfile(outputDir,"evidence.json"),evidence);
end

function [passed,gate]=localIntegrity(evidence)
ids=["nominal","elevated_targets_and_feed","feed_concentration_depletion", ...
    "hot_feed_ramp","warm_coolant_ramp","mild_catalyst_and_fouling"];
runtime=localTrue(evidence,"load_pass")&&localTrue(evidence,"update_pass")&& ...
    localTrue(evidence,"compile_pass")&&localTrue(evidence,"nominal_smoke_pass");
actual=strings(0,1);
if isfield(evidence,"scenarios")&&isstruct(evidence.scenarios)&& ...
        isfield(evidence.scenarios,"id"),actual=string({evidence.scenarios.id}).';end
exact=numel(actual)==numel(ids)&&numel(unique(actual))==numel(ids)&&all(ismember(ids,actual));
simulation=exact;contract=exact;artifacts=exact;
if exact
    for id=ids
        row=evidence.scenarios(find(actual==id,1));
        simulation=simulation&&localTrue(row,"simulation_pass")&&localTrue(row,"valid");
        contract=contract&&isfield(row,"output_contract")&&localAllTrue(row.output_contract);
        artifacts=artifacts&&strlength(localString(row,"complete_signal_artifact"))>0&& ...
            strlength(localString(row,"complete_signal_file_presence"))>0;
    end
end
identity=strcmpi(localString(evidence,"evaluation_subject"),"candidate")|| ...
    localTrue(evidence,"reference_binding_preserved");
passed=runtime&&simulation&&contract&&artifacts&&identity;
gate=struct("schema","simuverity.f90-xtherm11-integrity.v1", ...
    "integrity_pass",passed,"load_update_compile_smoke",runtime, ...
    "exact_required_scenarios",exact,"all_simulations_valid",simulation, ...
    "all_output_contracts_complete",contract,"complete_artifacts_bindinged",artifacts, ...
    "candidate_or_reference_identity",identity, ...
    "structure_thresholds_used",false,"performance_thresholds_used",false, ...
    "outer_evidence_lock_required",true);
end
function value=localTrue(source,name)
value=isstruct(source)&&isfield(source,name)&&isscalar(source.(name))&&logical(source.(name));
end
function value=localString(source,name)
value="";if isstruct(source)&&isfield(source,name),value=string(source.(name));if ~isscalar(value),value="";end,end
end
function passed=localAllTrue(source)
passed=isstruct(source)&&~isempty(fieldnames(source));
if passed,values=struct2cell(source);passed=all(cellfun(@(v)isscalar(v)&&logical(v),values));end
end
function localWrite(path,value)
fid=fopen(path,"w","n","UTF-8");assert(fid>=0,"SimuVerity:F90:XTHERM11:EvidenceWrite");
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,"PrettyPrint",true),"char");
end
