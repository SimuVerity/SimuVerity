function evidence = f90_xauto07_extract_candidate_evidence(modelPath, outputDir)
%F90_XAUTO07_EXTRACT_CANDIDATE_EVIDENCE_CORE_CORE Add mechanism-specific structure proof.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
end

% Preserve the validated simulation/output extraction path.  The structure-audit step
% replaces only the unsound generic structural classification before evidence is
% returned to the outer evidence locker.
evidence = f90_xauto07_extract_candidate_evidence_core(modelPath, outputDir);
loadedHere = false;
model = "";
try
    [~, candidateName] = fileparts(modelPath);
    loadedHere = ~bdIsLoaded(candidateName);
    handle = load_system(modelPath);
    model = string(get_param(handle, "Name"));
    audit = f90_xauto07_structure_policy(model, ...
        ["driver_input"; "motor_torque"; "phase_currents"; "vehicle_speed"]);
catch error
    audit = localFailedAudit(error);
end
if loadedHere && strlength(model) > 0
    try, close_system(model, 0); catch, end
end

evidence.static_audit = audit;
evidence.structure = audit;
evidence.structure_policy_id = "f90_xauto07_structure_policy";
evidence.structure_evidence_complete = audit.audit_complete;
evidence.EVIDENCE_COMPLETE = evidence.EVIDENCE_COMPLETE && audit.audit_complete;
evidence.evidence_complete = evidence.EVIDENCE_COMPLETE;
localWriteJson(fullfile(outputDir, "evidence.json"), evidence);
end

function audit = localFailedAudit(error)
audit = struct( ...
    "schema", "simuverity.f90-xauto07-structure-audit.v1", ...
    "policy_id", "f90_xauto07_structure_policy", ...
    "audit_complete", false, ...
    "battery_and_dc_link", false, ...
    "controlled_three_phase_converter", false, ...
    "interior_permanent_magnet_motor", false, ...
    "closed_loop_phase_current_control", false, ...
    "torque_reference_and_estimation", false, ...
    "fixed_ratio_gear_and_axle", false, ...
    "finite_mass_vehicle_dynamics", false, ...
    "closed_driver_drive_vehicle_feedback", false, ...
    "failure_identifier", string(error.identifier), ...
    "failure_message", string(error.message));
end

function localWriteJson(path, value)
temporary = string(path) + ".staging-" + string(java.util.UUID.randomUUID);
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAUTO07:Write", "Cannot write candidate evidence.");
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char"); clear cleanup
assert(movefile(temporary, path, "f"), "SimuVerity:F90:XAUTO07:Publish", ...
    "Cannot publish candidate evidence.");
end
