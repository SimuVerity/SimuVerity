function value = xp9_file_presence_file(pathValue)
%XP9_FILE_PRESENCE_FILE Validate a declared public dependency path.
assert(isfile(pathValue), "SimuVerity:FileMissing", ...
    "Required file is missing: %s", pathValue);
value = "present";
end
