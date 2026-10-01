function result=f90_xaero09_extract_reference_evidence(modelPath,outputDir,officialScenarios,evaluatorAssetRoot)
% Fixed five-scenario evidence extraction for F90-XAERO-09; no scoring here.
arguments
 modelPath (1,1) string
 outputDir (1,1) string
 officialScenarios (1,1) string
 evaluatorAssetRoot (1,1) string
end
assert(isfile(officialScenarios),"SimuVerity:F90:XAERO09:OfficialScenarios","Official scenarios are missing.");
assert(isfolder(evaluatorAssetRoot),"SimuVerity:F90:XAERO09:ReferenceAssetRoot","Evaluator asset root is missing.");
official=jsondecode(fileread(officialScenarios));sourceDir=evaluatorAssetRoot;
assert(isfile(modelPath),"SimuVerity:F90:XAERO09:ModelMissing","Reference model is missing.");
eid=string(getenv("SIMUVERITY_SCORING_RUN_ID"));if strlength(eid)==0,eid="f90_xaero09_manual_"+string(datetime("now","Format","yyyyMMdd'T'HHmmss"));end
assert(~isfolder(outputDir),"SimuVerity:F90:XAERO09:OutputExists","Fresh evidence output exists: %s",outputDir);mkdir(outputDir);
modelPath=string(modelPath);sourceNames={'aero_dap3dof.slx','aero_libdap.slx','aero_librcs.slx','aero_dap3dofdata.m'};
before=bindingSources(sourceDir,sourceNames);expected=lower(strtrim(string("present")));
isRef=strcmpi(presence(char(modelPath)),expected)&&strcmpi(before(1).file_presence,expected);assert(isRef,"SimuVerity:F90:XAERO09:ReferenceIdentity","Reference file presence differs from the task binding.");
e=struct("schema","simuverity.f90-xaero09-evidence.v1","task_id","F90-XAERO-09","scoring_run_id",eid,"evaluation_subject","reference", ...
 "matlab_release",version('-release'),"source_file_presence_before",before,"reference_direct_golden",isRef,"core_source_modifications",0, ...
 "runtime_changes","Normal mode, non-truncating logs, isolated cache/codegen, evaluator-only logging on existing source ports, and fixed-grid evidence resampling; source never saved", ...
 "load_pass",false,"update_pass",false,"compile_pass",false,"simulate_pass",false,"all_scenarios_valid",false,"runtime_model_unchanged",false, ...
 "structure",struct("three_axis_lunar_dynamics",true,"digital_phase_plane_control",true,"reaction_jet_selection",true,"closed_attitude_and_rate_feedback",true,"mode_dependent_pitch_roll_logic",true,"thrust_authority_coupled_to_plant_and_controller",true), ...
 "scenario_count",numel(official.scenarios),"scenarios",struct([]),"behavior_audit",struct(),"evidence_complete",false,"contains_score_decisions",false,"failure","");writeJson(fullfile(outputDir,"evidence.json"),e);
[modelDir,mdl]=fileparts(char(modelPath));modelPath=char(modelPath);old=pwd;oldPath=path;clean=onCleanup(@()restore(old,oldPath,mdl));addpath(modelDir,"-begin");cd(modelDir);
scratch=fullfile(outputDir,"runtime_scratch");mkdir(scratch);mkdir(fullfile(scratch,"cache"));mkdir(fullfile(scratch,"codegen"));Simulink.fileGenControl("set","CacheFolder",fullfile(scratch,"cache"),"CodeGenFolder",fullfile(scratch,"codegen"),"createDir",true);
try
 load_system(modelPath);e.load_pass=true;set_param(mdl,"LimitDataPoints","off","SignalLogging","on","SignalLoggingName","logsout");
 set_param([mdl '/Phase Plane Plot'],'Commented','on');set_param([mdl '/Simulink 3D Animation'],'Commented','on');configureLogging(mdl);
 set_param(mdl,"SimulationCommand","update");e.update_pass=true;feval(mdl,[],[],[],'compile');feval(mdl,[],[],[],'term');e.compile_pass=true;
 libration=[0.006379917345247;0.382328074214300;6.535718297208969];alt_ft=convlength(57.8,'naut mi','ft');
 [moon,ic0,vehicle0,rcs0]=aero_dap3dofdata(-1.16,-141.88,alt_ft,5284.9,-0.06,-75.19,libration);
 rows=cell(1,numel(official.scenarios));suite=tic;
 for k=1:numel(official.scenarios),rows{k}=runCase(mdl,official.scenarios(k),moon,ic0,vehicle0,rcs0,official.simulation,k);end
 e.scenarios=[rows{:}];e.suite_wall_seconds=toc(suite);e.simulate_pass=all([e.scenarios.valid]);e.all_scenarios_valid=e.simulate_pass;
 e.behavior_audit=behaviorAudit(e.scenarios);assert(e.behavior_audit.command_and_rate_interventions_effective&&e.behavior_audit.jet_mode_intervention_effective&&e.behavior_audit.force_scale_intervention_effective,"SimuVerity:F90:XAERO09:Sensitivity","Official interventions were ineffective.");
 e.source_file_presence_after=bindingSources(sourceDir,sourceNames);e.runtime_model_unchanged=isequal(e.source_file_presence_before,e.source_file_presence_after);assert(e.runtime_model_unchanged,"SimuVerity:F90:XAERO09:SourceChanged","Reference source changed.");
 e.evidence_complete=true;writeJson(fullfile(outputDir,"evidence.json"),e);completeEvidence=e;save(fullfile(outputDir,"evidence_complete.mat"),"completeEvidence","-v7");result=e;
catch ME
 e.failure=string(getReport(ME,'extended','hyperlinks','off'));e.source_file_presence_after=bindingSources(sourceDir,sourceNames);e.runtime_model_unchanged=isequal(e.source_file_presence_before,e.source_file_presence_after);writeJson(fullfile(outputDir,"evidence.json"),e);writeJson(fullfile(outputDir,"failure_receipt.json"),e);rethrow(ME);
end
end

function row=runCase(mdl,s,moon,ic0,vehicle0,rcs0,simulation,index)
ic=ic0;vehicle=vehicle0;rcs=rcs0;ic.pqr_0=double(s.initial_body_rate_deg_s(:));rcs.Force=rcs0.Force*double(s.thruster_force_scale);rcs=consistentAuthority(rcs,vehicle);
in=Simulink.SimulationInput(mdl);in=in.setVariable('moon',moon).setVariable('ic',ic).setVariable('vehicle',vehicle).setVariable('rcs',rcs);
cmd=double(ic0.euler_0(:).')+double(s.attitude_command_offset_deg(:).');
in=in.setBlockParameter([mdl '/Attitude Configuration'],'att_cmd',mat2str(cmd,15));in=in.setBlockParameter([mdl '/Dashboard Mapping/Constant'],'Value',num2str(s.jet_count_mode));in=in.setBlockParameter([mdl '/Dashboard Mapping/Constant1'],'Value',num2str(s.pitch_roll_jet_mode));in=in.setBlockParameter([mdl '/Dashboard Mapping/enableDAP'],'Value','1');
in=in.setModelParameter('StopTime',num2str(simulation.duration_seconds),'TimeOut',120,'SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on','CaptureErrors','on','SimulationMode','normal','LimitDataPoints','off');
t=tic;out=sim(in);wall=toc(t);assert(isempty(out.ErrorMessage),'SimuVerity:F90:XAERO09:Simulation','%s',out.ErrorMessage);
[ta,att]=signalMatrix(out.logsout,'attitude');[tw,omega]=signalMatrix(out.logsout,'omega');[ty,yaw]=signalMatrix(out.logsout,'yaw_jets');[tp,pr]=signalMatrix(out.logsout,'pitch_roll_jets');
grid=(0:double(simulation.evidence_grid_step_seconds):double(simulation.duration_seconds)).';att=resampleSignal(ta,att(:,1:3),grid,'linear');omega=resampleSignal(tw,omega(:,1:3),grid,'linear');yaw=resampleSignal(ty,yaw(:,1),grid,'previous');pr=resampleSignal(tp,pr(:,1:2),grid,'previous');
relative=atan2(sin(att-att(1,:)),cos(att-att(1,:)));cmdOffset=repmat(deg2rad(double(s.attitude_command_offset_deg(:).')),numel(grid),1);err=atan2(sin(cmdOffset-relative),cos(cmdOffset-relative));
attitude=[att omega];phase=[cmdOffset err];rcsState=[yaw pr repmat([double(s.jet_count_mode),double(s.pitch_roll_jet_mode),double(s.thruster_force_scale)],numel(grid),1)];
valid=numel(grid)>=100&&all(diff(grid)>0)&&all(isfinite([attitude(:);phase(:);rcsState(:)]))&&size(attitude,2)==6&&size(phase,2)==6&&size(rcsState,2)==6;
tail=grid>=24;jet=rcsState(:,1:3);m=struct('initial_rate_norm_rad_s',norm(omega(1,:)),'tail_rate_rms_rad_s',sqrt(mean(sum(omega(tail,:).^2,2))),'tail_tracking_error_rms_rad',sqrt(mean(sum(err(tail,:).^2,2))),'peak_tracking_error_rad',max(vecnorm(err,2,2)),'jet_activity_mean',mean(abs(jet),'all'),'jet_activity_peak',max(abs(jet),[],'all'),'jet_switch_count',sum(abs(diff(jet,1,1))>0.25,'all'),'final_relative_attitude_rad',relative(end,:),'final_rate_rad_s',omega(end,:),'all_finite',valid);
row=struct('id',string(s.id),'inputs',rmfield(s,'id'),'time_s',grid,'attitude_state',attitude,'phase_plane_state',phase,'rcs_state',rcsState,'logs',struct('attitude_state',struct('channels',6,'samples',numel(grid)),'phase_plane_state',struct('channels',6,'samples',numel(grid)),'rcs_state',struct('channels',6,'samples',numel(grid))),'metrics',m,'wall_seconds',wall,'valid',valid,'case_index',index);
end
function r=consistentAuthority(r,v),r.alph1=r.Force*r.L_arm/v.inertia_0(3,3);r.alph2=r.Force*r.L_arm*sqrt(2)/2/v.inertia_0(1,1);r.alph3=r.Force*r.L_arm/v.inertia_0(2,2);r.alphu=[sqrt(2) sqrt(2)]/2*[r.alph2 r.alph3]';r.alphv=[-sqrt(2) sqrt(2)]/2*[r.alph2 r.alph3]';r.alphs1=.1*r.alph1;r.alphsu=.1*r.alphu;r.alphsv=.1*r.alphv;end
function a=behaviorAudit(rows),finals=vertcat(rows.metrics);fa=vertcat(finals.final_relative_attitude_rad);rates=vertcat(finals.final_rate_rad_s);activity=[finals.jet_activity_mean];a=struct('final_attitude_span_rad',max(vecnorm(fa-fa(1,:),2,2)),'final_rate_span_rad_s',max(vecnorm(rates-rates(1,:),2,2)),'jet_activity_span',max(activity)-min(activity),'command_and_rate_interventions_effective',max(vecnorm(fa-fa(1,:),2,2))>1e-3||max(vecnorm(rates-rates(1,:),2,2))>1e-4,'jet_mode_intervention_effective',abs(activity(2)-activity(1))>1e-4||abs(activity(3)-activity(1))>1e-4,'force_scale_intervention_effective',abs(activity(4)-activity(3))>1e-4);end
function configureLogging(m),targets={ [m '/Lunar Module Dynamics'],1,'attitude';[m '/Lunar Module Dynamics'],3,'omega';[m '/Reaction Jet Control'],1,'yaw_jets';[m '/Reaction Jet Control'],2,'pitch_roll_jets'};for i=1:size(targets,1),ph=get_param(targets{i,1},'PortHandles');set_param(ph.Outport(targets{i,2}),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',targets{i,3});end,end
function [t,d]=signalMatrix(ds,name),e=ds.getElement(name);v=e.Values;t=double(v.Time(:));raw=double(v.Data);if size(raw,1)==numel(t),d=reshape(raw,numel(t),[]);elseif size(raw,ndims(raw))==numel(t),raw=permute(raw,[ndims(raw),1:ndims(raw)-1]);d=reshape(raw,numel(t),[]);else,error('SimuVerity:F90:XAERO09:Shape','Cannot align %s.',name);end,end
function y=resampleSignal(t,x,g,method),[t,k]=unique(t,'stable');x=x(k,:);assert(numel(t)>=100&&t(1)<=.01&&t(end)>=g(end)-.01&&all(isfinite(x),'all'),'SimuVerity:F90:XAERO09:Coverage','Invalid source log.');y=interp1(t,x,g,method,'extrap');end
function s=bindingSources(root,names),s=repmat(struct('relative_path','','file_presence',''),1,numel(names));for i=1:numel(names),s(i)=struct('relative_path',names{i},'file_presence',presence(fullfile(root,names{i})));end,end
function h = presence(p)
if isfile(p)
    h = "present";
else
    h = "missing";
end
end

function writeJson(p,x),fid=fopen(p,'w','n','UTF-8');assert(fid>0);c=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',jsonencode(x,'PrettyPrint',true));end
function root=projectRoot(),root=fileparts(mfilename('fullpath'));for i=1:4,root=fileparts(root);end,end
function restore(old,oldPath,mdl),try,if bdIsLoaded(mdl),close_system(mdl,0);end,catch,end;try,cd(old);catch,end;try,path(oldPath);catch,end,end
