function evidence=f90_xmed02_extract_reference_evidence(modelPath,outDir)
%f90_xmed02_extract_reference_evidence Exact-reference R2025a bridge.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
taskRoot=fileparts(mfilename('fullpath'));
projectRoot=fileparts(fileparts(fileparts(fileparts(taskRoot))));
addpath(fullfile(projectRoot,'scripts','xp9'),'-begin');
publicOutputDependency=fullfile(projectRoot,'scripts','unified', ...
    'public_output','simuverity_public_output_compatibility.m');
assert(strcmpi(xp9_file_presence_file(publicOutputDependency), ...
    "present"), ...
    'F90_XMED02_PUBLIC_OUTPUT_DEPENDENCY_BINDING');
addpath(fileparts(publicOutputDependency),'-begin');
physicalNetDependency=fullfile(projectRoot,'engine', ...
    'simuverity_physical_line_networks.m');
assert(strcmpi(xp9_file_presence_file(physicalNetDependency), ...
    "present"), ...
    'F90_XMED02_PHYSICAL_NET_DEPENDENCY_BINDING');
addpath(fullfile(projectRoot,'engine'),'-begin');addpath(taskRoot,'-begin');
dependency=fullfile(taskRoot,'f90_xmed02_measurement.m');
assert(strcmpi(xp9_file_presence_file(dependency), ...
    "present"), ...
    'F90_XMED02_MEASUREMENT_DEPENDENCY_BINDING');
assignScenario=@(varargin)f90_xmed02_measurement_compatibility("localAssignScenario",varargin{:});
readTimeseries=@(varargin)f90_xmed02_measurement_compatibility("localTimeseries",varargin{:});
heartRate=@(varargin)f90_xmed02_measurement_compatibility("localHeartRateEstimate",varargin{:});
task=f90_xmed02_definition();
facts=struct('platform_valid',false,'score_inputs_valid',false, ...
    'diagnostics_valid',false,'gate_reasons',strings(0,1), ...
    'structure_policy_id',"formal90-xmed02-connected-circulation", ...
    'static_audit',struct,'scenario_rows',struct([]));
[~,model]=fileparts(modelPath);oldDir=pwd;oldPath=path;
cleanup=onCleanup(@() local_cleanup(model,oldDir,oldPath)); %#ok<NASGU>
try
    assert(isfile(modelPath),'F90_XMED02_MODEL_MISSING');
    assignScenario(task.scenarios(1));load_system(modelPath);
    set_param(model,'SimulationCommand','update');
    audit=f90_xmed02_reference_static_audit(model);reasons=strings(0,1);
    if ~logical(audit.circulation_topology.pass)
        reasons(end+1)="missing_or_unproved_connected_circulation_topology";
    elseif ~logical(audit.core_mechanism_ok)
        reasons(end+1)="missing_or_unproved_core_physical_feedback_mechanism";
    end
    rows=repmat(local_empty_row(),0,1);
    if isempty(reasons)
        for index=1:numel(task.scenarios)
            scenario=task.scenarios(index);row=local_empty_row();row.id=scenario.id;
            row.inputs=scenario;
            try
                assignScenario(scenario);
                set_param(model,'StopTime',char(string(task.stop_time_s)), ...
                    'ReturnWorkspaceOutputs','on');
                output=sim(model);
                pressure=readTimeseries(output,'pressure_state',3, ...
                    task.stop_time_s,task.windows.minimum_samples);
                flow=readTimeseries(output,'flow_state',3, ...
                    task.stop_time_s,task.windows.minimum_samples);
                command=readTimeseries(output,'pump_command',1, ...
                    task.stop_time_s,task.windows.minimum_samples);
                row.interface_valid=pressure.valid&&flow.valid&&command.valid;
                row.interface_reasons=[pressure.reasons;flow.reasons;command.reasons];
                if row.interface_valid
                    row.metrics=local_measure_raw(scenario,task,pressure,flow, ...
                        command,heartRate);
                    row.valid=local_all_finite(row.metrics);
                end
            catch ME
                row.error_id=string(ME.identifier);row.error_message=string(ME.message);
            end
            if ~row.valid,reasons(end+1)="scenario_failed:"+row.id;end %#ok<AGROW>
            rows(end+1,1)=row; %#ok<AGROW>
        end
    end
    gate=isempty(reasons)&&numel(rows)==numel(task.scenarios)&&all([rows.valid]);
    facts.platform_valid=true;facts.score_inputs_valid=gate;
    facts.diagnostics_valid=true;facts.gate_reasons=unique(reasons,'stable');
    facts.static_audit=audit;facts.scenario_rows=rows;
catch ME
    facts.gate_reasons="Evaluator/platform failure: "+string(ME.message);
    facts.error_identifier=string(ME.identifier);facts.error_message=string(ME.message);
end
evidence=formal90_write_evidence("F90-XMED-02",modelPath,outDir, ...
    task.weights,facts,dependency);
end

function metrics=local_measure_raw(scenario,task,pressure,flow,command,heartRate)
dt=.002;grid=(0:dt:task.stop_time_s).';
p=interp1(pressure.time,pressure.data,grid,'linear','extrap');
f=interp1(flow.time,flow.data,grid,'linear','extrap');
u=interp1(command.time,command.data,grid,'linear','extrap');
period=60/scenario.heart_rate_bpm;windowSamples=max(3,round(period/dt));
map=movmean(p(:,1),[windowSamples-1,0]);
pre=grid>=max(period,scenario.target_step_time_s-task.windows.pre_step_tail_s)& ...
    grid<=scenario.target_step_time_s-.10;
post=grid>=task.stop_time_s-task.windows.post_step_tail_s;
assert(any(pre)&&any(post),'SimuVerity:F90:XMED02:EvidenceWindow');
mapInitial=mean(map(pre));mapFinal=mean(map(post));
tailPeriod=grid>=task.stop_time_s-period;
systemic=mean(f(post,2));pulmonary=mean(f(post,3));ecmo=mean(f(post,1));
flowBalance=abs(systemic-pulmonary-ecmo)/ ...
    max(mean(abs([systemic,pulmonary+ecmo])),1);
after=grid>=scenario.target_step_time_s;afterTime=grid(after);
afterError=abs(map(after)-scenario.target_map_final_mmHg);
lastBad=find(afterError>3,1,'last');
settlingUnrecovered=false;
if isempty(lastBad),settling=0;
elseif lastBad<numel(afterTime),settling=afterTime(lastBad+1)-scenario.target_step_time_s;
else,settling=task.stop_time_s;settlingUnrecovered=true;end
if scenario.target_map_final_mmHg>scenario.target_map_initial_mmHg
    overshoot=max(0,max(map(after))-scenario.target_map_final_mmHg);
elseif scenario.target_map_final_mmHg<scenario.target_map_initial_mmHg
    overshoot=max(0,scenario.target_map_final_mmHg-min(map(after)));
else
    overshoot=max(abs(map(after)-scenario.target_map_final_mmHg));
end
before=grid<scenario.target_step_time_s;beforeTime=grid(before);
lastInitialBad=find(abs(map(before)-scenario.target_map_initial_mmHg)>3,1,'last');
initialUnrecovered=false;
if isempty(lastInitialBad),initialSettling=0;
elseif lastInitialBad<numel(beforeTime),initialSettling=beforeTime(lastInitialBad+1);
else,initialSettling=task.stop_time_s;initialUnrecovered=true;end
estimate=heartRate(grid,p(:,1),scenario.heart_rate_bpm);
metrics=struct( ...
    'map_initial_mmHg',mapInitial,'map_final_mmHg',mapFinal, ...
    'initial_error_mmHg',abs(mapInitial-scenario.target_map_initial_mmHg), ...
    'final_error_mmHg',abs(mapFinal-scenario.target_map_final_mmHg), ...
    'pulse_pressure_mmHg',max(p(tailPeriod,1))-min(p(tailPeriod,1)), ...
    'cvp_mean_mmHg',mean(p(post,2)),'pap_mean_mmHg',mean(p(post,3)), ...
    'ecmo_flow_mean_cm3_s',ecmo,'systemic_flow_mean_cm3_s',systemic, ...
    'pulmonary_flow_mean_cm3_s',pulmonary, ...
    'flow_balance_fraction',flowBalance, ...
    'heart_rate_estimate_bpm',estimate, ...
    'heart_rate_error_bpm',abs(estimate-scenario.heart_rate_bpm), ...
    'command_initial_mean_rpm',mean(u(pre)), ...
    'command_final_mean_rpm',mean(u(post)), ...
    'command_within_limit',all(u>=-1e-6&u<=scenario.pump_speed_limit_rpm+1e-6), ...
    'negative_ecmo_fraction',mean(f(:,1)<-1e-5), ...
    'pump_saturation_fraction',mean(u>=.995*scenario.pump_speed_limit_rpm), ...
    'settling_time_s',settling,'settling_unrecovered',settlingUnrecovered, ...
    'overshoot_mmHg',overshoot, ...
    'initial_settling_time_s',initialSettling, ...
    'initial_settling_unrecovered',initialUnrecovered);
end

function row=local_empty_row()
row=struct('id',"",'inputs',struct,'valid',false,'interface_valid',false, ...
    'interface_reasons',strings(0,1),'metrics',struct, ...
    'error_id',"",'error_message',"");
end

function valid=local_all_finite(value)
fields=fieldnames(value);valid=true;
for index=1:numel(fields)
    item=value.(fields{index});
    if isnumeric(item)&&any(~isfinite(item),'all'),valid=false;return;end
end
end

function local_cleanup(model,oldDir,oldPath)
try,if bdIsLoaded(model),close_system(model,0);end,catch,end
try,cd(oldDir);path(oldPath);catch,end
end
