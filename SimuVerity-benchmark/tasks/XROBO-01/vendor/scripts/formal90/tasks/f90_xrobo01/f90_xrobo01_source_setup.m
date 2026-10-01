function paths = f90_xrobo01_source_setup
%F90_XROBO01_SOURCE_SETUP Add only the bundled source dependency paths.
% Deliberately excludes the upstream work/slprj tree so generated helper
% files cannot shadow MATLAB built-ins.

taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
sourceRoot = fullfile(taskRoot, "reference", "files");
paths = struct;
paths.root = sourceRoot;
paths.model = fullfile(sourceRoot, "sm_robot_run_4legs.slx");
paths.param_mat = fullfile(sourceRoot, "sm_robot_run_4legs_param_def.mat");
paths.library = fullfile(sourceRoot, "sm_robot_run_4legs_lib.slx");
paths.contact_library = fullfile(sourceRoot, "Contact_Forces_Lib.slx");

addpath(sourceRoot);
end
