function [modelPath, bundleVerified] = f90_xmech02_build_reference
%F90_XMECH02_BUILD_REFERENCE Locate the bundled public reference model.
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
subject = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
assert(subject == "reference" && isfolder(taskRoot) && isfolder(runtimeRoot), ...
    "SimuVerity:F90:XMECH02:ReferenceRuntime", ...
    "The reference run requires its task and runtime directories.");

sourceRoot = fullfile(runtimeRoot, "Simscape-Wind-Turbine");
projectPath = fullfile(sourceRoot, "Wind_Turbine.prj");
modelPath = fullfile(sourceRoot, "Wind_Turbine.slx");
licensePath = fullfile(sourceRoot, "LICENSE.md");
bundleVerified = isfolder(sourceRoot) && isfile(projectPath) && ...
    isfile(modelPath) && isfile(licensePath);
assert(bundleVerified, "SimuVerity:F90:XMECH02:DirectReferenceMissing", ...
    "The bundled reference project is incomplete.");
end
