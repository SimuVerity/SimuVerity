function f90_xmed10_reference_clean_replay_core(taskId, officialScenariosPath)
arguments
    taskId (1,1) string
    officialScenariosPath (1,1) string
end
assert(taskId == "F90-XMED-10", "SimuVerity:ReferenceSetup:TaskMismatch", "Task mismatch.");
assert(lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference", ...
    "SimuVerity:ReferenceSetup:SubjectMismatch", "Reference only.");
document = jsondecode(fileread(officialScenariosPath));
assert(string(document.task_id) == taskId && isfield(document, "scenarios"), ...
    "SimuVerity:ReferenceSetup:ScenarioContract", "Scenario contract mismatch.");
rows = document.scenarios;
assert(any(string({rows.id}) == "nominal_adult_target50"), ...
    "SimuVerity:ReferenceSetup:NominalScenarioMissing", "Nominal scenario missing.");
% Values below are the native main_sim_closedloop.m initialization contract.
assignin("base", "simulation_time", 900);
assignin("base", "age", 18);
assignin("base", "height", 170);
assignin("base", "weight", 60);
assignin("base", "sex", 0);
assignin("base", "sampling_time", 1);
assignin("base", "Kp", 0.0286);
assignin("base", "Ti", 206.98);
assignin("base", "Td", 29.83);
assignin("base", "Ts", 5);
assignin("base", "N", 5);
assignin("base", "ratio", 2);
assignin("base", "uref_p", 0);
assignin("base", "uref_r", 0);
assignin("base", "sat_pos_p", 6.67);
assignin("base", "sat_neg_p", 0);
assignin("base", "sat_pos_r", 16.67);
assignin("base", "sat_neg_r", 0);
end
