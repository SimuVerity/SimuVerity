function facts=f90_xmech04_build_evidence(runs,spec)
%f90_xmech04_build_evidence Add per-channel activity without scoring.
facts=f90_xmech04_build_evidence_core(runs,spec);
motion=NaN(numel(runs),6);
actuation=NaN(numel(runs),6);
for index=1:numel(runs)
    if string(runs(index).stage)~="simulated",continue;end
    [~,state,okState]=xp9_series(runs(index),'joint_state',12);
    [~,torque,okTorque]=xp9_series(runs(index),'joint_torque',6);
    if ~(okState&&okTorque),continue;end
    limits=[80 70 60 22 18 14]*double(runs(index).inputs.torque_limit_scale);
    motion(index,:)=max(state(:,1:6),[],1)-min(state(:,1:6),[],1);
    actuation(index,:)=local_quantile(abs(torque)./limits,.90);
end
jointMotion=max(motion,[],1,'omitnan');
actuatorActivity=max(actuation,[],1,'omitnan');
valid=numel(jointMotion)==6&&numel(actuatorActivity)==6&& ...
    all(isfinite(jointMotion))&&all(isfinite(actuatorActivity));
facts.channel_activity=struct( ...
    'schema',"simuverity.f90-xmech04-channel-activity.v1", ...
    'valid',valid, ...
    'aggregation',"per_channel_maximum_across_locked_scenarios", ...
    'joint_motion_range_rad',jointMotion, ...
    'actuator_activity_ratio',actuatorActivity);
end

function q=local_quantile(x,p)
x=sort(double(x),1);n=size(x,1);
if n==0,q=NaN(1,max(1,size(x,2)));return;end
k=max(1,min(n,ceil(p*n)));q=x(k,:);
end
