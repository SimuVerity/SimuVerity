function varargout=f90_xmech01_measurement_compat(helperName,varargin)
%F90_XMECH01_MEASUREMENT_COMPAT Variable-timebase loss-pair recovery.
helperName=char(string(helperName));
if helperName~="measure_suite"
    if nargout==0
        f90_xmech01_measurement_compat_core(helperName,varargin{:});
    else
        [varargout{1:nargout}]=f90_xmech01_measurement_compat_core(helperName,varargin{:});
    end
    return;
end
assert(nargout<=1,"SimuVerity:f90_xmech01_measurement_compat:MeasureSuiteOutputs", ...
    "The suite measurement has one output.");
s=f90_xmech01_measurement_compat_core("measure_suite",varargin{:});
if ~s.paired_valid
    runs=varargin{1};rows=varargin{2};
    [s.paired_valid,s.paired_binding,s.paired_effect_strength, ...
        s.paired_recovery_time,s.paired_no_loss_degradation, ...
        s.paired_loss_index,s.paired_loss_scenario]=measure_loss_pair_variable_timebase(runs);
    s.max_contact_binding=max([[rows.contact_binding],s.paired_binding]);
    s.slip_activity_required=isfinite(s.max_contact_binding)&&s.max_contact_binding>=.55;
    kinOK=all(isfinite([s.planar_kinematic_residual s.yaw_kinematic_residual ...
        s.coordinate_sign s.heading_offset]));
    s.valid=s.track_passive&&s.chassis_passive&&kinOK&&s.paired_valid&& ...
        all(isfinite([s.track_power_residual s.chassis_power_residual ...
        s.contact_force_sign s.drive_force_sign s.contact_power_direction_violation ...
        s.drive_activity s.track_motion_activity s.contact_force_activity ...
        s.vehicle_motion_activity s.slip_activity s.max_contact_binding ...
        s.planar_kinematic_residual s.yaw_kinematic_residual s.paired_binding ...
        s.paired_effect_strength s.paired_no_loss_degradation s.paired_loss_index]))&& ...
        ~isnan(s.paired_recovery_time);
end
if nargout==1,varargout{1}=s;end
end

function [valid,binding,effect,recovery,degradation,lossIndex,lossScenario]= ...
    measure_loss_pair_variable_timebase(runs)
valid=false;binding=NaN;effect=NaN;recovery=NaN;degradation=NaN;
lossIndex=NaN;lossScenario="";bestBinding=-Inf;names=string({runs.scenario});
for candidate=1:numel(runs)
    if names(candidate)=="nominal"
        controlName="paired_no_loss";
    elseif endsWith(names(candidate),"_no_loss")
        continue;
    else
        controlName=names(candidate)+"_no_loss";
    end
    iZero=find(names==controlName,1);if isempty(iZero),continue;end
    [pairValid,pairBinding,pairEffect,pairRecovery,pairDegradation]= ...
        measure_one_loss_pair_variable_timebase(runs,candidate,iZero);
    if pairValid&&pairBinding>bestBinding
        valid=true;bestBinding=pairBinding;binding=pairBinding;effect=pairEffect;
        recovery=pairRecovery;degradation=pairDegradation;
        lossIndex=candidate;lossScenario=names(candidate);
    end
end
end

function [valid,binding,effect,recovery,degradation]= ...
    measure_one_loss_pair_variable_timebase(runs,iLoss,iZero)
valid=false;binding=NaN;effect=NaN;recovery=NaN;degradation=NaN;
[tL,mL,ok1]=xp9_series(runs(iLoss),'vehicle_motion',5);
[tZ,mZ,ok2]=xp9_series(runs(iZero),'vehicle_motion',5);
[t2,sL,ok3]=xp9_series(runs(iLoss),'track_state',4);
[t3,sZ,ok4]=xp9_series(runs(iZero),'track_state',4);
[t4,cL,ok5]=xp9_series(runs(iLoss),'terrain_contact',4);
[t5,cZ,ok6]=xp9_series(runs(iZero),'terrain_contact',4);
if ~(ok1&&ok2&&ok3&&ok4&&ok5&&ok6&&isequal(tL,t2)&& ...
        isequal(tL,t4)&&isequal(tZ,t3)&&isequal(tZ,t5)),return;end
[t,loss,control,aligned]=formal90_align_pair_timebase( ...
    tL,[mL,sL,cL],tZ,[mZ,sZ,cZ],max(tL(1),tZ(1)),min(tL(end),tZ(end)));
if ~aligned,return;end
mL=loss(:,1:5);sL=loss(:,6:9);cL=loss(:,10:13);
mZ=control(:,1:5);sZ=control(:,6:9);
event=double(runs(iLoss).inputs.traction_event_time);eventEnd=event+1.2;
evt=t>=event+.08&t<=eventEnd-.05;
post=t>=eventEnd+.6&t<=min(t(end),eventEnd+1.6);
if nnz(evt)<60||nnz(post)<30,return;end
mu=double(runs(iLoss).inputs.terrain_friction)* ...
    (1-double(runs(iLoss).inputs.left_traction_loss));
binding=local_quantile(abs(cL(evt,1))./max(mu*cL(evt,3),100),.95);
width=1.2;
motion=max(median(abs(mL(evt,4)-mZ(evt,4)))/max(median(abs(mZ(evt,4))),.30), ...
    width*median(abs(mL(evt,5)-mZ(evt,5)))/ ...
    max(abs(double(runs(iLoss).inputs.right_track_command)- ...
    double(runs(iLoss).inputs.left_track_command)),.20));
slip=max(median(abs(sL(evt,3:4)-sZ(evt,3:4))));
force=max(median(abs(cL(evt,1:2)-control(evt,10:11))))/ ...
    max((720+double(runs(iLoss).inputs.payload_mass))*9.81,1);
effect=max([motion slip force]);
degradation=max([median(abs(sL(post,1:2)-sZ(post,1:2)),'all')/ ...
    max(mean(abs(sZ(post,1:2)),'all'),.30), ...
    median(abs(mL(post,4)-mZ(post,4)))/max(median(abs(mZ(post,4))),.30), ...
    width*median(abs(mL(post,5)-mZ(post,5)))/ ...
    max(abs(double(runs(iLoss).inputs.right_track_command)- ...
    double(runs(iLoss).inputs.left_track_command)),.20)]);
recovery=paired_recovery(t,mL,sL,mZ,sZ,eventEnd);
valid=all(isfinite([binding effect degradation]))&&~isnan(recovery);
end

function dt=paired_recovery(t,mL,sL,mZ,sZ,eventEnd)
dt=Inf;start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.35/median(diff(t))));
good=max(abs(sL(:,1:2)-sZ(:,1:2)),[],2)<=.08& ...
    abs(mL(:,4)-mZ(:,4))<=.12&abs(mL(:,5)-mZ(:,5))<=.15& ...
    max(abs(sL(:,3:4)-sZ(:,3:4)),[],2)<=.08;
lastStart=numel(t)-window+1;if start>lastStart,return;end
for k=start:lastStart
    if all(good(k:k+window-1)),dt=t(k)-eventEnd;return;end
end
end

function q=local_quantile(x,p)
x=double(x);if isempty(x),q=NaN;return;end
x=sort(x,1);n=size(x,1);k=max(1,min(n,ceil(p*n)));q=x(k,:);
end
