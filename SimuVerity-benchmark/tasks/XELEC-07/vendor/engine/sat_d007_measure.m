function out=sat_d007_measure(sig,spec,scenarioId)
%SAT_D007_MEASURE All-scenario, all-phase D007 physical measurements.
% The evaluator derives implementation-neutral in-phase/quadrature current
% and fundamental P/Q from the physical Vout/Igrid waveforms.  It never
% reads an agent's internal dq signals or assumes a PI/PWM implementation.

scenarioId=string(scenarioId);out=empty_metrics(scenarioId);
if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D007"
    out.detail="NOT_D007";return;
end
if ~isstruct(sig)||~isfield(sig,'Vout')||~isfield(sig,'Igrid') ...
        ||~valid3(sig.Vout)||~valid3(sig.Igrid)
    out.detail="THREE_PHASE_VOLTAGE_OR_CURRENT_MISSING";return;
end
v=sig.Vout;i=sig.Igrid;

[out.Vout_rms,okVrms]=per_channel(v,"rms",cfg(spec,"i_rms_witness"),3);
[out.Igrid_rms,okIrms]=per_channel(i,"rms",cfg(spec,"i_rms_witness"),3);
[out.Vout_freq,okFreq]=per_channel(v,"fund_freq",cfg(spec,"v_freq"),3);
[out.Vout_thd,okVthd]=per_channel(v,"thd",cfg(spec,"v_thd"),3);
[out.Igrid_thd,okIthd]=per_channel(i,"thd",cfg(spec,"i_thd"),3);
[out.signed_pf,okPf]=per_channel_pair(v,i,"power_factor_signed", ...
    cfg(spec,"signed_pf"),3);
[out.phase_deg,okPhase]=per_channel_pair(v,i,"phase_angle_deg", ...
    cfg(spec,"signed_phase"),3);
[out.Vout_imbalance,okVimb]=sat_metrics('imbalance',{v}, ...
    cfg(spec,"vout_balance_nom"));
[out.Igrid_imbalance,okIimb]=sat_metrics('imbalance',{i}, ...
    cfg(spec,"igrid_balance_nom"));
[out.Vout_duplicate_corr,okVcorr]=duplicate_corr(v,spec,50);
[out.Igrid_duplicate_corr,okIcorr]=duplicate_corr(i,spec,50);

ph=fundamental_components(v,i,spec,50);
out.fundamental_voltage_rms=ph.voltage_rms;
out.fundamental_current_rms=ph.current_rms;
out.fundamental_current_fraction=ph.current_fraction;
out.active_current=ph.active_current;
out.quadrature_lag_current=ph.quadrature_lag_current;
out.fundamental_phase_deg=ph.phase_deg;
out.P_fundamental_phase=ph.P_phase;
out.Q_fundamental_phase=ph.Q_phase;
out.P_fundamental_total=sum(ph.P_phase);
out.Q_fundamental_total=sum(ph.Q_phase);
out.Vout_sequence_index=ph.voltage_sequence_index;
out.Igrid_sequence_index=ph.current_sequence_index;
out.sequence_order_consistent=ph.sequence_order_consistent;
out.phasor_valid=ph.valid;
out.cycle_response=sat_d007_cycle_response(i,50);

out.Igrid_rms_valid=all(okIrms);out.phase_valid=all(okPhase);
out.valid=all(okVrms)&&out.Igrid_rms_valid&&all(okFreq)&&all(okVthd) ...
    &&all(okIthd)&&all(okPf)&&out.phase_valid&&okVimb&&okIimb ...
    &&okVcorr&&okIcorr&&ph.valid;
out.detail=tern(out.valid,"OK","SCENARIO_METRICS_INVALID");
end

function ph=fundamental_components(v,i,spec,f0)
ph=struct('valid',false,'voltage_rms',nan(1,3), ...
    'current_rms',nan(1,3),'current_fraction',nan(1,3), ...
    'active_current',nan(1,3),'quadrature_lag_current',nan(1,3), ...
    'phase_deg',nan(1,3),'P_phase',nan(1,3),'Q_phase',nan(1,3), ...
    'voltage_sequence_index',NaN,'current_sequence_index',NaN, ...
    'sequence_order_consistent',false);
[t,vY,ok]=steady_matrix(v,spec,f0);if ~ok,return;end
iY=interp1(double(i.t(:)),double(i.Y(:,1:3)),t,'linear',NaN);
if any(~isfinite(iY),'all'),return;end
w=2*pi*f0;T=t(end)-t(1);if T<=0,return;end
vp=zeros(1,3);ip=zeros(1,3);
for k=1:3
    vv=vY(:,k)-mean(vY(:,k));ii=iY(:,k)-mean(iY(:,k));
    basis=exp(-1j*w*t);
    vp(k)=sqrt(2)/T*trapz(t,vv.*basis);
    ip(k)=sqrt(2)/T*trapz(t,ii.*basis);
end
if any(~isfinite(vp))||any(~isfinite(ip))||any(abs(vp)<eps),return;end
relative=ip.*conj(vp)./abs(vp);
ph.voltage_rms=abs(vp);ph.current_rms=abs(ip);
ph.active_current=real(relative);
% Positive means current lags voltage, matching D007's positive-Iq prompt.
ph.quadrature_lag_current=-imag(relative);
ph.phase_deg=rad2deg(angle(ip.*conj(vp)));
complexPower=vp.*conj(ip);
ph.P_phase=real(complexPower);ph.Q_phase=imag(complexPower);
totalRms=sqrt(trapz(t,(iY-mean(iY,1)).^2,1)/T);
ph.current_fraction=ph.current_rms./max(totalRms,eps);
[ph.voltage_sequence_index,vSeqOk]=sequence_index(vp);
[ph.current_sequence_index,iSeqOk]=sequence_index(ip);
ph.sequence_order_consistent=vSeqOk&&iSeqOk&& ...
    sign(ph.voltage_sequence_index)==sign(ph.current_sequence_index);
ph.valid=all(isfinite([ph.voltage_rms ph.current_rms ...
    ph.current_fraction ph.active_current ph.quadrature_lag_current ...
    ph.phase_deg ph.P_phase ph.Q_phase ph.voltage_sequence_index ...
    ph.current_sequence_index]));
end

function [idx,ok]=sequence_index(x)
% Signed symmetrical-component dominance.  +1 and -1 are equally valid
% phase orders; zero means that no unique three-phase fundamental order is
% present.  The scorer separately requires Vout and Igrid to agree.
idx=NaN;ok=false;x=reshape(x,1,[]);if numel(x)<3,return;end
a=exp(1j*2*pi/3);
positive=(x(1)+a*x(2)+a^2*x(3))/3;
negative=(x(1)+a^2*x(2)+a*x(3))/3;
p=abs(positive);n=abs(negative);den=p+n;
if ~isfinite(den)||den<=1e-9,return;end
idx=(p-n)/den;ok=isfinite(idx);
end

function [value,ok]=duplicate_corr(s,spec,f0)
[~,Y,ok]=steady_matrix(s,spec,f0);value=NaN;if ~ok,return;end
c=corrcoef(Y);off=abs(c(~eye(3)));ok=~isempty(off)&&all(isfinite(off));
if ok,value=max(off);end
end

function [t,Y,ok]=steady_matrix(s,spec,f0)
t=double(s.t(:));Y=double(s.Y(:,1:3));ok=false;
if numel(t)<16||size(Y,1)~=numel(t),return;end
fraction=.2;cycles=2;
if isfield(spec,'steady_state_policy')&&isstruct(spec.steady_state_policy)
    p=spec.steady_state_policy;
    fraction=getnum(p,'steady_fraction',fraction);
    cycles=getnum(p,'steady_cycles',cycles);
end
duration=t(end)-t(1);window=max(fraction*duration,cycles/f0);
start=max(t(1),t(end)-window);keep=t>=start;
t=t(keep);Y=Y(keep,:);ok=numel(t)>=16&&all(isfinite(Y),'all')&&all(diff(t)>0);
end

function b=cfg(spec,id)
b=struct();
if strlength(id)>0&&isfield(spec,'behavioral')
    for k=1:numel(spec.behavioral)
        x=elem(spec.behavioral,k);
        if isfield(x,'id')&&string(x.id)==id,b=x;break;end
    end
end
if ~isfield(b,'fundamental_hz'),b.fundamental_hz=50;end
if isfield(spec,'steady_state_policy')&&isstruct(spec.steady_state_policy)
    names=fieldnames(spec.steady_state_policy);
    for k=1:numel(names)
        if ~isfield(b,names{k}),b.(names{k})=spec.steady_state_policy.(names{k});end
    end
end
end
function [values,oks]=per_channel(s,metric,b,n)
values=nan(1,n);oks=false(1,n);
for k=1:n
    one=s;one.y=double(s.Y(:,k));one.Y=one.y;
    [values(k),oks(k)]=sat_metrics(metric,{one},b);
end
end
function [values,oks]=per_channel_pair(a,b,metric,cfgValue,n)
values=nan(1,n);oks=false(1,n);
for k=1:n
    x=a;x.y=double(a.Y(:,k));x.Y=x.y;
    y=b;y.y=double(b.Y(:,k));y.Y=y.y;
    [values(k),oks(k)]=sat_metrics(metric,{x,y},cfgValue);
end
end
function tf=valid3(s)
tf=isstruct(s)&&isfield(s,'Y')&&isfield(s,'t')&&size(s.Y,2)>=3 ...
    &&size(s.Y,1)==numel(s.t)&&size(s.Y,1)>=16 ...
    &&all(isfinite(s.Y(:,1:3)),'all')&&all(isfinite(s.t)) ...
    &&all(diff(double(s.t(:)))>0);
end
function out=empty_metrics(scenario)
out=struct('schema',"simuverity.d007-direct-measurement.v1", ...
    'scenario',scenario,'valid',false,'detail',"UNINITIALIZED", ...
    'Vout_rms',nan(1,3),'Igrid_rms',nan(1,3), ...
    'Igrid_rms_valid',false,'phase_deg',nan(1,3),'phase_valid',false, ...
    'Vout_freq',nan(1,3),'Vout_thd',nan(1,3),'Igrid_thd',nan(1,3), ...
    'signed_pf',nan(1,3),'Vout_imbalance',NaN,'Igrid_imbalance',NaN, ...
    'Vout_duplicate_corr',NaN,'Igrid_duplicate_corr',NaN, ...
    'fundamental_voltage_rms',nan(1,3),'fundamental_current_rms',nan(1,3), ...
    'fundamental_current_fraction',nan(1,3),'active_current',nan(1,3), ...
    'quadrature_lag_current',nan(1,3),'fundamental_phase_deg',nan(1,3), ...
    'P_fundamental_phase',nan(1,3),'Q_fundamental_phase',nan(1,3), ...
    'P_fundamental_total',NaN,'Q_fundamental_total',NaN, ...
    'Vout_sequence_index',NaN,'Igrid_sequence_index',NaN, ...
    'sequence_order_consistent',false, ...
    'phasor_valid',false,'cycle_response',sat_d007_cycle_response(struct(),50));
end
function x=elem(a,i),if iscell(a),x=a{i};else,x=a(i);end,end
function v=getnum(s,f,d),v=d;if isstruct(s)&&isscalar(s)&&isfield(s,f)&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)),v=double(s.(f));end,end
function x=tern(c,a,b),if c,x=a;else,x=b;end,end
