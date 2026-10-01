function evidence = f90_xrobo07_extract_candidate_evidence( ...
        candidatePath, outDir)
%f90_xrobo07_extract_candidate_evidence Candidate-only official map replay.
% COMPATIBILITY adds candidate-independent goal-event termination coverage. Normal early termination still fails closed.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end
[taskRoot,sharedRoot]=localRoots("F90-XROBO-07");
addpath(sharedRoot,"-begin");cleanup=onCleanup(@()rmpath(sharedRoot)); %#ok<NASGU>
official=jsondecode(fileread(simuverity_official_scenarios_path()));
mapFixture=fullfile(taskRoot,replace(string(official.reference.map_path), ...
    "/",filesep));
assert(isfile(mapFixture), ...
    "SimuVerity:F90:XROBO07:OfficialMap", ...
    "Pinned official map fixture is missing or has the wrong binding.");
spec=struct("schema","simuverity.f90-xrobo07-evidence.v1", ...
    "task_id","F90-XROBO-07","task_root",taskRoot, ...
    "scenarios",official.scenarios,"output_contract",localOutputs, ...
    "input_builder",@localInputs,"requested_input_builder",@localRequested, ...
    "stop_time",@(~,~)double(official.simulation.maximum_stop_s), ...
    "postprocess",@localPostprocess,"static_audit",@localAudit, ...
    "coverage_mode","event_terminated", ...
    "maximum_stop_s",double(official.simulation.maximum_stop_s), ...
    "finalize_evidence",@localFinalize,"evidence_sample_s",0.1);
evidence=simuverity_run_candidate_evidence(candidatePath,outDir,spec);
end
function rows=localOutputs
names=["robot_state","executed_command","planner_state"];
widths=[5 2 4];
rows=repmat(struct("name","","evidence_name","","width",0, ...
    "interpolation","linear","event_columns",zeros(0,1)),numel(names),1);
for k=1:numel(names),rows(k).name=names(k);rows(k).evidence_name=names(k); ...
    rows(k).width=widths(k);end
rows(3).interpolation="previous";rows(3).event_columns=1;
end
function inputs=localInputs(scenario,spec)
inputs=localRequested(scenario,spec);
inputs.MapMatrix=localMap(scenario,spec);
end
function requested=localRequested(scenario,~)
requested=rmfield(scenario,intersect(fieldnames(scenario),{'id','map_variant'}));
end
function map=localMap(scenario,spec)
fixture=fullfile(spec.task_root,"official_assets","offroadMap.mat");
assert(isfile(fixture),"SimuVerity:F90:XROBO07:OfficialMap", ...
    "Pinned official map fixture is missing.");
loaded=load(fixture,"map");map=uint8(loaded.map);
if string(scenario.map_variant)=="official_plus_bounded_route_patch"
    rows=max(1,min(size(map,1),136:146));
    cols=max(1,min(size(map,2),95:105));
    map(rows,cols)=1;
end
end
function row=localPostprocess(row,outputs,scenario,spec)
map=logical(localMap(scenario,spec));
state=double(outputs.robot_state);
[collisionFree,clearance]=localCollisionEvidence( ...
    state(:,1:3),map,double(scenario.ObstacleSafetyMargin));
outputs.collision_free=double(collisionFree);
outputs.obstacle_clearance_margin_m=clearance;
planner=double(outputs.planner_state);
time=double(outputs.time_s(:));
goal=double(scenario.GoalPose(:));
finalPositionError=hypot(state(end,1)-goal(1),state(end,2)-goal(2));
finalHeadingError=abs(atan2(sin(state(end,3)-goal(3)), ...
    cos(state(end,3)-goal(3))));
early=time(end)<double(row.stop_time_s)-max(0.2,2*spec.evidence_sample_s);
terminalGoalSignal=~isempty(planner) && size(planner,2)>=1 && ...
    planner(end,1)>=0.5;
terminalPhysical=finalPositionError<=0.5 && finalHeadingError<=0.35;
requiredThroughEvent=row.output_contract.all_required_pass;
dynamicEventPass=~early || ...
    (terminalGoalSignal && terminalPhysical && requiredThroughEvent);
row.outputs=outputs;
row.map_occupied_fraction=mean(map,"all");
row.metrics.actual_output_end_s=time(end);
row.metrics.event_terminated=logical(early);
row.metrics.terminal_goal_signal_observed=logical(terminalGoalSignal);
row.metrics.terminal_goal_physical_proximity=logical(terminalPhysical);
row.metrics.terminal_position_error_m=finalPositionError;
row.metrics.terminal_heading_error_rad=finalHeadingError;
row.metrics.required_outputs_complete_through_terminal_event= ...
    logical(requiredThroughEvent);
row.metrics.event_termination_dynamic_qualified=logical(dynamicEventPass);
row.valid=row.output_contract.all_required_pass && ...
    all(isfinite(clearance)) && dynamicEventPass;
end
function [stateFree,distance]=localCollisionEvidence(poses,map,margin)
sdf=signedDistanceMap(double(map),Resolution=1,InterpolationMethod="linear");
vehicle=vehicleDimensions(4,2);
vehicle.RearOverhang=1.5;vehicle.Wheelbase=1;
checker=inflationCollisionChecker(vehicle,3);
centers=checker.CenterPlacements(:)*checker.VehicleDimensions.Wheelbase;
radius=checker.InflationRadius+margin;
distance=zeros(size(poses,1),1);
for k=1:size(poses,1)
    yaw=poses(k,3);
    points=[poses(k,1)+centers*cos(yaw),poses(k,2)+centers*sin(yaw)];
    distance(k)=min(sdf.distance(points)-radius);
end
stateFree=distance>0|isnan(distance);
end
function audit=localAudit(model,spec)
structure=simuverity_candidate_structure(model,string({spec.output_contract.name})');
semantic=structure.semantic_types;
planner=nnz(contains(semantic,["planner","navigation","trajectory", ...
    "matlab system","matlab function"]));
vehicle=nnz(contains(semantic,["bicycle","kinematic","state-space"]));
controller=nnz(contains(semantic,["controller","pure pursuit","teb","pid"]));
[goalTerminationPass,goalTerminationProof]= ...
    localGoalTerminationPath(model);
audit=struct("planner_mechanism_count",planner, ...
    "vehicle_dynamics_count",vehicle,"controller_count",controller, ...
    "signal_cycle_present",structure.signal_cycle_present, ...
    "connected_public_output_count",structure.connected_output_count, ...
    "goal_termination_path_qualified",logical(goalTerminationPass), ...
    "goal_termination_path_proof",goalTerminationProof, ...
    "core_path_qualified", ...
        structure.connected_output_count==numel(spec.output_contract) && ...
        structure.nontrivial_output_source_count==numel(spec.output_contract) && ...
        structure.dynamic_block_count>=1 && planner>=1 && vehicle>=1 && ...
        controller>=1 && structure.signal_cycle_present);
end

function evidence=localFinalize(evidence,~)
rows=evidence.scenarios;
staticPass=isfield(evidence.static_audit, ...
    "goal_termination_path_qualified") && ...
    logical(evidence.static_audit.goal_termination_path_qualified);
eventCount=0;
for index=1:numel(rows)
    if isfield(rows(index).metrics,"event_terminated") && ...
            logical(rows(index).metrics.event_terminated)
        eventCount=eventCount+1;
        dynamicPass=isfield(rows(index).metrics, ...
            "event_termination_dynamic_qualified") && ...
            logical(rows(index).metrics.event_termination_dynamic_qualified);
        rows(index).metrics.event_termination_static_qualified=logical(staticPass);
        rows(index).metrics.event_termination_qualified= ...
            logical(staticPass && dynamicPass);
        rows(index).valid=logical(rows(index).valid && ...
            rows(index).metrics.event_termination_qualified);
        rows(index).success=rows(index).valid;
    else
        rows(index).metrics.event_termination_static_qualified=true;
        rows(index).metrics.event_termination_qualified=true;
    end
end
evidence.scenarios=rows;
validRows=false(numel(rows),1);
if ~isempty(rows),validRows=logical([rows.valid]);end
evidence.nominal_smoke_pass=~isempty(validRows)&&validRows(1);
evidence.score_inputs_valid=evidence.platform_valid && ...
    numel(rows)==5 && all(validRows);
evidence.diagnostics_valid=evidence.score_inputs_valid;
evidence.event_terminated_coverage_successor=true;
evidence.event_terminated_scenario_count=eventCount;
evidence.event_termination_static_path_qualified=logical(staticPass);
end

function [pass,proof]=localGoalTerminationPath(model)
proof=struct("single_stop_block",false, ...
    "single_planner_state_sink",false, ...
    "shared_matlab_function_source",false, ...
    "terminal_output_port_bound",false, ...
    "planner_state_output_port_bound",false, ...
    "planner_channel1_is_terminal_signal",false, ...
    "identity_specific_route_used",false);
pass=false;
stops=string(find_system(model,"FollowLinks","on", ...
    "LookUnderMasks","all","Type","Block","BlockType","Stop"));
sinks=string(find_system(model,"FollowLinks","on", ...
    "LookUnderMasks","all","Type","Block","BlockType","ToWorkspace"));
plannerSinks=strings(0,1);
for sink=sinks(:).'
    try
        if string(get_param(sink,"VariableName"))=="planner_state"
            plannerSinks(end+1,1)=sink; %#ok<AGROW>
        end
    catch
    end
end
proof.single_stop_block=numel(stops)==1;
proof.single_planner_state_sink=numel(plannerSinks)==1;
if ~proof.single_stop_block || ~proof.single_planner_state_sink,return,end
[stopSource,stopPort]=localUpstreamSource(stops(1));
[plannerSource,plannerPort]=localUpstreamSource(plannerSinks(1));
proof.terminal_output_port_bound=strlength(stopSource)>0&&stopPort>=1;
proof.planner_state_output_port_bound= ...
    strlength(plannerSource)>0&&plannerPort>=1;
proof.shared_matlab_function_source= ...
    stopSource==plannerSource&&strlength(stopSource)>0&& ...
    contains(lower(localGetParam(stopSource,"SFBlockType")),"matlab function");
if ~all([proof.terminal_output_port_bound, ...
        proof.planner_state_output_port_bound, ...
        proof.shared_matlab_function_source]),return,end
script=localChartScript(stopSource);
outputs=localFunctionOutputs(script);
if stopPort>numel(outputs)||plannerPort>numel(outputs),return,end
terminalVariable=outputs(stopPort);
plannerVariable=outputs(plannerPort);
code=localNormalizeScript(script);
direct=plannerVariable+"(1)="+terminalVariable+";";
casted=plannerVariable+"(1)=double("+terminalVariable+");";
proof.planner_channel1_is_terminal_signal= ...
    contains(code,direct)||contains(code,casted);
pass=all(structfun(@(value)logical(value),rmfield(proof, ...
    "identity_specific_route_used")));
end

function [source,portNumber]=localUpstreamSource(block)
source="";portNumber=0;
try
    ports=get_param(block,"PortHandles");
    if isempty(ports.Inport),return,end
    line=get_param(ports.Inport(1),"Line");
    if line<0,return,end
    sourcePort=get_param(line,"SrcPortHandle");
    if sourcePort<0,return,end
    source=string(get_param(sourcePort,"Parent"));
    raw=get_param(sourcePort,"PortNumber");
    if isnumeric(raw),portNumber=double(raw);
    else,portNumber=str2double(string(raw));end
catch
    source="";portNumber=0;
end
end

function script=localChartScript(block)
script="";
try
    chart=find(sfroot,"-isa","Stateflow.EMChart","Path",char(block));
    if numel(chart)==1,script=string(chart.Script);end
catch
end
end

function outputs=localFunctionOutputs(script)
outputs=strings(0,1);
lines=strtrim(splitlines(string(script)));
index=find(startsWith(lines,"function "),1,"first");
if isempty(index),return,end
header=strtrim(extractAfter(lines(index),strlength("function ")));
equalsAt=strfind(char(header),"=");
if numel(equalsAt)~=1,return,end
left=strtrim(extractBefore(header,equalsAt(1)));
if startsWith(left,"[")&&endsWith(left,"]")
    outputs=string(strtrim(strsplit(char( ...
        extractBetween(left,2,strlength(left)-1)),","))).';
    outputs=outputs(strlength(outputs)>0);
elseif matches(left,regexpPattern("^[A-Za-z][A-Za-z0-9_]*$"))
    outputs=left;
end
end

function value=localNormalizeScript(script)
characters=char(script);
value=string(characters(~isspace(characters)));
end

function value=localGetParam(block,parameter)
value="";
try,value=string(get_param(block,parameter));catch,end
end
function [taskRoot,sharedRoot]=localRoots(taskId)
scriptRoot=fileparts(mfilename("fullpath"));tasksRoot=fileparts(scriptRoot);
sharedRoot=fullfile(tasksRoot,"_shared");repoRoot=tasksRoot;
for k=1:3,repoRoot=fileparts(repoRoot);end
taskRoot=string(getenv("SIMUVERITY_TASK_ROOT"));
end
