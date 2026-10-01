function modelPath = f90_xaero03_build_reference()
%F90_XAERO03_BUILD_REFERENCE Return the already-current reference.
%
% CURRENT does not rebuild or retune a current reference.
root = localProjectRoot();
modelPath = fullfile(getenv("SIMUVERITY_TASK_ROOT"), "reference", "files", "XAERO03_reference.slx");
assert(isfile(modelPath), "SimuVerity:F90:XAERO03:CurrentReferenceMissing", ...
    "Current reference is missing: %s", modelPath);
fprintf("F90_XAERO03_CURRENT_REFERENCE path=%s\n", modelPath);
end

function root = localProjectRoot()
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
