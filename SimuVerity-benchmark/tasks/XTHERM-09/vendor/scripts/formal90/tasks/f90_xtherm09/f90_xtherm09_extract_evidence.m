function evidence = f90_xtherm09_extract_evidence(modelFile, outFile, generationRunId)
%F90_XTHERM09_EXTRACT_EVIDENCE One-session dual-adapter evidence extraction.
% The exact golden uses non-invasive native signal taps. Other models must
% satisfy the public base-workspace input and Timeseries output contract.
if nargin < 3, generationRunId = "manual"; end
def = f90_xtherm09_definition;
modelFile = string(modelFile);
[~,model] = fileparts(modelFile);
evaluationSubject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(evaluationSubject) == 0, evaluationSubject = "candidate"; end
assert(any(evaluationSubject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XTHERM09:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
isReference = evaluationSubject == "reference" && ...
    strcmpi(file_file_presence(modelFile), def.reference_file_presence);
if evaluationSubject == "reference"
    assert(isReference, "SimuVerity:F90:XTHERM09:ReferenceIdentity", ...
        "Reference-subject model file presence differs from the task binding.");
end
evidence = struct("schema","simuverity.f90-xtherm09-evidence.v1", ...
    "task_id",def.formal_id,"load_pass",false,"update_pass",false, ...
    "compile_pass",false,"scenarios",[],"static_audit",struct, ...
    "runtime",struct("generation_run_id",string(generationRunId),"matlab_start_count",1, ...
    "adapter",ternary(isReference,"reference_native","candidate_public")));
try
    load_system(modelFile); evidence.load_pass = true;
    if isReference, install_native_logging(model); end
    set_param(model,"SimulationCommand","update"); evidence.update_pass = true;
    feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    evidence.compile_pass = true;
    evidence.static_audit = audit_model(model,isReference);
    rows = repmat(struct,0,1);
    for k = 1:numel(def.scenarios)
        s = def.scenarios(k);
        apply_inputs(model,s,isReference);
        in = Simulink.SimulationInput(model);
        in = in.setModelParameter("StartTime","0","StopTime","6000", ...
            "SignalLogging","on","SignalLoggingName","logsout", ...
            "ReturnWorkspaceOutputs","on");
        out = sim(in);
        row = collect_row(out,s,def.output_names,isReference);
        if k == 1
            rows = row;
        else
            rows(end+1,1) = row; %#ok<AGROW>
        end
    end
    evidence.scenarios = rows;
catch ME
    evidence.error = struct("identifier",string(ME.identifier), ...
        "message",string(ME.message));
    try, feval(model,[],[],[],"term"); catch, end
end
try, close_system(model,0); catch, end
fid = fopen(outFile,"w");
assert(fid >= 0,"SimuVerity:F90:XTHERM09:EvidenceWrite","Cannot open evidence output.");
cleaner = onCleanup(@() fclose(fid));
fwrite(fid,jsonencode(evidence,PrettyPrint=true),"char");
end

function apply_inputs(model,s,isReference)
names = ["PassengerCount","EquipmentHeat_W","BleedPressure_kPa", ...
    "BleedTemperature_degC","OzoneRemovalFraction"];
for n = names
    assignin("base",n,s.(n));
end
if ~isReference, return, end
set_param(unique_named(model,"Thermal & Moisture Loads"), ...
    "N_passenger",num2str(s.PassengerCount,17), ...
    "Q_equipment",num2str(s.EquipmentHeat_W,17));
set_param(unique_named(model,"Engine Bleed Air"), ...
    "p_bleed",num2str(s.BleedPressure_kPa,17), ...
    "T_bleed",num2str(s.BleedTemperature_degC,17));
set_param(unique_named(model,"Catalytic Converter"), ...
    "removal_rate",num2str(s.OzoneRemovalFraction,17));
end

function install_native_logging(model)
spec = {
    "Scope Data/From",1,"cabin_pressure";
    "Scope Data/From1",1,"atmospheric_pressure";
    "Scope Data/From2",1,"cabin_temperature";
    "Scope Data/From3",1,"atmospheric_temperature";
    "Scope Data/From4",1,"cabin_relative_humidity";
    "Scope Data/From5",1,"atmospheric_relative_humidity";
    "Scope Data/From6",1,"cabin_ozone_ppm";
    "Scope Data/From7",1,"atmospheric_ozone_ppm";
    "Controllers/From",1,"acm_mass_flow";
    "Controllers/From1",1,"turbine_outlet_temperature";
    "Controllers/Transfer Fcn",1,"flow_valve_area";
    "Controllers/Transfer Fcn1",1,"bypass_valve_area";
    "Controllers/Transfer Fcn2",1,"trim_valve_area";
    "Controllers/Transfer Fcn3",1,"outflow_valve_area"};
for k = 1:size(spec,1)
    path = unique_suffix(model,spec{k,1});
    ph = get_param(path,"PortHandles");
    line = get_param(ph.Outport(spec{k,2}),"Line");
    assert(line ~= -1,"SimuVerity:F90:XTHERM09:MissingLine","Missing native signal line: %s",path);
    set_param(ph.Outport(spec{k,2}),"DataLogging","on", ...
        "DataLoggingNameMode","Custom", ...
        "DataLoggingName",spec{k,3});
end
end

function row = collect_row(out,s,names,isReference)
row = struct("id",string(s.id),"requested_inputs",s,"valid",false, ...
    "time_s",[],"outputs",struct,"failure_reason","");
try
    firstTime = [];
    for name = names
        if isReference
            ds = out.logsout;
            value = ds.getElement(char(name)).Values;
        else
            value = simuverity_public_output_compatibility( ...
                out,name,1,AllowBaseWorkspace=true);
        end
        assert(isa(value,"timeseries"),"SimuVerity:F90:XTHERM09:NotTimeseries", ...
            "%s is not a Timeseries.",name);
        t = double(value.Time(:)); y = double(value.Data);
        if size(y,1) ~= numel(t), y = reshape(y,numel(t),[]); end
        assert(size(y,2)==1 && all(isfinite(t)) && all(isfinite(y),"all"), ...
            "SimuVerity:F90:XTHERM09:BadSignal","%s is not finite scalar evidence.",name);
        idx = unique(round(linspace(1,numel(t),min(numel(t),2001))));
        if isempty(firstTime), firstTime=t(idx); end
        row.outputs.(name) = y(idx,1);
    end
    row.time_s = firstTime;
    row.valid = numel(firstTime)>=20 && firstTime(1)<=1e-6 && firstTime(end)>=5999;
    if ~row.valid, row.failure_reason = "incomplete mission interval"; end
catch ME
    row.failure_reason = string(ME.message);
end
end

function audit = audit_model(model,isReference)
blocks = find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");
text = lower(string(blocks));
src = strings(size(text));
for k=1:numel(blocks)
    try, src(k)=lower(string(get_param(blocks{k},"SourceBlock"))); catch, end
end
allText = text+" "+src;
topBlocks = find_system(model,"SearchDepth",1,"Type","Block");
if ~isempty(topBlocks) && strcmp(topBlocks{1},model), topBlocks(1)=[]; end
topText = lower(regexprep(string(topBlocks),"\s+"," "));
audit = struct;
audit.compressor_present = any(contains(allText,"compressor"));
audit.turbine_present = any(contains(allText,"turbine"));
audit.heat_exchanger_count = sum(contains(topText,"heat exchanger"));
audit.moist_air_path_present = any(contains(allText,"moist air"));
audit.cabin_volume_present = any(contains(allText,["constant volume","chamber"]));
audit.valve_count = sum(contains(allText,["valve","restriction"]));
audit.feedback_controller_count = sum(contains(allText,["pid controller","controller"]));
audit.reference_native_adapter = isReference;
audit.core_path_qualified = audit.compressor_present && audit.turbine_present && ...
    audit.heat_exchanger_count>=2 && audit.moist_air_path_present && ...
    audit.cabin_volume_present && audit.valve_count>=3 && ...
    audit.feedback_controller_count>=2;
end

function path = unique_named(model,name)
hits = find_system(model,"SearchDepth",1,"Type","Block");
if ~isempty(hits) && strcmp(hits{1},model), hits(1)=[]; end
actual = strings(size(hits));
for k = 1:numel(hits)
    actual(k) = string(get_param(hits{k},"Name"));
end
normalize = @(value) regexprep(strtrim(string(value)),"\s+"," ");
hits = hits(normalize(actual) == normalize(name));
assert(numel(hits)==1,"SimuVerity:F90:XTHERM09:Locator","Expected one top-level %s.",name);
path = hits{1};
end

function path = unique_suffix(model,suffix)
hits = find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");
hits = hits(endsWith(string(hits),"/"+string(suffix)));
assert(numel(hits)==1,"SimuVerity:F90:XTHERM09:Locator","Expected one semantic path suffix %s.",suffix);
path = hits{1};
end

function h = file_file_presence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
h = "present";
end

function value = ternary(test,a,b)
if test, value=a; else, value=b; end
end
