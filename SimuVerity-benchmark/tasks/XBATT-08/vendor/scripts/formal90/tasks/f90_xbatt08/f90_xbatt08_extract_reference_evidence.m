function evidence = f90_xbatt08_extract_reference_evidence(modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
% Run the fixed F90-XBATT-08 reference and save complete, replayable evidence.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
sourceDir = evaluatorAssetRoot;
assert(isfile(modelPath),'SimuVerity:F90:XBATT08:ModelMissing','Reference model is missing.');
assert(isfile(officialScenarios),'SimuVerity:F90:XBATT08:OfficialScenarios','Official scenarios are missing.');
assert(isfolder(sourceDir),'SimuVerity:F90:XBATT08:ReferenceAssetRoot','Evaluator asset root is missing.');
official = jsondecode(fileread(officialScenarios));
expectedPresence = lower(strtrim(string('present')));
assert(strcmpi(localFilePresence(modelPath),expectedPresence),'SimuVerity:F90:XBATT08:ReferenceIdentity', ...
    'Reference file presence differs from the task binding.');
if ~exist(outputDir,'dir'), mkdir(outputDir); end
cacheDir = fullfile(outputDir,'cache');
codegenDir = fullfile(outputDir,'codegen');
if ~exist(cacheDir,'dir'), mkdir(cacheDir); end
if ~exist(codegenDir,'dir'), mkdir(codegenDir); end
Simulink.fileGenControl('set','CacheFolder',cacheDir,'CodeGenFolder',codegenDir,'createDir',true);
addpath(sourceDir);

mdl = '';
evidencePath = fullfile(outputDir,'evidence.json');
ev = struct('schema','simuverity.f90-xbatt08-evidence.v1','task_id','F90-XBATT-08', ...
    'scoring_run_id',getenv('SIMUVERITY_SCORING_RUN_ID'),'matlab_release',version('-release'), ...
    'source_model',modelPath,'source_model_file_presence',expectedPresence, ...
    'core_source_modifications',0,'load_update_compile_simulate',false,'evidence_complete',false, ...
    'current_phase','starting','error_identifier','','error_message','');
flush();
try
    ticSuite = tic;
    modelHandle = load_system(modelPath);
    mdl = char(string(get_param(modelHandle,'Name')));
    set_param(mdl,'SimulationCommand','update');
    eval([mdl '([],[],[],''compile'');']);
    eval([mdl '([],[],[],''term'');']);
    defs = official.scenarios;
    resultCell = cell(1,numel(defs));
    for k = 1:numel(defs)
        ev.current_phase = ['simulate_' defs(k).id]; flush();
        set_param([mdl '/Energy Strategy'],'mode',defs(k).strategy_mode);
        simIn = Simulink.SimulationInput(mdl);
        simIn = simIn.setVariable('mass_battery',defs(k).battery_mass_kg);
        simIn = simIn.setVariable('mass_capacitor',defs(k).ultracapacitor_mass_kg);
        simIn = simIn.setVariable('mass_motor',defs(k).motor_generator_mass_kg);
        simIn = simIn.setModelParameter('ReturnWorkspaceOutputs','on');
        ticOne = tic;
        out = sim(simIn);
        elapsed = toc(ticOne);
        log = out.get('simlog_KineticEnergyRecovery');
        [sc, publicLogs] = extractScenario(defs(k),log,elapsed);
        resultCell{k} = sc;
        save(fullfile(outputDir,[defs(k).id '.mat']),'-struct','publicLogs','-v7');
    end
    ev.scenarios = [resultCell{:}];
    ev.structure = struct( ...
        'battery_branch_logged',true,'ultracapacitor_branch_logged',true, ...
        'shared_dc_bus_logged',true,'motor_generator_path_logged',true, ...
        'vehicle_dynamics_logged',true,'source_native_strategy_used',true, ...
        'source_native_mass_parameters_used',true);
    ev.load_update_compile_simulate = all([ev.scenarios.valid]);
    ev.simulation_wall_clock_s = toc(ticSuite);
    ev.current_phase = 'complete';
    ev.evidence_complete = ev.load_update_compile_simulate;
catch ME
    try, eval([mdl '([],[],[],''term'');']); catch, end
    ev.current_phase = 'failed';
    ev.error_identifier = ME.identifier;
    ev.error_message = getReport(ME,'extended','hyperlinks','off');
end
flush();
bdclose('all');
evidence = ev;

    function flush()
        writejson(evidencePath,ev);
    end
end

function d = scenario(id,strategy,batteryMass,capMass,motorMass)
d = struct('id',id,'strategy_mode',strategy,'battery_mass_kg',batteryMass, ...
    'ultracapacitor_mass_kg',capMass,'motor_generator_mass_kg',motorMass);
end

function [sc, publicLogs] = extractScenario(d,log,elapsed)
[tv,vveh] = readSeries(log.Vehicle_Dynamics.Total_Vehicle_Mass.v.series,'km/hr');
[tt,tmotor] = readSeries(log.PMSM_Drive.PMSM_Drive.Tr.series,'N*m');
[tw,wmotor] = readSeries(log.PMSM_Drive.PMSM_Drive.w.series,'rad/s');
[tib,ibat] = readSeries(log.Battery_and_Ultracapacitor.Sensing_Battery_Current.Current_Sensor.I.series,'A');
[tiu,iuc] = readSeries(log.Battery_and_Ultracapacitor.Sensing_Ultracapacitor_Current.Current_Sensor.I.series,'A');
[tvb,vbat] = readSeries(log.Battery_and_Ultracapacitor.Lithium_Ion_Battery.p.v.series,'V');
[tvu,vuc] = readSeries(log.Battery_and_Ultracapacitor.Ultracapacitor.p.v.series,'V');
[tbus,vbus] = readSeries(log.Battery_and_Ultracapacitor.Sensing_Vbus.Voltage_Sensor.V.series,'V');

wOnT = interpSignal(tw,wmotor,tt);
motorPower = tmotor .* wOnT;
iucOnIb = interpSignal(tiu,iuc,tib);
vbatOnBus = interpSignal(tvb,vbat,tbus);
vucOnBus = interpSignal(tvu,vuc,tbus);
vbusOnIb = interpSignal(tbus,vbus,tib);
vbatOnIb = interpSignal(tvb,vbat,tib);
vucOnIb = interpSignal(tvu,vuc,tib);

vehicle_speed = makeLog(tv,vveh,{'vehicle_speed_kph'},{'km/hr'});
traction = makeLog(tt,[tmotor wOnT motorPower], ...
    {'motor_torque_Nm','motor_speed_rad_s','motor_mechanical_power_W'}, ...
    {'N*m','rad/s','W'});
storage_voltage = makeLog(tbus,[vbatOnBus vucOnBus vbus], ...
    {'battery_voltage_V','ultracapacitor_voltage_V','dc_bus_voltage_V'}, ...
    {'V','V','V'});
storage_current = makeLog(tib,[ibat iucOnIb], ...
    {'battery_current_A','ultracapacitor_current_A'},{'A','A'});
storage_power = makeLog(tib,[vbatOnIb.*ibat vucOnIb.*iucOnIb], ...
    {'battery_power_W','ultracapacitor_power_W'},{'W','W'});

logs = struct('vehicle_speed',vehicle_speed,'traction',traction, ...
    'storage_voltage',storage_voltage,'storage_current',storage_current,'storage_power',storage_power);
valid = logsValid(logs);
sc = d;
sc.valid = valid;
sc.simulate_s = elapsed;
sc.lap_completion_s = max(tv);
sc.logs = logs;
sc.metrics = struct( ...
    'vehicle_speed_max_kph',max(abs(vveh)), ...
    'motor_torque_rms_Nm',rms0(tmotor), ...
    'motor_power_peak_W',max(abs(motorPower)), ...
    'battery_current_rms_A',rms0(ibat), ...
    'ultracap_current_rms_A',rms0(iucOnIb), ...
    'battery_power_peak_W',max(abs(vbatOnIb.*ibat)), ...
    'ultracap_power_peak_W',max(abs(vucOnIb.*iucOnIb)), ...
    'bus_voltage_min_V',min(vbus), ...
    'bus_voltage_max_V',max(vbus), ...
    'battery_charge_and_discharge',hasBothSigns(vbatOnIb.*ibat), ...
    'ultracap_charge_and_discharge',hasBothSigns(vucOnIb.*iucOnIb));
publicLogs = logs;
end

function [t,v] = readSeries(series,unit)
t = double(time(series));
v = double(values(series,Units=unit));
t = t(:);
v = v(:);
[t,idx] = unique(t,'stable');
v = v(idx,:);
end

function yq = interpSignal(t,y,tq)
if numel(t) == 1
    yq = repmat(y(1,:),numel(tq),1);
else
    yq = interp1(t,y,tq,'linear','extrap');
end
yq = yq(:);
end

function x = makeLog(t,data,channels,units)
x = struct('time',t(:),'data',data,'channels',{channels},'units',{units});
end

function ok = logsValid(logs)
names = fieldnames(logs);
ok = true;
for k = 1:numel(names)
    x = logs.(names{k});
    ok = ok && numel(x.time) >= 100 && size(x.data,1) == numel(x.time);
    ok = ok && x.time(1) <= 1e-9 && x.time(end) >= 80 && x.time(end) <= 101;
    ok = ok && all(diff(x.time) > 0) && all(isfinite(x.time)) && all(isfinite(x.data(:)));
end
end

function y = rms0(x)
y = sqrt(mean(x.^2));
end

function tf = hasBothSigns(x)
tol = max(max(abs(x))*1e-5,1e-6);
tf = any(x > tol) && any(x < -tol);
end

function writejson(path,x)
f = fopen(path,'w','n','UTF-8');
c = onCleanup(@() fclose(f));
fwrite(f,jsonencode(x,'PrettyPrint',true),'char');
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

