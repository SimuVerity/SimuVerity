function report = transform(sourceDir, destinationDir)
%F90_XBATT_09_TRANSFORM Complete the official live-script tuning.
% The importer core deterministically reproduces the generated closure, but it
% stopped before the official live script applied its three documented
% Battery Cell Contact Monitoring tuning values and selected the validation
% current profile as the saved default. Apply exactly that source state to
% the already canonical SLX archive without changing topology or any private
% scenario/scorer input.
arguments
    sourceDir (1,1) string
    destinationDir (1,1) string
end

report = transform_core(sourceDir, destinationDir);
modelPath = fullfile(destinationDir, "disconnectedCellDetection.slx");
localApplyOfficialLiveScriptTuning(modelPath);
report.status = "OFFICIAL_EXAMPLE_GENERATION_COMPLETE_LIVE_SCRIPT_SEMANTICS";
report.official_live_script_completion = struct( ...
    "VoltageChangeDetectionThreshold", "1e-5", ...
    "VoltageChangePar", "0.015", ...
    "QualTime", "5", ...
    "VariableName", "batteryCurrentValidation");
report.semantic_basis = "R2025a DisconnectedCellDetectionExample.mlx";
end

function localApplyOfficialLiveScriptTuning(modelPath)
assert(isfile(modelPath), "SimuVerity:Importer:OfficialTuning", ...
    "Generated reference model is missing: %s", modelPath);
staging = string(tempname); mkdir(staging);
cleanup = onCleanup(@() localRemoveTree(staging)); %#ok<NASGU>
unzip(modelPath, staging);
systemPath = fullfile(staging, "simulink", "systems", "system_root.xml");
assert(isfile(systemPath), "SimuVerity:Importer:OfficialTuning", ...
    "Generated model system is missing: %s", systemPath);
text = fileread(systemPath);
rules = {
    "VoltageChangeDetectionThreshold", "1e-5";
    "VoltageChangePar", "0.015";
    "QualTime", "5";
    "VariableName", "batteryCurrentValidation"
    };
for index = 1:size(rules, 1)
    name = rules{index, 1};
    value = rules{index, 2};
    pattern = '(<P Name="' + name + '">)[^<]*(</P>)';
    assert(~isempty(regexp(text, pattern, "once")), ...
        "SimuVerity:Importer:OfficialTuning", ...
        "Official live-script parameter is missing: %s", name);
    text = regexprep(text, pattern, "$1" + value + "$2");
end
fid = fopen(systemPath, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:Importer:OfficialTuning", ...
    "Cannot rewrite generated model system: %s", systemPath);
fwrite(fid, text, "char"); fclose(fid);

files = dir(fullfile(staging, "**", "*")); files = files(~[files.isdir]);
relative = string(fullfile({files.folder}, {files.name}));
relative = erase(relative, staging + filesep); relative = sort(relative);
temporaryZip = string(tempname) + ".zip";
stream = javaObject("java.util.zip.ZipOutputStream", ...
    javaObject("java.io.FileOutputStream", char(temporaryZip)));
stream.setLevel(9); streamCleanup = onCleanup(@() localCloseZip(stream)); %#ok<NASGU>
for index = 1:numel(relative)
    entry = javaObject("java.util.zip.ZipEntry", ...
        char(replace(relative(index), "\", "/")));
    entry.setTime(0); stream.putNextEntry(entry);
    fid = fopen(fullfile(staging, relative(index)), "r");
    assert(fid >= 0, "SimuVerity:Importer:OfficialTuning", ...
        "Cannot read %s", relative(index));
    bytes = fread(fid, Inf, "*uint8"); fclose(fid);
    stream.write(typecast(bytes, "int8"), 0, numel(bytes));
    stream.closeEntry();
end
stream.close(); movefile(temporaryZip, modelPath, "f");
end

function localRemoveTree(pathValue)
if isfolder(pathValue), try, rmdir(pathValue, "s"); catch, end, end
end

function localCloseZip(stream)
try, stream.close(); catch, end
end
