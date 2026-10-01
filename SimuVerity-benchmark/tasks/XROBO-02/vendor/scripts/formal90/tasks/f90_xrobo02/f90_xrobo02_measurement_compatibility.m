function varargout = f90_xrobo02_measurement_compatibility(helperName, varargin)
%f90_xrobo02_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xrobo02_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["run_scenario", "static_audit", "nominal_values", "empty_row"];
        end
    case "run_scenario"
        if nargout == 0
            run_scenario(varargin{:});
        else
            [varargout{1:nargout}] = run_scenario(varargin{:});
        end
    case "static_audit"
        if nargout == 0
            static_audit(varargin{:});
        else
            [varargout{1:nargout}] = static_audit(varargin{:});
        end
    case "nominal_values"
        if nargout == 0
            nominal_values(varargin{:});
        else
            [varargout{1:nargout}] = nominal_values(varargin{:});
        end
    case "empty_row"
        if nargout == 0
            empty_row(varargin{:});
        else
            [varargout{1:nargout}] = empty_row(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xrobo02_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function row = run_scenario(model,id,v,def)
row=empty_row;
row.id=id;
fields=fieldnames(v);
for k=1:numel(fields), assignin("base",fields{k},v.(fields{k})); end
out=sim(model,"StopTime",num2str(def.sim.stop), ...
    "ReturnWorkspaceOutputs","on");
names=["joint_state","end_effector_pose","joint_torque","coordination_state"];
channels=[28 12 14 4];
ts=cell(1,4);
for k=1:4
    ts{k}=simuverity_public_output_compatibility( ...
        out,names(k),channels(k),AllowBaseWorkspace=true);
end
for k=1:4
    data=normalize_data(ts{k});
    assert(size(data,2)==channels(k),"F90_XROBO02_CHANNEL_COUNT");
    assert(ts{k}.Time(1)<=1e-9 && ts{k}.Time(end)>=def.sim.stop-1e-6, ...
        "F90_XROBO02_TIME_COVERAGE");
    assert(all(isfinite(data),"all"),"F90_XROBO02_NONFINITE");
end
joint=normalize_data(ts{1}); pose=normalize_data(ts{2});
tau=normalize_data(ts{3}); coord=normalize_data(ts{4});
t=ts{1}.Time; q=joint(:,1:14); dq=joint(:,15:28);
target=[reshape(v.left_target_rad,1,7),reshape(v.right_target_rad,1,7)];
targetPose=local_pose(target);
idx=t>=7.4;
qFinal=mean(q(idx,:),1);
row.q_error_rms=sqrt(mean((qFinal-target).^2));
row.q_error_max=max(abs(qFinal-target));
poseFinal=mean(pose(ts{2}.Time>=7.4,:),1);
row.position_error_max=max([norm(poseFinal(1:3)-targetPose(1:3)), ...
    norm(poseFinal(7:9)-targetPose(7:9))]);
row.orientation_error_max=max(abs(wrap_pi( ...
    [poseFinal(4:6)-targetPose(4:6),poseFinal(10:12)-targetPose(10:12)])));
row.final_speed_max=max(abs(mean(dq(idx,:),1)));
limits=def.unscaled_torque_limits_nm*v.torque_limit_scale;
row.torque_ratio_max=max(max(abs(tau),[],1)./limits);
moveMask=ts{4}.Time>=.15*v.move_duration & ...
    ts{4}.Time<=1.10*v.move_duration;
row.sync_peak=max(coord(moveMask,3));
row.sync_final=mean(coord(ts{4}.Time>=7.4,3));
row.gripper_separation_final=mean(coord(ts{4}.Time>=7.4,4));
recalc=local_pose(qFinal);
row.pose_consistency_error=max(abs(poseFinal-recalc));
row.pose_consistency_score=quality(row.pose_consistency_error,1e-8,1e-4);
q0=def.initial_joint_position_rad;
row.target_motion_score=quality(1/(norm(qFinal-q0)+1e-9), ...
    1/(.45*norm(target-q0)+1e-9),1/(.08*norm(target-q0)+1e-9));

if any(abs(v.disturbance_torque_nm)>0)
    eventEnd=v.disturbance_start+.34;
    post=t>=max(eventEnd+.35,7.1);
    row.post_event_q_error_max=max(abs(mean(q(post,:),1)-target));
    row.post_event_speed_max=max(abs(mean(dq(post,:),1)));
    event=t>=v.disturbance_start & t<=eventEnd+.15;
    row.event_peak_speed=max(abs(dq(event,:)),[],"all");
    pre=ts{3}.Time>=max(.2,v.disturbance_start-.45) & ...
        ts{3}.Time<v.disturbance_start-.05;
    during=ts{3}.Time>=v.disturbance_start & ...
        ts{3}.Time<=eventEnd+.20;
    preMean=mean(abs(tau(pre,:)),"all");
    eventMean=mean(abs(tau(during,:)),"all");
    row.event_torque_response=abs(eventMean-preMean);
    row.event_response_score=quality(1/(row.event_torque_response+1e-9), ...
        1/.08,1/.005);
else
    row.post_event_q_error_max=row.q_error_max;
    row.post_event_speed_max=row.final_speed_max;
    row.event_peak_speed=max(abs(dq),[],"all");
    row.event_torque_response=0;
    row.event_response_score=1;
end
row.valid=true;
end

function s=static_audit(model)
joints=find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "MaskType","Revolute Joint");
motion=string(get_param(joints,"MotionActuationMode"));
torque=string(get_param(joints,"TorqueActuationMode"));
pos=string(get_param(joints,"SensePosition"));
vel=string(get_param(joints,"SenseVelocity"));
connected=false(1,numel(joints));
for k=1:numel(joints)
    ph=get_param(joints{k},"PortHandles");
    connected(k)=numel(ph.LConn)>=2 && get_param(ph.LConn(2),"Line")>=0;
end
traj=find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "RegExp","on","Name","Trajectory Profile|From Workspace|FromWorkspace");
s=struct;
s.revolute_joint_count=numel(joints);
s.joint_count_14=double(numel(joints)==14);
s.all_input_torque=double(all(torque=="InputTorque"));
s.all_computed_motion=double(all(motion=="ComputedMotion"));
s.all_position_sensed=double(all(pos=="on"));
s.all_velocity_sensed=double(all(vel=="on"));
s.all_torque_ports_connected=double(all(connected));
s.controller_present=double(~isempty(find_system(model,"SearchDepth",1, ...
    "Name","ClosedLoopTorqueController")));
s.no_prescribed_trajectory_blocks=double(isempty(traj));
s.prescribed_trajectory_blocks=traj;
end

function v=nominal_values(def)
v=struct;
for k=1:numel(def.public_inputs)
    v.(def.public_inputs(k).name)=def.public_inputs(k).nominal;
end
end

function r=empty_row
r=struct("id","","valid",false,"q_error_rms",Inf,"q_error_max",Inf, ...
    "position_error_max",Inf,"orientation_error_max",Inf, ...
    "final_speed_max",Inf,"torque_ratio_max",Inf,"sync_peak",Inf, ...
    "sync_final",Inf,"gripper_separation_final",NaN, ...
    "pose_consistency_error",Inf,"pose_consistency_score",0, ...
    "target_motion_score",0,"post_event_q_error_max",Inf, ...
    "post_event_speed_max",Inf,"event_peak_speed",Inf, ...
    "event_torque_response",0,"event_response_score",0);
end

function data=normalize_data(ts)
data=squeeze(ts.Data);
if size(data,1)~=numel(ts.Time) && size(data,2)==numel(ts.Time)
    data=data.';
end
end

function y=quality(x,good,bad)
if bad==good, y=double(x<=good); return; end
y=clip((bad-x)/(bad-good));
end

function x=wrap_pi(x), x=atan2(sin(x),cos(x)); end

function pose=local_pose(q)
TL=arm_fk(q(1:7),1); TR=arm_fk(q(8:14),-1);
pose=[TL(1:3,4).',to_rpy(TL(1:3,1:3)),TR(1:3,4).',to_rpy(TR(1:3,1:3))];
end

function y=clip(x), y=min(max(x,0),1); end

function T=arm_fk(q,side)
if side>0
    xyz=[.05355 .07250 .41492]; rpy=[.9781 -.5716 2.3180];
else
    xyz=[.05355 -.07250 .41492]; rpy=[-.9795 -.5682 -2.3155];
end
origxyz=[xyz;.03 0 .1;-.03 .17283 0;-.04188 0 .07873; ...
    .0405 .16461 0;-.027 0 .10039;.027 .029 0];
origrpy=[rpy;pi/2 0 0;-pi/2 0 0;pi/2 -pi/2 0;-pi/2 0 0; ...
    pi/2 0 0;-pi/2 0 0];
T=eye(4);
for k=1:7
    A=eye(4); A(1:3,1:3)=rpyrot(origrpy(k,:)); A(1:3,4)=origxyz(k,:).';
    J=eye(4); J(1:3,1:3)=[cos(q(k)) -sin(q(k)) 0; ...
        sin(q(k)) cos(q(k)) 0;0 0 1];
    T=T*A*J;
end
A=eye(4);A(1:3,1:3)=[-1 0 0;0 -1 0;0 0 1];A(3,4)=.007;T=T*A;
end

function a=to_rpy(R)
a=[atan2(R(3,2),R(3,3)), ...
    atan2(-R(3,1),sqrt(R(1,1)^2+R(2,1)^2)), ...
    atan2(R(2,1),R(1,1))];
end

function R=rpyrot(a)
cr=cos(a(1));sr=sin(a(1));cp=cos(a(2));sp=sin(a(2)); ...
cy=cos(a(3));sy=sin(a(3));
Rx=[1 0 0;0 cr -sr;0 sr cr];Ry=[cp 0 sp;0 1 0;-sp 0 cp]; ...
Rz=[cy -sy 0;sy cy 0;0 0 1];R=Rz*Ry*Rx;
end
