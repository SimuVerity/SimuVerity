function out=sat_d022_measure(sig,spec,scenarioId)
%SAT_D022_MEASURE All-phase ELC quality and cold-start diagnostics.
% The direct scorer owns the aggregation.  This helper only extracts
% physical measurements from the public D022 output contract.

scenarioId=string(scenarioId);out=empty_metrics(scenarioId);
if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D022"
    out.detail="NOT_D022";return;
end
required={'Vdc','Vabc','Iabc','Psource','Pload','Pdump','Speed'};
if ~isstruct(sig)||~all(isfield(sig,required))||~valid3(sig.Vabc) ...
        ||~valid3(sig.Iabc)||~all(cellfun(@(x)valid1(sig.(x)), ...
        {'Vdc','Psource','Pload','Pdump','Speed'}))
    out.detail="D022_PUBLIC_PHYSICAL_OUTPUTS_MISSING_OR_INVALID";return;
end

cfgAc=metric_cfg(spec,"rms");cfgAc.fundamental_hz=50;
cfgDc=metric_cfg(spec,"mean");
[out.Vabc_freq,okVfreq]=per_channel(sig.Vabc,"fund_freq",cfgAc,3);
[out.Vabc_thd,okVthd]=per_channel(sig.Vabc,"thd",cfgAc,3);
[out.Iabc_thd,okIthd]=per_channel(sig.Iabc,"thd",cfgAc,3);
[out.Vabc_imbalance,okVimb]=sat_metrics('imbalance',{sig.Vabc},cfgAc);
[out.Iabc_imbalance,okIimb]=sat_metrics('imbalance',{sig.Iabc},cfgAc);
[out.Vabc_sequence_minor_frac,out.Vabc_phase_step_error_deg, ...
    out.Vabc_dominant_sequence,okVseq]=fundamental_sequence(sig.Vabc,50, ...
    steady_cycles(spec));
[out.Iabc_sequence_minor_frac,out.Iabc_phase_step_error_deg, ...
    out.Iabc_dominant_sequence,okIseq]=fundamental_sequence(sig.Iabc,50, ...
    steady_cycles(spec));
out.VI_sequence_consistent=okVseq&&okIseq ...
    &&out.Vabc_dominant_sequence==out.Iabc_dominant_sequence;
[out.Vdc_ripple_pp_frac,okVdcRipple]=sat_metrics( ...
    'ripple_pp_frac',{sig.Vdc},cfgDc);
[out.Speed_ripple_pp_frac,okSpeedRipple]=sat_metrics( ...
    'ripple_pp_frac',{sig.Speed},cfgDc);
[out.Psource_ripple_pp_frac,okSourceRipple]=sat_metrics( ...
    'ripple_pp_frac',{sig.Psource},cfgDc);
[out.Pload_ripple_pp_frac,okLoadRipple]=sat_metrics( ...
    'ripple_pp_frac',{sig.Pload},cfgDc);
[out.Pdump_ripple_pp_frac,okDumpRipple]=sat_metrics( ...
    'ripple_pp_frac',{sig.Pdump},cfgDc);
[out.Psource_cycle_mean_ripple_pp_frac,okSourceCycle]=cycle_mean_ripple( ...
    sig.Psource,50,5);
[out.Pload_cycle_mean_ripple_pp_frac,okLoadCycle]=cycle_mean_ripple( ...
    sig.Pload,50,5);
[out.Pdump_cycle_mean_ripple_pp_frac,okDumpCycle]=cycle_mean_ripple( ...
    sig.Pdump,50,5);
out.power_cycle_trajectory=power_cycle_trajectory(sig,50);
out.dynamic_trace_valid=out.power_cycle_trajectory.valid;

out.quality_valid=all(okVfreq)&&all(okVthd)&&all(okIthd)&&okVimb&&okIimb ...
    &&okVseq&&okIseq ...
    &&okVdcRipple&&okSpeedRipple&&okSourceRipple&&okSourceCycle;
out.power_ripple_diagnostic_valid=okLoadRipple&&okDumpRipple&&okLoadCycle&&okDumpCycle;
out.startup=sat_d022_startup_diagnostic(sig,50);
out.valid=out.quality_valid&&out.dynamic_trace_valid;
out.detail=tern(out.valid,"OK","ONE_OR_MORE_D022_QUALITY_METRICS_INVALID");
end

function out=power_cycle_trajectory(sig,f)
% Common absolute-time, one-cycle means for paired counterfactual dynamics.
% Separate nominal/scenario simulations are compared later by the scorer;
% this extractor never assumes an implementation or an internal controller
% signal.  Absolute 50 Hz boundaries make independently simulated traces
% align even when their logging sample grids differ.
out=struct('schema',"simuverity.d022-power-cycle-trajectory.v1", ...
    'valid',false,'detail',"UNINITIALIZED",'fundamental_hz',double(f), ...
    'cycle_end_time',zeros(0,1),'Psource_mean',zeros(0,1), ...
    'Pload_mean',zeros(0,1),'Pdump_mean',zeros(0,1));
names={'Psource','Pload','Pdump'};
if ~isstruct(sig)||~all(isfield(sig,names))||f<=0|| ...
        ~all(cellfun(@(x)valid1(sig.(x)),names))
    out.detail="POWER_SIGNALS_INVALID";return;
end
starts=cellfun(@(x)double(sig.(x).t(1)),names);
stops=cellfun(@(x)double(sig.(x).t(end)),names);
period=1/f;firstEdge=ceil((max(starts)-1e-10)/period)*period;
lastEdge=floor((min(stops)+1e-10)/period)*period;
n=floor((lastEdge-firstEdge)/period+1e-9);
if n<10,out.detail="INSUFFICIENT_COMPLETE_CYCLES";return;end
edges=firstEdge+(0:n)'*period;means=nan(n,3);
for j=1:3
    s=sig.(names{j});t=double(s.t(:));y=double(s.Y(:,1));
    for k=1:n
        lo=edges(k);hi=edges(k+1);inside=t>lo&t<hi;
        tt=[lo;t(inside);hi];
        yy=[interp1(t,y,lo,'linear');y(inside);interp1(t,y,hi,'linear')];
        if any(~isfinite(yy)),out.detail="CYCLE_INTERPOLATION_FAILED";return;end
        means(k,j)=trapz(tt,yy)/(hi-lo);
    end
end
if any(~isfinite(means),'all'),out.detail="CYCLE_MEANS_INVALID";return;end
out.valid=true;out.detail="OK";out.cycle_end_time=edges(2:end);
out.Psource_mean=means(:,1);out.Pload_mean=means(:,2);out.Pdump_mean=means(:,3);
end

function n=steady_cycles(spec)
n=5;
if isstruct(spec)&&isfield(spec,'steady_state_policy') ...
        &&isstruct(spec.steady_state_policy) ...
        &&isfield(spec.steady_state_policy,'steady_cycles') ...
        &&isnumeric(spec.steady_state_policy.steady_cycles) ...
        &&isscalar(spec.steady_state_policy.steady_cycles) ...
        &&isfinite(spec.steady_state_policy.steady_cycles) ...
        &&spec.steady_state_policy.steady_cycles>=2
    n=double(spec.steady_state_policy.steady_cycles);
end
end

function [minorFrac,phaseErrDeg,dominant,ok]=fundamental_sequence(s,f,nCycles)
% Fit the three fundamental phasors over an integer-cycle terminal window.
% The minor/dominant symmetrical-component ratio is zero for an ideal
% three-phase set.  Either phase order is legal; the scorer separately
% requires voltage and current to use the same dominant order.
minorFrac=NaN;phaseErrDeg=NaN;dominant=0;ok=false;
if ~valid3(s)||~isfinite(f)||f<=0||~isfinite(nCycles)||nCycles<2,return;end
t=double(s.t(:));Y=double(s.Y(:,1:3));t0=t(end)-nCycles/f;
keep=t>=t0;if nnz(keep)<16,return;end
t=t(keep);Y=Y(keep,:);w=2*pi*f;
H=[cos(w*t) sin(w*t) ones(size(t))];
if rank(H)<3,return;end
coef=H\Y;X=coef(1,:)-1i*coef(2,:);
if any(~isfinite(real(X)))||any(~isfinite(imag(X)))||max(abs(X))<=eps,return;end
a=exp(1i*2*pi/3);
pos=(X(1)+a*X(2)+a^2*X(3))/3;
neg=(X(1)+a^2*X(2)+a*X(3))/3;
if abs(pos)>=abs(neg),major=abs(pos);minor=abs(neg);dominant=1;step=-120;
else,major=abs(neg);minor=abs(pos);dominant=-1;step=120;end
if major<=eps,return;end
minorFrac=minor/major;
phase=180/pi*angle(X);
errB=abs(wrap180((phase(2)-phase(1))-step));
errC=abs(wrap180((phase(3)-phase(1))+step));
phaseErrDeg=max(errB,errC);
ok=isfinite(minorFrac)&&isfinite(phaseErrDeg)&&any(dominant==[-1 1]);
end

function x=wrap180(x),x=mod(x+180,360)-180;end

function [value,ok]=cycle_mean_ripple(s,f,nCycles)
value=NaN;ok=false;
if ~valid1(s)||f<=0||nCycles<2,return;end
t=double(s.t(:));y=double(s.Y(:,1));period=1/f;
endTime=t(end);startTime=endTime-nCycles*period;
if startTime<t(1),return;end
edges=startTime+(0:nCycles)*period;means=nan(1,nCycles);
for k=1:nCycles
    lo=edges(k);hi=edges(k+1);inside=t>lo&t<hi;
    tt=[lo;t(inside);hi];yy=[interp1(t,y,lo);y(inside);interp1(t,y,hi)];
    means(k)=trapz(tt,yy)/(hi-lo);
end
den=max(abs(mean(means)),eps);value=(max(means)-min(means))/den;
ok=isfinite(value);
end

function b=metric_cfg(spec,steadyStat)
b=struct('steady_fraction',0.2,'fundamental_hz',50,'max_harmonic',40);
if isfield(spec,'steady_state_policy')&&isstruct(spec.steady_state_policy)
    p=spec.steady_state_policy;names=fieldnames(p);
    for k=1:numel(names),b.(names{k})=p.(names{k});end
end
b.steady_stat=char(steadyStat);
end

function [values,oks]=per_channel(s,metric,b,n)
values=nan(1,n);oks=false(1,n);
for k=1:n
    one=s;one.y=double(s.Y(:,k));one.Y=one.y;
    [values(k),oks(k)]=sat_metrics(metric,{one},b);
end
end

function tf=valid3(s)
tf=isstruct(s)&&isfield(s,'Y')&&isfield(s,'t')&&size(s.Y,2)>=3 ...
    &&size(s.Y,1)==numel(s.t)&&size(s.Y,1)>=16 ...
    &&all(isfinite(s.Y(:,1:3)),'all')&&all(isfinite(s.t)) ...
    &&all(diff(double(s.t(:)))>0);
end
function tf=valid1(s)
tf=isstruct(s)&&isfield(s,'Y')&&isfield(s,'t')&&size(s.Y,2)>=1 ...
    &&size(s.Y,1)==numel(s.t)&&size(s.Y,1)>=16 ...
    &&all(isfinite(s.Y(:,1)))&&all(isfinite(s.t)) ...
    &&all(diff(double(s.t(:)))>0);
end
function out=empty_metrics(scenario)
out=struct('schema',"simuverity.d022-direct-measurement.v1", ...
    'scenario',scenario,'valid',false,'quality_valid',false, ...
    'power_ripple_diagnostic_valid',false,'dynamic_trace_valid',false, ...
    'detail',"UNINITIALIZED", ...
    'Vabc_freq',nan(1,3),'Vabc_thd',nan(1,3),'Iabc_thd',nan(1,3), ...
    'Vabc_imbalance',NaN,'Iabc_imbalance',NaN, ...
    'Vabc_sequence_minor_frac',NaN,'Iabc_sequence_minor_frac',NaN, ...
    'Vabc_phase_step_error_deg',NaN,'Iabc_phase_step_error_deg',NaN, ...
    'Vabc_dominant_sequence',0,'Iabc_dominant_sequence',0, ...
    'VI_sequence_consistent',false, ...
    'Vdc_ripple_pp_frac',NaN,'Speed_ripple_pp_frac',NaN, ...
    'Psource_ripple_pp_frac',NaN,'Pload_ripple_pp_frac',NaN, ...
    'Pdump_ripple_pp_frac',NaN,'Psource_cycle_mean_ripple_pp_frac',NaN, ...
    'Pload_cycle_mean_ripple_pp_frac',NaN, ...
    'Pdump_cycle_mean_ripple_pp_frac',NaN, ...
    'power_cycle_trajectory',struct('schema', ...
      "simuverity.d022-power-cycle-trajectory.v1",'valid',false, ...
      'detail',"UNINITIALIZED",'fundamental_hz',50, ...
      'cycle_end_time',zeros(0,1),'Psource_mean',zeros(0,1), ...
      'Pload_mean',zeros(0,1),'Pdump_mean',zeros(0,1)),'startup', ...
    sat_d022_startup_diagnostic(struct(),50));
end
function x=tern(c,a,b),if c,x=a;else,x=b;end,end
