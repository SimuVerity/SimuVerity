function result=sat_D028_phase_lattice(groups,cfg)
%SAT_D028_PHASE_LATTICE Rotation-invariant four-class 24-pulse lattice.

minGroups=getnum(cfg,'min_active_six_pulse_groups',4);
period=getnum(cfg,'phase_period_deg',60);
step=getnum(cfg,'ideal_group_step_deg',15);
tol=getnum(cfg,'max_phase_lattice_error_deg',0.5);
result=struct('valid',false,'ok',false,'reason',"INVALID_GROUPS", ...
    'active_group_count',0,'normalized_phases',[],'global_rotation_deg',NaN, ...
    'class_indices',[],'class_errors_deg',[],'distinct_class_count',0, ...
    'min_active_six_pulse_groups',minGroups,'phase_period_deg',period, ...
    'ideal_group_step_deg',step,'max_phase_lattice_error_deg',tol);
% Evidence is recorded even for a failing control.  Use an empty
% value for "not resolved" instead of NaN so a legitimate negative verdict
% cannot be converted into an infrastructure error by the finite-number
% evidence contract.
result.global_rotation_deg=[];
if ~isstruct(groups)||period<=0||step<=0||tol<0||abs(period/step-round(period/step))>1e-12,return;end
if isempty(groups),result.valid=true;result.reason="TOO_FEW_ACTIVE_GROUPS";return;end
active=true(1,numel(groups));if isfield(groups,'active'),active=logical([groups.active]);end
if ~isfield(groups,'phase_deg'),return;end
ph=double([groups(active).phase_deg]);
if any(~isfinite(ph)),result.reason="ACTIVE_GROUP_PHASE_UNRESOLVED";return;end
ph=mod(ph,period);ph(abs(ph-period)<1e-9|abs(ph)<1e-9)=0;
result.valid=true;result.active_group_count=numel(ph);result.normalized_phases=ph;
if numel(ph)<minGroups,result.reason="TOO_FEW_ACTIVE_GROUPS";return;end
nClasses=round(period/step);classes=(0:nClasses-1)*step;
rotations=[];for i=1:numel(ph),rotations=[rotations mod(ph(i)-classes,period)];end %#ok<AGROW>
rotations=unique(round(rotations*1e12)/1e12);
best=inf;bestRot=NaN;bestClass=[];bestErr=[];bestDistinct=0;
for r=rotations
    shifted=mod(ph-r,period);idx=zeros(size(ph));err=zeros(size(ph));
    for i=1:numel(ph)
        dist=abs(mod(shifted(i)-classes+period/2,period)-period/2);
        [err(i),idx(i)]=min(dist);
    end
    distinct=numel(unique(idx));objective=max(err)+double(distinct<nClasses)*period;
    if objective<best,best=objective;bestRot=r;bestClass=idx;bestErr=err;bestDistinct=distinct;end
end
result.global_rotation_deg=bestRot;result.class_indices=bestClass-1;
result.class_errors_deg=bestErr;result.distinct_class_count=bestDistinct;
result.ok=logical(bestDistinct==nClasses&&all(bestErr<=tol+64*eps(max(1,tol))));
if result.ok,result.reason="OK";
elseif bestDistinct<nClasses,result.reason="PHASE_CLASSES_INCOMPLETE";
else,result.reason="PHASE_LATTICE_ERROR_EXCEEDED";end
end
function v=getnum(s,f,d),v=d;if isstruct(s)&&isfield(s,f)&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)),v=double(s.(f));end,end
