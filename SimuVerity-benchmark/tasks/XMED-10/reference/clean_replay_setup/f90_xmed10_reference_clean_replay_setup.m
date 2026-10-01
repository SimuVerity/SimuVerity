function f90_xmed10_reference_clean_replay_setup(taskId, officialScenariosPath)
% The current setup keeps the native variables and selects the evaluator-provided Python runtime.
f90_xmed10_reference_clean_replay_core(taskId, officialScenariosPath);
referenceRoot = fileparts(fileparts(mfilename("fullpath")));
pythonSource = string(fullfile(referenceRoot, "files", "source", "src"));
assert(isfolder(pythonSource), "SimuVerity:ReferenceSetup:PythonSource", ...
    "Retained Python source is missing: %s", pythonSource);
pythonExe = string(getenv("SIMUVERITY_F90_XMED10_PYTHON_EXE"));
assert(strlength(pythonExe) > 0 && isfile(pythonExe), ...
    "SimuVerity:ReferenceSetup:PythonRuntime", ...
    "SIMUVERITY_F90_XMED10_PYTHON_EXE must identify the isolated Python runtime.");
oldPythonPath = string(getenv("PYTHONPATH"));
if strlength(oldPythonPath) > 0
    setenv("PYTHONPATH", pythonSource + pathsep + oldPythonPath);
else
    setenv("PYTHONPATH", pythonSource);
end
pe = pyenv;
if pe.Status == "Loaded", terminate(pe); end
pyenv("Version", pythonExe, "ExecutionMode", "OutOfProcess");
if double(py.sys.path().count(pythonSource)) == 0
    py.sys.path().insert(int32(0), pythonSource);
end
py.importlib.import_module("python_anesthesia_simulator.simulator");
end
