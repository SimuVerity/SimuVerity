function info=sat_provenance_semantic(block)
%SAT_PROVENANCE_SEMANTIC Fail-closed provenance semantics for sensors.
% User-visible names are never evidence.  Trust requires an exact native or
% SPS library identity.  Native Simscape sensors additionally require their
% conserving terminals and at least one physical-signal output to be wired.

info=struct('trusted',false,'kind',"",'semantic',"",'reason',"UNTRUSTED_IDENTITY");
if isempty(block)||getSimulinkBlockHandle(block)<0,info.reason="BLOCK_MISSING";return;end
bt=normtext(getp(block,'BlockType'));mt=normtext(getp(block,'MaskType'));
rb=normpath(getp(block,'ReferenceBlock'));link=normtext(getp(block,'LinkStatus'));

% Native Simscape Foundation voltage sensor.
if bt=="simscapeblock"&&mt=="voltage sensor" ...
        &&rb=="fl_lib/electrical/electrical sensors/voltage sensor"
    if ~trusted_link(link),info.reason="NATIVE_LINK_NOT_RESOLVED";return;end
    if ~native_sensor_connected(block,"network_engine_domain.foundation.electrical.electrical",2)
        info.reason="NATIVE_SENSOR_NOT_FULLY_CONNECTED";return;
    end
    info=trusted("measurement","voltage measurement|voltage sensor");return;
end

% Native Simscape Foundation current sensor.  As for the voltage sensor,
% an exact library identity is necessary but not sufficient: both conserving
% electrical terminals and the physical-signal output must be connected.
% This deliberately does not trust a copied MaskType or a user-authored block
% whose visible name merely contains "Current Sensor".
if bt=="simscapeblock"&&mt=="current sensor" ...
        &&rb=="fl_lib/electrical/electrical sensors/current sensor"
    if ~trusted_link(link),info.reason="NATIVE_LINK_NOT_RESOLVED";return;end
    if ~native_sensor_connected(block,"network_engine_domain.foundation.electrical.electrical",2)
        info.reason="NATIVE_SENSOR_NOT_FULLY_CONNECTED";return;
    end
    info=trusted("measurement","current measurement|current sensor");return;
end

% Native Simscape Electrical combined three-phase sensor.
if bt=="simscapeblock"&&mt=="current and voltage sensor (three-phase)" ...
        &&rb=="ee_lib/sensors & transducers/current and voltage sensor (three-phase)"
    if ~trusted_link(link),info.reason="NATIVE_LINK_NOT_RESOLVED";return;end
    if ~native_sensor_connected(block, ...
            "network_engine_domain.foundation.electrical.three_phase",2)
        info.reason="NATIVE_SENSOR_NOT_FULLY_CONNECTED";return;
    end
    info=trusted("measurement",strjoin(["three-phase vi measurement", ...
        "current measurement","voltage measurement", ...
        "current and voltage sensor (three-phase)"],"|"));return;
end

% Simscape physical-signal to Simulink converter.  This is a trusted,
% transparent boundary, not a measurement terminal.
if bt=="subsystem"&&mt=="ps-simulink converter" ...
        &&rb=="nesl_utility/ps-simulink converter"&&trusted_link(link)
    if ~converter_connected(block),info.reason="CONVERTER_INPUT_NOT_CONNECTED";return;end
    info=trusted("converter","ps-simulink converter");return;
end

% Specialized Power Systems measurements.  Exact ReferenceBlock identity
% prevents a user-authored masked subsystem from copying only MaskType.
if bt=="subsystem"&&mt=="voltage measurement" ...
        &&rb=="spsvoltagemeasurementlib/voltage measurement"
    info=trusted("measurement","voltage measurement");return;
end
if bt=="subsystem"&&mt=="current measurement" ...
        &&rb=="spscurrentmeasurementlib/current measurement"
    info=trusted("measurement","current measurement");return;
end
if bt=="subsystem"&&mt=="three-phase vi measurement" ...
        &&rb=="spsthreephasevimeasurementlib/three-phase v-i measurement"
    info=trusted("measurement", ...
        "three-phase vi measurement|current measurement|voltage measurement");return;
end
% Newer SPS library links expose the visible block through an exact
% implementation-model subsystem.  Trust that official identity as the
% same three-phase V-I sensor; a copied MaskType/name without this
% ReferenceBlock remains untrusted.
if bt=="subsystem"&&mt=="specialized power systems three-phase vi measurement" ...
        &&rb=="spsvimeasurementmodel/vi"
    info=trusted("measurement", ...
        "three-phase vi measurement|current measurement|voltage measurement");return;
end
if bt=="subsystem"&&mt=="multimeter" ...
        &&rb=="spsmultimeterlib/multimeter"
    info=trusted("measurement","multimeter|current measurement|voltage measurement");return;
end
if bt=="subsystem"&&startsWith(mt,"power (3ph") ...
        &&(startsWith(rb,"spspower3phinstantaneouslib/") ...
        ||startsWith(rb,"spspower3phphasorlib/"))
    info=trusted("measurement","power (3ph|power measurement");return;
end

% The public m port of the official SPS Simplified Synchronous Machine is
% a MathWorks-defined measurement bus.  Treat the exact SI/pu library
% identities as a measurement boundary so provenance does not descend into
% the machine's implementation internals.  A copied name or MaskType alone
% cannot satisfy either exact ReferenceBlock identity.
officialSimplifiedMachines=[ ...
    "spssimplifiedsynchronousmachinesiunitslib/simplified synchronous machine si units", ...
    "spssimplifiedsynchronousmachinepuunitslib/simplified synchronous machine pu units"];
if bt=="subsystem"&&mt=="simplified synchronous machine" ...
        &&any(rb==officialSimplifiedMachines)&&trusted_link(link)
    info=trusted("measurement",strjoin(["machine measurement","machine", ...
        "three-phase vi measurement","current measurement", ...
        "voltage measurement"],"|"));return;
end

% Machine measurement ports remain accepted only when their source is an
% installed MathWorks electrical library, never from the candidate name.
if (startsWith(rb,"sps")||startsWith(rb,"ee_lib/")) ...
        &&contains(rb,"machine")&&contains(rb,"measurement")
    info=trusted("measurement","machine measurement|machine");return;
end
end

function info=trusted(kind,semantic)
info=struct('trusted',true,'kind',string(kind), ...
    'semantic',string(semantic),'reason',"OK");
end

function yes=trusted_link(link)
yes=any(link==["resolved","implicit"]);
end

function yes=native_sensor_connected(block,conservingType,minConserving)
yes=false;ports=connection_ports(block);if isempty(ports),return;end
types=strings(size(ports));for i=1:numel(ports),types(i)=normtext(getport(ports(i),'ConnectionType'));end
conserving=ports(types==normtext(conservingType));signals=ports(types=="network_engine_domain.output");
if numel(conserving)<minConserving||isempty(signals),return;end
yes=all(arrayfun(@port_connected,conserving))&&any(arrayfun(@port_connected,signals));
end

function yes=converter_connected(block)
ports=connection_ports(block);types=strings(size(ports));
for i=1:numel(ports),types(i)=normtext(getport(ports(i),'ConnectionType'));end
inputs=ports(types=="network_engine_domain.input");
yes=numel(inputs)==1&&port_connected(inputs(1));
end

function ports=connection_ports(block)
ports=[];try,ph=get_param(block,'PortHandles');catch,return;end
for f={'LConn','RConn'}
    if isfield(ph,f{1})&&~isempty(ph.(f{1})),ports=[ports ph.(f{1})(:)'];end %#ok<AGROW>
end
end

function yes=port_connected(port)
yes=false;try,ln=get_param(port,'Line');yes=~isempty(ln)&&all(double(ln)>=0);catch,end
end

function value=getp(block,param)
value='';try,value=get_param(block,param);catch,end
if isnumeric(value),value=num2str(value);end
end

function value=getport(port,param)
value='';try,value=get_param(port,param);catch,end
if isnumeric(value),value=num2str(value);end
end

function value=normtext(value)
value=lower(strtrim(regexprep(string(value),'\s+',' ')));
end

function value=normpath(value)
value=replace(normtext(value),'\','/');
end
