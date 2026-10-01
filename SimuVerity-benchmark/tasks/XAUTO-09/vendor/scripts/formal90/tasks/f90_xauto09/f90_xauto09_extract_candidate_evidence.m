function evidence = f90_xauto09_extract_candidate_evidence(modelPath, outputDir)
%F90_XAUTO09_EXTRACT_CANDIDATE_EVIDENCE_CORE_CORE Add mechanism-specific structure proof.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
end

evidence = f90_xauto09_extract_candidate_evidence_core(modelPath, outputDir);
loadedHere = false; model = "";
try
    [~, candidateName] = fileparts(modelPath);
    loadedHere = ~bdIsLoaded(candidateName);
    handle = load_system(modelPath);
    model = string(get_param(handle,"Name"));
    audit = f90_xauto09_structure_policy(model, [ ...
        "ego_acceleration"; "ego_velocity"; "driver_set_velocity"; ...
        "relative_distance"; "relative_velocity"; "lateral_deviation"; ...
        "relative_yaw_angle"; "steering_angle"; "collision"]);
catch error
    audit = localFailedAudit(error);
end
if loadedHere && strlength(model) > 0
    try, close_system(model,0); catch, end
end

evidence.static_audit = audit;
evidence.structure = audit;
evidence.structure_policy_id = "f90_xauto09_structure_policy";
evidence.structure_evidence_complete = audit.audit_complete;
evidence.EVIDENCE_COMPLETE = evidence.EVIDENCE_COMPLETE && audit.audit_complete;
evidence.evidence_complete = evidence.EVIDENCE_COMPLETE;
localWriteJson(fullfile(outputDir,"evidence.json"),evidence);
end

function audit = localFailedAudit(error)
audit = struct( ...
    "schema","simuverity.f90-xauto09-structure-audit.v1", ...
    "policy_id","f90_xauto09_structure_policy", ...
    "audit_complete",false, ...
    "radar_and_vision_detection_path",false, ...
    "multi_object_fusion_and_lead_selection",false, ...
    "detected_lane_center_estimation",false, ...
    "coupled_longitudinal_lateral_mpc",false, ...
    "finite_mass_vehicle_dynamics",false, ...
    "closed_sensor_control_vehicle_loop",false, ...
    "native_fusion_derived_range_rate_logs",false, ...
    "native_lane_derived_lateral_yaw_logs",false, ...
    "failure_identifier",string(error.identifier), ...
    "failure_message",string(error.message));
end

function localWriteJson(path,value)
temporary=string(path)+".staging-"+string(java.util.UUID.randomUUID);
fid=fopen(temporary,"w","n","UTF-8");
assert(fid>=0,"SimuVerity:F90:XAUTO09:Write","Cannot write candidate evidence.");
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,PrettyPrint=true),"char");clear cleanup
assert(movefile(temporary,path,"f"),"SimuVerity:F90:XAUTO09:Publish", ...
    "Cannot publish candidate evidence.");
end
