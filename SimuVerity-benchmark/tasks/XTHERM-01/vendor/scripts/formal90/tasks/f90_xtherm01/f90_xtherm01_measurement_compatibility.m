function varargout = f90_xtherm01_measurement_compatibility(helperName, varargin)
%f90_xtherm01_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xtherm01_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["empty_row", "measure_run", "measure_suite"];
        end
    case "empty_row"
        if nargout == 0
            empty_row(varargin{:});
        else
            [varargout{1:nargout}] = empty_row(varargin{:});
        end
    case "measure_run"
        if nargout == 0
            measure_run(varargin{:});
        else
            [varargout{1:nargout}] = measure_run(varargin{:});
        end
    case "measure_suite"
        if nargout == 0
            measure_suite(varargin{:});
        else
            [varargout{1:nargout}] = measure_suite(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xtherm01_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function r=empty_row()
r=struct('scenario',"",'inputs',struct(),'valid',false, ...
    'complete_interval',false,'cabin_error',NaN,'cabin_ripple',NaN, ...
    'comfort_violation',NaN,'component_excess',NaN, ...
    'component_violation',NaN,'component_peak_excess',NaN, ...
    'event_component_excess',NaN,'event_component_violation',NaN, ...
    'capacity_binding',NaN, ...
    'generation_schedule_residual',NaN,'capacity_schedule_residual',NaN, ...
    'capacity_exceedance_residual',NaN,'allocation_residual',NaN, ...
    'condenser_residual',NaN,'cop_violation',NaN,'energy_residual',NaN, ...
    'energy_monotonic_violation',NaN,'actuator_contract_violation',NaN, ...
    'actuator_chatter',NaN,'load_actuation_response',NaN, ...
    'load_recovery_time',NaN,'capacity_response_strength',NaN, ...
    'capacity_event_excursion',NaN,'capacity_recovery_time',NaN);
end

function r=measure_run(run,spec)
r=empty_row();
r.scenario=string(run.scenario);
if isfield(run,'inputs'),r.inputs=run.inputs;end
if string(run.stage)~="simulated",return;end
[t,x,okX]=xp9_series(run,'thermal_state',4);
[t2,q,okQ]=xp9_series(run,'thermal_flow',11);
[t3,a,okA]=xp9_series(run,'actuator_state',12);
[t4,e,okE]=xp9_series(run,'energy_state',4);
if ~(okX&&okQ&&okA&&okE&&size(x,2)==4&&size(q,2)==11&& ...
        size(a,2)==12&&size(e,2)==4)
    return
end
coverageTolerance=max(1.5*double(spec.sim.step),1e-6);
r.complete_interval=all([t(1) t2(1) t3(1) t4(1)]<=coverageTolerance)&& ...
    all([t(end) t2(end) t3(end) t4(end)]>= ...
    double(spec.sim.stop)-coverageTolerance);
if ~r.complete_interval,return;end
[q,okQ]=local_resample(t2,q,t);
[a,okA]=local_resample(t3,a,t);
[e,okE]=local_resample(t4,e,t);
if ~(okQ&&okA&&okE),return;end

tail=t>=t(end)-300;
if nnz(tail)<20,return;end
sp=double(run.inputs.cabin_temperature_setpoint);
limit=double(run.inputs.component_temperature_limit);
err=abs(x(:,1)-sp);
r.cabin_error=median(err(tail));
r.cabin_ripple=local_quantile(x(tail,1),.95)-local_quantile(x(tail,1),.05);
r.comfort_violation=mean(err(tail)>1.0);
r.component_excess=max(median(x(tail,3))-limit,0);
r.component_violation=mean(x(:,3)>limit);
r.component_peak_excess=max(max(x(:,3)-limit,0));
r.capacity_binding=local_quantile(max(q(:,6)+q(:,9),0)./max(a(:,2),1),.95);

% Public event schedules are checked directly, but no official score anchor
% or scenario time is exposed in the task statement.
heatMask=t>=double(run.inputs.heat_step_time)& ...
    t<double(run.inputs.heat_step_time)+600;
expectedGeneration=double(run.inputs.component_heat_load)* ...
    (1+double(run.inputs.component_heat_step_fraction)*double(heatMask));
r.generation_schedule_residual=rms(q(:,7)-expectedGeneration)/ ...
    max(rms(expectedGeneration),1);
capacityMask=t>=double(run.inputs.capacity_event_time)& ...
    t<double(run.inputs.capacity_event_time)+450;
expectedCapacity=double(run.inputs.refrigerant_capacity)* ...
    (1-double(run.inputs.compressor_capacity_loss)*double(capacityMask));
r.capacity_schedule_residual=rms(a(:,2)-expectedCapacity)/ ...
    max(rms(expectedCapacity),1);

qTotal=q(:,6)+q(:,9);
r.capacity_exceedance_residual=max(max(qTotal-max(a(:,2),0),0))/ ...
    max(double(run.inputs.refrigerant_capacity),1);
expectedCooling=max(a(:,2),0).*min(max(a(:,1),0),1);
r.allocation_residual=max([ ...
    rms(q(:,6)-expectedCooling.*a(:,3)), ...
    rms(q(:,9)-expectedCooling.*a(:,4)), ...
    rms(max(a(:,3)+a(:,4)-1,0).*max(a(:,2),1))])/ ...
    max(double(run.inputs.refrigerant_capacity),1);
r.condenser_residual=rms(q(:,11)-(q(:,6)+q(:,9)+a(:,9)))/ ...
    max(rms(q(:,11)),100);
active=qTotal>max(.01*double(run.inputs.refrigerant_capacity),50);
cop=qTotal(active)./max(a(active,9),1e-9);
if isempty(cop)
    r.cop_violation=1;
else
    r.cop_violation=mean(cop<1.5|cop>6);
end

predictedEnergy=e(1,:)+cumtrapz(t,max(a(:,9:12),0))/3.6e6;
r.energy_residual=rms(e-predictedEnergy,'all')/ ...
    max(rms(predictedEnergy-e(1,:),'all'),1e-8);
de=diff(e,1,1);
r.energy_monotonic_violation=sum(max(-de,0),'all')/ ...
    max(sum(abs(de),'all'),1e-9);

capacityScale=max(double(run.inputs.refrigerant_capacity),1);
fractionViolation=[ ...
    max(-a(:,1),0),max(a(:,1)-1,0), ...
    max(-a(:,3),0),max(a(:,3)-1,0), ...
    max(-a(:,4),0),max(a(:,4)-1,0), ...
    max(-a(:,5),0),max(a(:,5)-1,0), ...
    max(-a(:,7),0),max(a(:,7)-1,0), ...
    max(-a(:,8),0),max(a(:,8)-1,0)];
flowPowerViolation=max([ ...
    max(max(-a(:,6),0))/.35, ...
    max(max(a(:,6)-.35,0))/.35, ...
    max(max(-a(:,9:12),0),[],'all')/capacityScale, ...
    max(max(a(:,12)-8000,0))/8000, ...
    max(max(q(:,5)-8000,0))/8000, ...
    max(max(-q(:,[4 5 6 7 9 11]),0),[],'all')/capacityScale]);
r.actuator_contract_violation=max( ...
    max(fractionViolation,[],'all'),flowPowerViolation);

da=abs(diff(a(:,[1 3 4 5 7 8]),1,1));
r.actuator_chatter=mean(any(da>.12,2));

heatStart=double(run.inputs.heat_step_time);
heatEnd=heatStart+600;
heatPre=t>=max(0,heatStart-240)&t<=heatStart-30;
heatDuring=t>=heatStart+45&t<=heatEnd-45;
if nnz(heatPre)<10||nnz(heatDuring)<10,return;end
loadHeatResponse=max([ ...
    median(q(heatDuring,9))-median(q(heatPre,9)), ...
    median(q(heatDuring,10))-median(q(heatPre,10))])/capacityScale;
loadCommandResponse=max([ ...
    median(a(heatDuring,1))-median(a(heatPre,1)), ...
    median(a(heatDuring,4))-median(a(heatPre,4)), ...
    median(a(heatDuring,5))-median(a(heatPre,5))]);
r.load_actuation_response=max([loadHeatResponse loadCommandResponse 0]);
if all(x(heatDuring,3)<=limit)
    r.load_recovery_time=0;
else
    r.load_recovery_time=local_constraint_recovery( ...
        t,x(:,3)<=limit,heatEnd,900);
end

capacityStart=double(run.inputs.capacity_event_time);
capacityEnd=capacityStart+450;
capacityPre=t>=max(0,capacityStart-240)&t<=capacityStart-30;
capacityDuring=t>=capacityStart+30&t<=capacityEnd-30;
if nnz(capacityPre)<10||nnz(capacityDuring)<10,return;end
flowChange=abs(median(qTotal(capacityDuring))-median(qTotal(capacityPre)))/ ...
    max(double(run.inputs.refrigerant_capacity),1);
allocationChange=max([ ...
    abs(median(a(capacityDuring,3))-median(a(capacityPre,3))), ...
    abs(median(a(capacityDuring,4))-median(a(capacityPre,4)))]);
actuationChange=max(abs(median(a(capacityDuring,[1 3 4 5 7 8]),1)- ...
    median(a(capacityPre,[1 3 4 5 7 8]),1)));
r.capacity_response_strength=max([flowChange allocationChange actuationChange]);
r.capacity_event_excursion=max([ ...
    max(median(abs(x(capacityDuring,1)-sp))-median(abs(x(capacityPre,1)-sp)),0), ...
    max(median(max(x(capacityDuring,3)-limit,0))- ...
    median(max(x(capacityPre,3)-limit,0)),0)]);
r.event_component_excess=max(max(x(heatDuring|capacityDuring,3)-limit,0));
r.event_component_violation=mean(x(heatDuring|capacityDuring,3)>limit);
capacityGood=abs(x(:,1)-sp)<=1.0&x(:,3)<=limit;
if all(capacityGood(capacityDuring))
    r.capacity_recovery_time=0;
else
    r.capacity_recovery_time=local_constraint_recovery( ...
        t,capacityGood,capacityEnd,750);
end

finiteValues=[r.cabin_error r.cabin_ripple r.comfort_violation ...
    r.component_excess r.component_violation r.component_peak_excess ...
    r.event_component_excess r.event_component_violation r.capacity_binding ...
    r.generation_schedule_residual r.capacity_schedule_residual ...
    r.capacity_exceedance_residual r.allocation_residual ...
    r.condenser_residual r.cop_violation r.energy_residual ...
    r.energy_monotonic_violation r.actuator_contract_violation ...
    r.actuator_chatter r.load_actuation_response r.load_recovery_time ...
    r.capacity_response_strength r.capacity_event_excursion ...
    r.capacity_recovery_time];
r.valid=r.complete_interval&&all(isfinite(finiteValues));
end

function s=measure_suite(runs,rows)
s=empty_suite();
if isempty(runs)||~all([rows.valid]),return;end
dxAll=[];netAll=[];passiveNegative=0;passiveAbsolute=0;
gainActual=[];gainDriver=[];generationResidual=[];
capacityResidual=[];capacityExceed=[];allocationResidual=[];
condenserResidual=[];copViolation=[];energyResidual=[];
actuatorViolation=[];stateActivity=[];netActivity=[];
evaporatorActivity=[];chillerActivity=[];componentCoolantActivity=[];
for i=1:numel(runs)
    run=runs(i);
    [t,x,okX]=xp9_series(run,'thermal_state',4);
    [t2,q,okQ]=xp9_series(run,'thermal_flow',11);
    if ~(okX&&okQ),return;end
    [q,okQ]=local_resample(t2,q,t);
    if ~okQ,return;end
    fit=t>10&t<t(end)-1;
    dx=[backward_rate(x(:,1),t),backward_rate(x(:,2),t), ...
        backward_rate(x(:,3),t),backward_rate(x(:,4),t)];
    net=[ ...
        q(:,1)+q(:,3)+q(:,4)+q(:,5)-q(:,6), ...
        q(:,2)-q(:,3), ...
        q(:,7)-q(:,8), ...
        q(:,8)-q(:,9)-q(:,10)];
    dxAll=[dxAll;dx(fit,:)]; %#ok<AGROW>
    netAll=[netAll;net(fit,:)]; %#ok<AGROW>

    drives=[ ...
        double(run.inputs.ambient_temperature)-x(:,1), ...
        double(run.inputs.ambient_temperature)-x(:,2), ...
        x(:,2)-x(:,1),x(:,3)-x(:,4), ...
        x(:,4)-double(run.inputs.ambient_temperature)];
    flows=[q(:,1),q(:,2),q(:,3),q(:,8),q(:,10)];
    work=drives.*flows;
    passiveNegative=passiveNegative+sum(max(-work,0),'all');
    passiveAbsolute=passiveAbsolute+sum(abs(work),'all');

    gainActual=[gainActual;q(fit,4)]; %#ok<AGROW>
    gainDriver=[gainDriver;repmat( ...
        [double(run.inputs.cabin_internal_gain) ...
        double(run.inputs.solar_irradiance)],nnz(fit),1)]; %#ok<AGROW>
    generationResidual(end+1)=rows(i).generation_schedule_residual; %#ok<AGROW>
    capacityResidual(end+1)=rows(i).capacity_schedule_residual; %#ok<AGROW>
    capacityExceed(end+1)=rows(i).capacity_exceedance_residual; %#ok<AGROW>
    allocationResidual(end+1)=rows(i).allocation_residual; %#ok<AGROW>
    condenserResidual(end+1)=rows(i).condenser_residual; %#ok<AGROW>
    copViolation(end+1)=rows(i).cop_violation; %#ok<AGROW>
    energyResidual(end+1)=rows(i).energy_residual; %#ok<AGROW>
    actuatorViolation(end+1)=rows(i).actuator_contract_violation; %#ok<AGROW>
    stateActivity=[stateActivity;local_quantile(abs(dx(fit,:)),.80)]; %#ok<AGROW>
    netActivity=[netActivity;local_quantile(abs(net(fit,:)),.80)]; %#ok<AGROW>
    evaporatorActivity(end+1)=local_quantile(abs(q(fit,6)),.75); %#ok<AGROW>
    chillerActivity(end+1)=local_quantile(abs(q(fit,9)),.75); %#ok<AGROW>
    componentCoolantActivity(end+1)=local_quantile(abs(q(fit,8)),.75); %#ok<AGROW>
end

s.storage_residual=ones(1,4);
s.storage_coefficients=nan(1,4);
s.storage_coefficients_physical=true;
for k=1:4
    [s.storage_residual(k),capacity,ok]=fit_positive(dxAll(:,k),netAll(:,k),100);
    s.storage_coefficients(k)=capacity;
    s.storage_coefficients_physical=s.storage_coefficients_physical&&ok&&capacity>0;
end
s.passivity_violation=passiveNegative/max(passiveAbsolute,1);
s.generation_schedule_residual=max(generationResidual);
s.capacity_schedule_residual=max(capacityResidual);
s.capacity_exceedance_residual=max(capacityExceed);
s.allocation_residual=max(allocationResidual);
s.condenser_residual=max(condenserResidual);
s.cop_violation=max(copViolation);
s.energy_residual=max(energyResidual);
s.actuator_contract_violation=max(actuatorViolation);

% Fit a nonnegative affine route from the two public cabin-gain drivers to
% the reported cabin heat gain. This permits different legal absorption
% factors while rejecting a constant or negatively routed fake signal.
X=[gainDriver ones(size(gainDriver,1),1)];
good=all(isfinite(X),2)&isfinite(gainActual);
b=X(good,:)\gainActual(good);
pred=X(good,:)*b;
s.cabin_gain_causality_residual=rms(gainActual(good)-pred)/ ...
    max(rms(gainActual(good)),100);
s.cabin_gain_coefficients=b(:)';
s.cabin_gain_causal=numel(b)==3&&all(isfinite(b))&& ...
    b(1)>.05&&b(2)>.05;
if ~s.cabin_gain_causal
    s.cabin_gain_causality_residual=max(s.cabin_gain_causality_residual,1);
end

s.storage_state_activity=max(stateActivity,[],'all');
s.thermal_input_activity=max(netActivity,[],'all');
s.core_thermal_storage=s.storage_state_activity>1e-8&& ...
    s.thermal_input_activity>1e-3&&s.storage_coefficients_physical;
s.static_setpoint_shortcut=~s.core_thermal_storage&& ...
    max([rows.cabin_error])<1e-5&&max([rows.cabin_ripple])<1e-6;
s.core_shared_capacity=max(evaporatorActivity)>50&& ...
    max(chillerActivity)>50&&s.capacity_schedule_residual<.15;
s.core_component_coolant_path=max(componentCoolantActivity)>50;
s.core_dynamic_interventions= ...
    max([rows.generation_schedule_residual])<.15&& ...
    max([rows.capacity_schedule_residual])<.15&& ...
    any([rows.load_actuation_response]>.002);
s.valid=all(isfinite([s.storage_residual s.storage_coefficients ...
    s.passivity_violation s.generation_schedule_residual ...
    s.cabin_gain_causality_residual s.capacity_schedule_residual ...
    s.capacity_exceedance_residual s.allocation_residual ...
    s.condenser_residual s.cop_violation s.energy_residual ...
    s.actuator_contract_violation s.storage_state_activity ...
    s.thermal_input_activity]));
end

function dt=local_constraint_recovery(t,good,eventEnd,maxWindow)
dt=maxWindow;
start=find(t>=eventEnd,1);
if isempty(start),return;end
hold=max(3,round(60/median(diff(t))));
last=min(numel(t)-hold+1,find(t<=eventEnd+maxWindow,1,'last'));
if isempty(last)||last<start,return;end
for k=start:last
    if all(good(k:k+hold-1))
        dt=t(k)-eventEnd;return
    end
end
end

function q=local_quantile(x,p)
x=sort(double(x),1);
n=size(x,1);
q=x(max(1,min(n,ceil(p*n))),:);
end

function [y,ok]=local_resample(tSource,ySource,tTarget)
% Accept complete legal multi-rate Timeseries without extrapolating beyond
% the source interval.  Duplicate timestamps are reduced deterministically.
y=[];ok=false;
tSource=double(tSource(:));tTarget=double(tTarget(:));
ySource=double(ySource);
if isempty(tSource)||isempty(tTarget)||size(ySource,1)~=numel(tSource)|| ...
        any(~isfinite(tSource))||any(~isfinite(tTarget))|| ...
        any(~isfinite(ySource),'all')
    return
end
[tUnique,keep]=unique(tSource,'stable');
yUnique=ySource(keep,:);
if numel(tUnique)<2||any(diff(tUnique)<=0)|| ...
        tTarget(1)<tUnique(1)-1e-9||tTarget(end)>tUnique(end)+1e-9
    return
end
if isequal(tUnique,tTarget)
    y=yUnique;
else
    y=interp1(tUnique,yUnique,tTarget,'linear');
end
ok=size(y,1)==numel(tTarget)&&all(isfinite(y),'all');
end

function [res,coefficient,ok]=fit_positive(dx,net,floorValue)
res=1;coefficient=NaN;ok=false;
good=isfinite(dx)&isfinite(net);dx=dx(good);net=net(good);
if numel(dx)<40||rms(dx)<1e-12||rms(net)<1e-9,return;end
coefficient=dx\net;
res=rms(net-coefficient*dx)/max(rms(net),floorValue);
ok=isfinite(coefficient)&&coefficient>0&&isfinite(res);
end

function dx=backward_rate(x,t)
dx=zeros(size(x));
dx(2:end)=diff(x)./diff(t);
dx(1)=dx(2);
end

function s=empty_suite()
s=struct('valid',false,'storage_residual',ones(1,4), ...
    'storage_coefficients',nan(1,4),'storage_coefficients_physical',false, ...
    'passivity_violation',1,'generation_schedule_residual',1, ...
    'cabin_gain_causality_residual',1,'cabin_gain_coefficients',nan(1,3), ...
    'cabin_gain_causal',false,'capacity_schedule_residual',1, ...
    'capacity_exceedance_residual',1,'allocation_residual',1, ...
    'condenser_residual',1,'cop_violation',1,'energy_residual',1, ...
    'actuator_contract_violation',1,'storage_state_activity',NaN, ...
    'thermal_input_activity',NaN,'core_thermal_storage',false, ...
    'static_setpoint_shortcut',false,'core_shared_capacity',false, ...
    'core_component_coolant_path',false,'core_dynamic_interventions',false);
end
