function value = simuverity_official_scenarios_path()
%SIMUVERITY_OFFICIAL_SCENARIOS_PATH Resolve the public scenario contract.
value = string(getenv("SIMUVERITY_OFFICIAL_SCENARIOS"));
assert(strlength(value) > 0 && isfile(value), ...
    "SimuVerity:Extractor:OfficialScenariosMissing", ...
    "The task-local official_scenarios.json file is unavailable.");
end
