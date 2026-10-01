function out=sat_d022_startup_diagnostic(sig,fundamentalHz)
%SAT_D022_STARTUP_DIAGNOSTIC Report-only cold-start evidence for D022.
% A 10%% final-value band is deliberately used: the purpose is to separate
% gross startup motion from settled operation, not to impose a fast-control
% design.  No value from this function enters the D022 total score.

if nargin<2||isempty(fundamentalHz),fundamentalHz=50;end
out=empty_result(fundamentalHz);
if ~isstruct(sig),out.detail="SIGNALS_MISSING";return;end
names=["Vdc","Speed","Psource"];
rows=repmat(empty_row(),1,numel(names));
for k=1:numel(names)
    if ~isfield(sig,names(k)),out.detail=names(k)+"_MISSING";return;end
    rows(k)=scalar_startup(sig.(names(k)),names(k));
end
if ~isfield(sig,'Vabc'),out.detail="VABC_MISSING";return;end
vrow=cycle_rms_startup(sig.Vabc,fundamentalHz);
out.signals=[rows vrow];out.valid=all([out.signals.valid]);
if out.valid
    out.q=geomean_nonzero([out.signals.q]);out.detail="OK";
else
    out.q=0;out.detail="ONE_OR_MORE_STARTUP_DIAGNOSTICS_INVALID";
end
end

function row=scalar_startup(s,name)
row=empty_row();row.name=name;
[t,y,ok]=series1(s);if ~ok,row.detail="INVALID_SERIES";return;end
n=numel(y);tail=max(1,floor(.8*n)):n;target=mean(y(tail));
scale=max(abs(target),max(abs(y(tail)))*1e-6+eps);
err=abs(y-target)/scale;row=finish_row(row,t,err,target);
end

function row=cycle_rms_startup(s,f)
row=empty_row();row.name="Vabc_A_cycle_rms";
if ~isstruct(s)||~isfield(s,'t')||~isfield(s,'Y')||size(s.Y,2)<3
    row.detail="INVALID_SERIES";return;
end
t=double(s.t(:));y=double(s.Y(:,1));
if numel(t)<16||numel(y)~=numel(t)||any(~isfinite(t))||any(~isfinite(y)) ...
        ||any(diff(t)<=0)||f<=0,row.detail="INVALID_SERIES";return;end
period=1/f;n=floor((t(end)-t(1))/period+1e-9);
if n<3,row.detail="INSUFFICIENT_COMPLETE_CYCLES";return;end
edges=t(1)+(0:n)*period;rmsv=nan(n,1);
for k=1:n
    lo=edges(k);hi=edges(k+1);inside=t>lo&t<hi;
    tt=[lo;t(inside);hi];yy=[interp1(t,y,lo);y(inside);interp1(t,y,hi)];
    rmsv(k)=sqrt(trapz(tt,yy.^2)/(hi-lo));
end
tail=max(1,floor(.8*n)):n;target=mean(rmsv(tail));
err=abs(rmsv-target)/max(abs(target),eps);
row=finish_row(row,edges(2:end).',err,target);
end

function row=finish_row(row,t,err,target)
band=.10;idx=NaN;
for k=1:numel(err),if all(err(k:end)<=band),idx=k;break;end,end
duration=max(t(end)-t(1),eps);
if isfinite(idx),settle=t(idx)-t(1);else,settle=duration;end
iae=mean(min(err,1));qTime=exp(-log(10)*min(max(settle/duration,0),1));
qErr=exp(-(log(10)/.10)*iae);
row.valid=true;row.detail="OK";row.target=target;row.band_frac=band;
row.settling_index=idx;row.settling_time_s=settle;
row.settling_time_fraction=settle/duration;row.normalized_iae=iae;
row.q_time=qTime;row.q_error=qErr;row.q=qTime*qErr;
end

function [t,y,ok]=series1(s)
t=[];y=[];ok=false;
if ~isstruct(s)||~isfield(s,'t')||~isfield(s,'Y')||isempty(s.Y),return;end
t=double(s.t(:));y=double(s.Y(:,1));ok=numel(t)>=16&&numel(y)==numel(t) ...
    &&all(isfinite(t))&&all(isfinite(y))&&all(diff(t)>0);
end
function q=geomean_nonzero(v)
v=min(max(double(v(:)),realmin),1);q=exp(mean(log(v)));
end
function row=empty_row()
row=struct('name',"",'valid',false,'detail',"UNINITIALIZED",'target',NaN, ...
    'band_frac',.10,'settling_index',NaN,'settling_time_s',NaN, ...
    'settling_time_fraction',NaN,'normalized_iae',NaN, ...
    'q_time',0,'q_error',0,'q',0);
end
function out=empty_result(f)
out=struct('schema',"simuverity.d022-startup-diagnostic.v1", ...
    'valid',false,'detail',"UNINITIALIZED",'fundamental_hz',double(f), ...
    'band_frac',.10,'q',0,'signals',repmat(empty_row(),1,0), ...
    'score_role',"report-only; excluded from total score");
end
