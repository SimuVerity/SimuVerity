function out=sat_d006_measure(sig,spec,scenarioId)
%SAT_D006_MEASURE Algorithm-neutral cold-start evidence for D006.
out=struct('schema',"simuverity.d006-direct-measurement.v1",'scenario',string(scenarioId),'valid',false,'detail',"UNINITIALIZED",'cold_start',struct());
if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D006",out.detail="NOT_D006";return;end
if ~isstruct(sig)||~all(isfield(sig,{'Vdc','Icomp'})),out.detail="PHYSICAL_OUTPUTS_MISSING";return;end
v=cycle_component(sig.Vdc,50,"mean",700);i=cycle_component(sig.Icomp,50,"rms",NaN);out.cold_start=combine(v,i,"dc_link_and_reactive_current_establishment");out.valid=out.cold_start.valid;out.detail=tern(out.valid,"OK","COLD_START_INVALID");
end
function out=cycle_component(s,f,mode,target)
out=struct('valid',false,'mode',mode,'cycle_time',zeros(0,1),'cycle_value',zeros(0,1),'target',NaN,'relative_error',zeros(0,1),'settling_time_s',NaN,'settling_time_fraction',NaN,'normalized_iae',NaN,'q',0);if ~validsig(s),return;end
t=double(s.t(:));Y=double(s.Y);T=1/f;n=floor((t(end)-t(1))/T+1e-9);if n<4,return;end,e=t(1)+(0:n)*T;z=nan(n,size(Y,2));for k=1:n,ix=t>e(k)&t<e(k+1);tt=[e(k);t(ix);e(k+1)];yy=[interp1(t,Y,e(k),'linear','extrap');Y(ix,:);interp1(t,Y,e(k+1),'linear','extrap')];if mode=="mean",z(k,:)=trapz(tt,yy,1)/T;else,z(k,:)=sqrt(trapz(tt,yy.^2,1)/T);end,end
if ~isfinite(target),target=mean(z(end-1:end,:),1);end,scale=max(abs(target),max(1e-9,.01*max(abs(z),[],'all')));err=max(abs(z-target)./scale,[],2);q=utility(err,e);out.valid=true;out.cycle_time=e(2:end).';out.cycle_value=z;out.target=target;out.relative_error=err;out.settling_time_s=q.ts;out.settling_time_fraction=q.tf;out.normalized_iae=q.iae;out.q=q.q;
end
function out=combine(a,b,scope),out=struct('schema',"simuverity.d006-cold-start.v1",'valid',a.valid&&b.valid,'scope',scope,'score_role',"score-bearing",'components',struct('dc_link',a,'compensation_current',b),'q',0,'settling_time_s',NaN,'normalized_iae',NaN);if out.valid,out.q=sqrt(mean([a.q b.q])*min([a.q b.q]));out.settling_time_s=max(a.settling_time_s,b.settling_time_s);out.normalized_iae=max(a.normalized_iae,b.normalized_iae);end,end
function q=utility(err,e),band=.10;k=find(arrayfun(@(j)all(err(j:end)<=band),1:numel(err)),1);dur=e(end)-e(1);if isempty(k),ts=dur;else,ts=e(k+1)-e(1);end,tf=min(max(ts/max(dur,eps),0),1);iae=mean(min(err,2));q=struct('ts',ts,'tf',tf,'iae',iae,'q',exp(-log(10)*tf)*exp(-(log(10)/.25)*iae));end
function ok=validsig(s),ok=isstruct(s)&&isfield(s,'t')&&isfield(s,'Y')&&numel(s.t)>=16&&size(s.Y,1)==numel(s.t)&&all(isfinite(s.t))&&all(isfinite(s.Y),'all')&&all(diff(double(s.t(:)))>0);end
function x=tern(c,a,b),if c,x=a;else,x=b;end,end
