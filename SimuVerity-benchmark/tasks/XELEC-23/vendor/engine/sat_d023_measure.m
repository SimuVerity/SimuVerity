function out=sat_d023_measure(sig,spec,scenarioId)
%SAT_D023_MEASURE Cold-start APF current/split-link evidence.
out=struct('schema',"simuverity.d023-direct-measurement.v1",'scenario',string(scenarioId),'valid',false,'detail',"UNINITIALIZED",'cold_start',struct());if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D023",out.detail="NOT_D023";return;end,if ~isstruct(sig)||~all(isfield(sig,{'Vdc','Icomp'}))||size(sig.Vdc.Y,2)<2,out.detail="PHYSICAL_OUTPUTS_MISSING";return;end
sumSig=sig.Vdc;sumSig.Y=sum(double(sig.Vdc.Y(:,1:2)),2);sumSig.y=sumSig.Y;
% The split-link balance is already normalized by the public 10% imbalance
% scale.  Its settling band is therefore 1.0, not 0.10.  Using 0.10 here
% silently demanded <=1% rail imbalance and collapsed a valid reference.
v=component(sumSig,50,"mean",1160,NaN,.10);b=balance_component(sig.Vdc,50,.10);i=component(sig.Icomp,50,"rms",NaN,NaN,.10);out.cold_start=combine(v,b,i);out.valid=out.cold_start.valid;out.detail=tern(out.valid,"OK","COLD_START_INVALID");
end
function o=component(s,f,mode,target,fixedScale,settleBand),o=struct('valid',false,'mode',mode,'cycle_time',zeros(0,1),'cycle_value',zeros(0,1),'target',NaN,'relative_error',zeros(0,1),'settling_tolerance',settleBand,'grace_cycles',2,'settling_time_s',NaN,'settling_time_fraction',NaN,'normalized_iae',NaN,'q_time',0,'q_excess',0,'q',0);if ~validsig(s),return;end,t=double(s.t(:));Y=double(s.Y);T=1/f;n=floor((t(end)-t(1))/T+1e-9);if n<4,return;end,e=t(1)+(0:n)*T;z=nan(n,size(Y,2));for k=1:n,ix=t>e(k)&t<e(k+1);tt=[e(k);t(ix);e(k+1)];yy=[interp1(t,Y,e(k),'linear','extrap');Y(ix,:);interp1(t,Y,e(k+1),'linear','extrap')];if mode=="mean",z(k,:)=trapz(tt,yy,1)/T;else,z(k,:)=sqrt(trapz(tt,yy.^2,1)/T);end,end,if ~isfinite(target),target=mean(z(end-1:end,:),1);end,if isfinite(fixedScale),scale=fixedScale;else,scale=max(abs(target),max(1e-9,.01*max(abs(z),[],'all')));end,err=max(abs(z-target)./scale,[],2);u=utility(err,e,settleBand,2);o.valid=true;o.cycle_time=e(2:end).';o.cycle_value=z;o.target=target;o.relative_error=err;o.settling_time_s=u.ts;o.settling_time_fraction=u.tf;o.normalized_iae=u.iae;o.q_time=u.q_time;o.q_excess=u.q_excess;o.q=u.q;end
function o=balance_component(s,f,tolerance)
o=struct('valid',false,'mode',"cycle_mean_rail_imbalance",'cycle_time',zeros(0,1),'cycle_value',zeros(0,1),'target',0,'relative_error',zeros(0,1),'settling_tolerance',1,'grace_cycles',2,'settling_time_s',NaN,'settling_time_fraction',NaN,'normalized_iae',NaN,'q_time',0,'q_excess',0,'q',0);if ~validsig(s)||size(s.Y,2)<2,return;end,t=double(s.t(:));Y=double(s.Y(:,1:2));T=1/f;n=floor((t(end)-t(1))/T+1e-9);if n<4,return;end,e=t(1)+(0:n)*T;levels=nan(n,2);for k=1:n,ix=t>e(k)&t<e(k+1);tt=[e(k);t(ix);e(k+1)];yy=[interp1(t,Y,e(k),'linear','extrap');Y(ix,:);interp1(t,Y,e(k+1),'linear','extrap')];levels(k,:)=trapz(tt,yy,1)/T;end,z=abs(levels(:,1)-levels(:,2))./max(abs(levels(:,1)+levels(:,2)),eps);err=z/max(tolerance,eps);u=utility(err,e,1,2);o.valid=true;o.cycle_time=e(2:end).';o.cycle_value=z;o.relative_error=err;o.settling_time_s=u.ts;o.settling_time_fraction=u.tf;o.normalized_iae=u.iae;o.q_time=u.q_time;o.q_excess=u.q_excess;o.q=u.q;
end
function o=combine(a,b,c),o=struct('schema',"simuverity.d023-cold-start.v1",'valid',a.valid&&b.valid&&c.valid,'scope',"current_compensation_and_split_dc_link_establishment",'score_role',"score-bearing",'components',struct('dc_link_sum',a,'dc_link_balance',b,'compensation_current',c),'q',0,'settling_time_s',NaN,'normalized_iae',NaN);if o.valid,v=[a.q b.q c.q];o.q=sqrt(mean(v)*min(v));o.settling_time_s=max([a.settling_time_s b.settling_time_s c.settling_time_s]);o.normalized_iae=max([a.normalized_iae b.normalized_iae c.normalized_iae]);end,end
function o=utility(err,e,band,graceCycles)
% Cycle-domain cold-start utility.  Two fundamental cycles are a declared
% measurement grace period for unavoidable energization transients.  Time
% to enter the public tolerance and excess area above that tolerance are
% scored with explicit piecewise anchors; a trace that never settles has a
% zero time-quality term and therefore still loses all of this component.
n=numel(err);g=min(max(round(graceCycles),0),max(n-1,0));en=err(g+1:end)/max(band,eps);k=find(arrayfun(@(j)all(en(j:end)<=1),1:numel(en)),1);if isempty(k),tf=1;ts=e(end)-e(1);else,tf=(k-1)/max(numel(en),1);ts=e(g+k)-e(1);end,iae=mean(min(max(en-1,0),4));qt=anchor(tf,[0 .10 .25 .50 .75 1],[1 1 .97 .90 .75 0]);qe=anchor(iae,[0 .10 .25 .50 1 2 4],[1 1 .98 .93 .82 .55 0]);o=struct('ts',ts,'tf',tf,'iae',iae,'q_time',qt,'q_excess',qe,'q',sqrt(mean([qt qe])*min([qt qe])));
end
function q=anchor(v,x,y),if ~isfinite(v),q=0;return;end,v=min(max(double(v),x(1)),x(end));q=interp1(x,y,v,'linear');end
function ok=validsig(s),ok=isstruct(s)&&isfield(s,'t')&&isfield(s,'Y')&&numel(s.t)>=16&&size(s.Y,1)==numel(s.t)&&all(isfinite(s.t))&&all(isfinite(s.Y),'all')&&all(diff(double(s.t(:)))>0);end
function x=tern(c,a,b),if c,x=a;else,x=b;end,end
