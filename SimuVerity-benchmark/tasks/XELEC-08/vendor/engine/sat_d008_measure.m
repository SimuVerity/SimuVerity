function out=sat_d008_measure(sig,spec,scenarioId)
%SAT_D008_MEASURE D008 cold-start plus all-phase grid-current quality.
%
% Grid-current THD
% is evaluated over the exact final five cycles in every declared scenario.
% Final-window stationarity is measured independently and enters D, so a
% mildly drifting window is not silently removed from the nine-scenario THD
% envelope while a materially non-stationary submission still loses temporal
% credit.

startup=sat_d008_startup_measurement(sig,spec,scenarioId);
out=struct('schema',"simuverity.d008-direct-measurement.v1", ...
    'scenario',string(scenarioId),'valid',false,'detail',"UNINITIALIZED", ...
    'cold_start',getfield_or(startup,'cold_start',struct()), ...
    'grid_current_quality',empty_quality());
if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D008"
    out.detail="NOT_D008";return;
end
if ~isstruct(sig)||~isfield(sig,'Igrid')
    out.detail="IGRID_MISSING";return;
end

q=measure_grid_quality(sig);
out.grid_current_quality=q;
out.valid=getbool(startup,'valid',false)&&q.valid;
if out.valid,out.detail="OK";
elseif ~getbool(startup,'valid',false),out.detail="COLD_START_INVALID";
else,out.detail="GRID_CURRENT_QUALITY_INVALID:"+q.detail;
end
end

function q=measure_grid_quality(sig)
q=empty_quality();s=sig.Igrid;
if ~validsig(s,3),q.detail="IGRID_INVALID";return;end
t=double(s.t(:));Y=double(s.Y(:,1:3));f0=50;cycles=5;
[st,tail]=stationarity(t,Y,f0,cycles);
q.valid=st.valid;q.steady=st.ok;q.steady_detail=st.detail;
q.steady_rel_range=st.rel_range;q.steady_rel_drift=st.rel_drift;
q.stationarity_q=st.q;q.stationarity_worst_q=min(st.q);
if ~st.valid,q.detail=st.detail;return;end
q.window_start_s=tail.t(1);q.window_end_s=tail.t(end);
q.window_cycles=cycles;q.fundamental_hz=f0;
fixedThd=nan(1,3);harm=nan(3,4);details=strings(1,3);
autoThd=nan(1,3);autoF0=nan(1,3);autoH5=nan(1,3);
gridFund=nan(1,3);gridHarm=nan(1,3);orders=[5 7 11 13];
cfg=struct('fundamental_hz',f0,'fundamental_search_frac',.05, ...
    'steady_fraction',1,'max_harmonic',40);
[tu,Yu]=uniform_exact_tail(t,Y,f0,cycles);
for p=1:3
    sp=series(tu,Yu(:,p));
    [autoThd(p),ok,detail]=sat_metrics('thd',{sp},cfg);
    details(p)=string(detail);if ~ok,autoThd(p)=NaN;end
    autoF0(p)=detail_f0(detail);
    if isfinite(autoF0(p))
        autoH5(p)=tone_amplitude(Yu(:,p),tu,5*autoF0(p))/ ...
            max(tone_amplitude(Yu(:,p),tu,autoF0(p)),eps);
    end
    amps=zeros(1,40);for h=1:40,amps(h)=tone_amplitude(Yu(:,p),tu,h*f0);end
    gridFund(p)=amps(1);gridHarm(p)=sqrt(sum(amps(2:end).^2));
    fixedThd(p)=gridHarm(p)/max(gridFund(p),eps);
    for k=1:numel(orders),harm(p,k)=amps(orders(k))/max(amps(1),eps);end
end
q.fixed_50_diagnostic_thd=fixedThd;q.Igrid_fundamental_peak=gridFund;
q.Igrid_harmonic_rss_peak=gridHarm;q.low_order_harmonic_orders=orders;
q.low_order_harmonic_ratio=harm;q.thd_detail=details;
q.thd_method="fixed_50Hz_projection_harmonics_2_to_40_exact_five_cycles";
q.auto_f0_diagnostic_hz=autoF0;q.auto_f0_diagnostic_thd=autoThd;
q.auto_f0_diagnostic_fifth_ratio=autoH5;
if isfield(sig,'Iload')&&validsig(sig.Iload,3)
    yl=interp1(double(sig.Iload.t(:)),double(sig.Iload.Y(:,1:3)),tu,'linear');
    if all(isfinite(yl),'all')
        loadFund=zeros(1,3);for p=1:3,loadFund(p)=tone_amplitude(yl(:,p),tu,f0);end
        q.Iload_fundamental_peak=loadFund;q.tdd_load_normalized=gridHarm./max(loadFund,eps);
        q.tdd_valid=all(isfinite(q.tdd_load_normalized));q.worst_phase_tdd=max(q.tdd_load_normalized);
    end
end
q.thd=fixedThd;q.thd_valid=all(isfinite(fixedThd));q.worst_phase_thd=max(fixedThd);

% Phase-A phasor diagnostics are report-only because the public Vpcc output
% is one physical PCC phase voltage rather than a three-phase voltage bus.
[diag,ok]=phase_a_diagnostics(sig,f0,cycles);
q.phase_a_diagnostics_valid=ok;q.displacement_pf_signed=diag.pf_signed;
q.displacement_pf_abs=diag.pf_abs;
q.residual_reactive_fraction=diag.residual_reactive_fraction;
q.compensation_completion_eta=diag.compensation_completion_eta;
q.fundamental_peak=diag.fundamental_peak;
if st.ok,q.detail="OK";else,q.detail="THD_SCORED_WITH_NONSTATIONARY_WINDOW_DIAGNOSTIC";end
end

function [st,tail]=stationarity(t,Y,f0,cycles)
st=struct('valid',false,'ok',false,'detail',"UNINITIALIZED", ...
    'rel_range',nan(1,3),'rel_drift',nan(1,3),'q',zeros(1,3));
tail=struct('t',zeros(0,1),'Y',zeros(0,3));T=1/f0;t1=t(end);t0=t1-cycles*T;
tol=max(1.5*median(diff(t)),1e-9);
if t0<t(1)-tol,st.detail="TAIL_TOO_SHORT";return;end
edges=t1-(cycles:-1:0)*T;z=nan(cycles,3);
for k=1:cycles
    % RMS must not depend on how a variable-step solver happened to place
    % samples inside a cycle.  Interpolate each exact 50 Hz cycle onto the
    % same grid and integrate in time; a raw sample mean is biased whenever
    % the solver's point density is correlated with waveform phase.
    ix=t>=edges(k)&t<=edges(k+1);
    if nnz(ix)<8,st.detail="CYCLE_"+k+"_TOO_SHORT";return;end
    tk=linspace(edges(k),edges(k+1),1025)';
    yk=interp1(t,Y,tk,'linear');
    if any(~isfinite(yk),'all'),st.detail="CYCLE_"+k+"_INTERPOLATION_INVALID";return;end
    z(k,:)=sqrt(trapz(tk,yk.^2,1)/T);
end
scale=max(abs(median(z,1)),1e-9);
rr=(max(z,[],1)-min(z,[],1))./scale;rd=zeros(1,3);x=(0:cycles-1)';
for p=1:3,fit=polyfit(x,z(:,p),1);rd(p)=abs(fit(1)*(cycles-1))/scale(p);end
st.valid=true;st.rel_range=rr;st.rel_drift=rd;st.ok=all(rr<=.10&rd<=.10);
u=max(rr,rd);st.q=arrayfun(@stationarity_q,u);
if st.ok,st.detail="STEADY_OK";else,st.detail="NOT_SETTLED";end
tt=linspace(t0,t1,cycles*1024+1)';yt=interp1(t,Y,tt,'linear');
tail=struct('t',tt,'Y',yt);
end

function [tu,Yu]=uniform_exact_tail(t,Y,f0,cycles)
t1=t(end);t0=t1-cycles/f0;tu=linspace(t0,t1,8193)';
Yu=interp1(t,Y,tu,'linear');
end

function f=detail_f0(detail)
f=NaN;tok=regexp(char(string(detail)),'f0=([0-9.eE+-]+)','tokens','once');
if ~isempty(tok),f=str2double(tok{1});end
end

function q=stationarity_q(v)
q=anchor(v,[0 .10 .15 .25 .50 1 2],[1 1 .95 .85 .60 .20 0]);
end

function [d,ok]=phase_a_diagnostics(sig,f0,cycles)
d=struct('pf_signed',NaN,'pf_abs',NaN,'residual_reactive_fraction',NaN, ...
    'compensation_completion_eta',NaN,'fundamental_peak',struct());ok=false;
needed={'Vpcc','Igrid','Iload','Icomp'};
if ~all(isfield(sig,needed)),return;end
if ~validsig(sig.Vpcc,1)||~validsig(sig.Igrid,3)|| ...
        ~validsig(sig.Iload,3)||~validsig(sig.Icomp,3),return;end
rows={sig.Vpcc,sig.Igrid,sig.Iload,sig.Icomp};starts=zeros(1,4);ends=zeros(1,4);
for k=1:4,starts(k)=rows{k}.t(1);ends(k)=rows{k}.t(end);end
t1=min(ends);t0=max(max(starts),t1-cycles/f0);if t1<=t0,return;end
tu=linspace(t0,t1,4097)';z=zeros(numel(tu),4);
z(:,1)=interp1(double(sig.Vpcc.t(:)),double(sig.Vpcc.Y(:,1)),tu,'linear');
z(:,2)=interp1(double(sig.Igrid.t(:)),double(sig.Igrid.Y(:,1)),tu,'linear');
z(:,3)=interp1(double(sig.Iload.t(:)),double(sig.Iload.Y(:,1)),tu,'linear');
z(:,4)=interp1(double(sig.Icomp.t(:)),double(sig.Icomp.Y(:,1)),tu,'linear');
if any(~isfinite(z),'all'),return;end
ph=zeros(1,4);for k=1:4,ph(k)=tone_phasor(z(:,k),tu,f0);end
delta=angle(ph(2))-angle(ph(1));pf=cos(delta);
iqGrid=abs(ph(2))*sin(delta);iqLoad=abs(ph(3))*sin(angle(ph(3))-angle(ph(1)));
res=abs(iqGrid)/max(abs(iqLoad),eps);
d.pf_signed=pf;d.pf_abs=abs(pf);d.residual_reactive_fraction=res;
d.compensation_completion_eta=1-res;
d.fundamental_peak=struct('Vpcc',2*abs(ph(1)),'Igrid',2*abs(ph(2)), ...
    'Iload',2*abs(ph(3)),'Icomp',2*abs(ph(4)));
ok=all(isfinite([d.pf_signed d.pf_abs res]));
end

function s=series(t,y),s=struct('t',t(:),'y',y(:),'Y',y(:));end
function a=tone_amplitude(y,t,f),a=2*abs(tone_phasor(y,t,f));end
function p=tone_phasor(y,t,f)
y=double(y(:));t=double(t(:));y=y-mean(y);dur=t(end)-t(1);
p=trapz(t,y.*exp(-1j*2*pi*f*t))/max(dur,eps);
end
function ok=validsig(s,nc)
ok=isstruct(s)&&isfield(s,'t')&&isfield(s,'Y')&&numel(s.t)>=16&& ...
    size(s.Y,1)==numel(s.t)&&size(s.Y,2)>=nc&&all(isfinite(s.t))&& ...
    all(isfinite(s.Y(:,1:nc)),'all')&&all(diff(double(s.t(:)))>0);
end
function q=empty_quality()
q=struct('schema',"simuverity.d008-grid-current-quality.v1", ...
    'valid',false,'steady',false,'steady_detail',"UNINITIALIZED", ...
    'steady_rel_range',nan(1,3),'steady_rel_drift',nan(1,3), ...
    'stationarity_q',zeros(1,3),'stationarity_worst_q',0, ...
    'window_start_s',NaN,'window_end_s',NaN,'window_cycles',5, ...
    'fundamental_hz',50,'thd',nan(1,3),'thd_valid',false, ...
    'worst_phase_thd',NaN,'thd_detail',strings(1,3), ...
    'thd_method',"fixed_50Hz_projection_harmonics_2_to_40_exact_five_cycles", ...
    'auto_f0_diagnostic_hz',nan(1,3),'auto_f0_diagnostic_thd',nan(1,3), ...
    'auto_f0_diagnostic_fifth_ratio',nan(1,3), ...
    'fixed_50_diagnostic_thd',nan(1,3),'Igrid_fundamental_peak',nan(1,3), ...
    'Igrid_harmonic_rss_peak',nan(1,3),'Iload_fundamental_peak',nan(1,3), ...
    'tdd_valid',false,'tdd_load_normalized',nan(1,3),'worst_phase_tdd',NaN, ...
    'low_order_harmonic_orders',[5 7 11 13], ...
    'low_order_harmonic_ratio',nan(3,4), ...
    'phase_a_diagnostics_valid',false,'displacement_pf_signed',NaN, ...
    'displacement_pf_abs',NaN,'residual_reactive_fraction',NaN, ...
    'compensation_completion_eta',NaN,'fundamental_peak',struct(), ...
    'detail',"UNINITIALIZED");
end
function q=anchor(v,x,y)
if ~isnumeric(v)||~isscalar(v)||~isfinite(v),q=0;return;end
v=min(max(double(v),x(1)),x(end));q=interp1(x,y,v,'linear');q=min(max(q,0),1);
end
function v=getfield_or(s,f,d),v=d;if isstruct(s)&&isscalar(s)&&isfield(s,f),v=s.(f);end,end
function v=getbool(s,f,d),v=d;if isstruct(s)&&isscalar(s)&&isfield(s,f)&&isscalar(s.(f))&&(islogical(s.(f))||isnumeric(s.(f))),v=logical(s.(f));end,end
