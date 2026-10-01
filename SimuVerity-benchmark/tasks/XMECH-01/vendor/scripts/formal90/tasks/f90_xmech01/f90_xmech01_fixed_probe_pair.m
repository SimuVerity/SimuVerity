function pair=f90_xmech01_fixed_probe_pair(runs)
%F90_XMECH01_FIXED_PROBE_PAIR Measure only the declared binding probe pair.
pair=empty_pair();
names=string({runs.scenario});
lossMatches=find(names=="traction_binding_probe");
controlMatches=find(names=="traction_binding_probe_no_loss");
if numel(lossMatches)~=1||numel(controlMatches)~=1
    pair.failure_reason="FIXED_TRACTION_BINDING_PROBE_PAIR_MISSING";
    return
end
iLoss=lossMatches(1);iControl=controlMatches(1);
lossRun=runs(iLoss);controlRun=runs(iControl);
if string(lossRun.stage)~="simulated"||string(controlRun.stage)~="simulated"
    pair.failure_reason="FIXED_TRACTION_BINDING_PROBE_PAIR_NOT_SIMULATED";
    return
end
if ~matching_inputs(lossRun.inputs,controlRun.inputs)
    pair.failure_reason="FIXED_TRACTION_BINDING_PROBE_INPUT_MISMATCH";
    return
end

[tL,mL,ok1]=xp9_series(lossRun,'vehicle_motion',5);
[tZ,mZ,ok2]=xp9_series(controlRun,'vehicle_motion',5);
[t2,sL,ok3]=xp9_series(lossRun,'track_state',4);
[t3,sZ,ok4]=xp9_series(controlRun,'track_state',4);
[t4,cL,ok5]=xp9_series(lossRun,'terrain_contact',4);
[t5,cZ,ok6]=xp9_series(controlRun,'terrain_contact',4);
if ~(ok1&&ok2&&ok3&&ok4&&ok5&&ok6&&isequal(tL,t2)&& ...
        isequal(tL,t4)&&isequal(tZ,t3)&&isequal(tZ,t5))
    pair.failure_reason="FIXED_TRACTION_BINDING_PROBE_OUTPUT_INVALID";
    return
end
sameTimebase=isequal(tL,tZ);
[t,loss,control,aligned]=formal90_align_pair_timebase( ...
    tL,[mL,sL,cL],tZ,[mZ,sZ,cZ],max(tL(1),tZ(1)),min(tL(end),tZ(end)));
if ~aligned
    pair.failure_reason="FIXED_TRACTION_BINDING_PROBE_TIMEBASE_INVALID";
    return
end
mL=loss(:,1:5);sL=loss(:,6:9);cL=loss(:,10:13);
mZ=control(:,1:5);sZ=control(:,6:9);cZ=control(:,10:13);
event=double(lossRun.inputs.traction_event_time);eventEnd=event+1.2;
evt=t>=event+.08&t<=eventEnd-.05;
post=t>=eventEnd+.6&t<=min(t(end),eventEnd+1.6);
if nnz(evt)<60||nnz(post)<30
    pair.failure_reason="FIXED_TRACTION_BINDING_PROBE_WINDOW_INVALID";
    return
end

mu=double(lossRun.inputs.terrain_friction)* ...
    (1-double(lossRun.inputs.left_traction_loss));
binding=local_quantile(abs(cL(evt,1))./max(mu*cL(evt,3),100),.95);
width=1.2;
motion=max(median(abs(mL(evt,4)-mZ(evt,4)))/ ...
    max(median(abs(mZ(evt,4))),.30), ...
    width*median(abs(mL(evt,5)-mZ(evt,5)))/ ...
    max(abs(double(lossRun.inputs.right_track_command)- ...
    double(lossRun.inputs.left_track_command)),.20));
slip=max(median(abs(sL(evt,3:4)-sZ(evt,3:4))));
force=max(median(abs(cL(evt,1:2)-cZ(evt,1:2))))/ ...
    max((720+double(lossRun.inputs.payload_mass))*9.81,1);
effect=max([motion slip force]);
degradation=max([median(abs(sL(post,1:2)-sZ(post,1:2)),'all')/ ...
    max(mean(abs(sZ(post,1:2)),'all'),.30), ...
    median(abs(mL(post,4)-mZ(post,4)))/max(median(abs(mZ(post,4))),.30), ...
    width*median(abs(mL(post,5)-mZ(post,5)))/ ...
    max(abs(double(lossRun.inputs.right_track_command)- ...
    double(lossRun.inputs.left_track_command)),.20)]);
recovery=paired_recovery(t,mL,sL,mZ,sZ,eventEnd);
if ~all(isfinite([binding effect degradation]))||isnan(recovery)
    pair.failure_reason="FIXED_TRACTION_BINDING_PROBE_METRIC_INVALID";
    return
end
recoveryObserved=isfinite(recovery);
if ~recoveryObserved,recovery=4.0;end

pair.valid=true;
pair.failure_reason="";
pair.binding=binding;
pair.effect_strength=effect;
pair.recovery_time=recovery;
pair.recovery_observed=recoveryObserved;
pair.no_loss_degradation=degradation;
pair.sample_count=numel(t);
pair.timebase_alignment_applied=~sameTimebase;
end

function tf=matching_inputs(lossInputs,controlInputs)
names=["left_track_command","right_track_command","payload_mass", ...
    "terrain_friction","grade_angle","traction_event_time"];
tf=isfield(lossInputs,'left_traction_loss')&& ...
    isfield(controlInputs,'left_traction_loss')&& ...
    double(lossInputs.left_traction_loss)>0&& ...
    double(controlInputs.left_traction_loss)==0;
for index=1:numel(names)
    name=char(names(index));
    tf=tf&&isfield(lossInputs,name)&&isfield(controlInputs,name)&& ...
        isequaln(double(lossInputs.(name)),double(controlInputs.(name)));
end
end

function dt=paired_recovery(t,mL,sL,mZ,sZ,eventEnd)
dt=Inf;start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.35/median(diff(t))));
good=max(abs(sL(:,1:2)-sZ(:,1:2)),[],2)<=.08& ...
    abs(mL(:,4)-mZ(:,4))<=.12&abs(mL(:,5)-mZ(:,5))<=.15& ...
    max(abs(sL(:,3:4)-sZ(:,3:4)),[],2)<=.08;
lastStart=numel(t)-window+1;if start>lastStart,return;end
for index=start:lastStart
    if all(good(index:index+window-1))
        dt=t(index)-eventEnd;
        return
    end
end
end

function q=local_quantile(x,p)
x=double(x);if isempty(x),q=NaN;return;end
x=sort(x,1);n=size(x,1);index=max(1,min(n,ceil(p*n)));q=x(index,:);
end

function pair=empty_pair()
pair=struct( ...
    'valid',false, ...
    'loss_scenario',"traction_binding_probe", ...
    'control_scenario',"traction_binding_probe_no_loss", ...
    'failure_reason',"", ...
    'binding',NaN, ...
    'effect_strength',NaN, ...
    'recovery_time',NaN, ...
    'recovery_observed',false, ...
    'no_loss_degradation',NaN, ...
    'sample_count',0, ...
    'timebase_alignment_applied',false);
end
