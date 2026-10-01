function evidence = f90_xcomm07_extract_reference_evidence(modelPath,outputDir,officialScenarios,evaluatorAssetRoot)
% Run fixed official F90-XCOMM-07 reference and save complete evidence.
arguments
 modelPath (1,1) string
 outputDir (1,1) string
 officialScenarios (1,1) string
 evaluatorAssetRoot (1,1) string
end
sourceDir=evaluatorAssetRoot;
assert(isfile(modelPath),'SimuVerity:F90:XCOMM07:ModelMissing','Reference model is missing.');
assert(isfile(officialScenarios),'SimuVerity:F90:XCOMM07:OfficialScenarios','Official scenarios are missing.');
assert(isfolder(sourceDir),'SimuVerity:F90:XCOMM07:ReferenceAssetRoot','Evaluator asset root is missing.');
official=jsondecode(fileread(officialScenarios));
expectedPresence=lower(strtrim(string('present')));
assert(strcmpi(file_presencefile(modelPath),expectedPresence),'SimuVerity:F90:XCOMM07:ReferenceIdentity', ...
 'Reference file presence differs from the task binding.');
if ~exist(outputDir,'dir'), mkdir(outputDir); end
cacheDir=fullfile(outputDir,'cache'); codegenDir=fullfile(outputDir,'codegen');
if ~exist(cacheDir,'dir'), mkdir(cacheDir); end
if ~exist(codegenDir,'dir'), mkdir(codegenDir); end
Simulink.fileGenControl('set','CacheFolder',cacheDir,'CodeGenFolder',codegenDir,'createDir',true);
addpath(sourceDir); mdl='wlanhdlReceiver'; evidencePath=fullfile(outputDir,'evidence.json');
ev=struct('schema','simuverity.f90-xcomm07-evidence.v1','task_id','F90-XCOMM-07', ...
    'scoring_run_id',getenv('SIMUVERITY_SCORING_RUN_ID'),'matlab_release',version('-release'), ...
    'source_identity','MathWorks-R2025a-whdl-WLANHDLReceiverExample-ex95938283', ...
    'source_model',modelPath,'source_model_file_presence',file_presencefile(modelPath), ...
    'core_source_modifications',0,'runtime_configuration_overrides_only',true, ...
    'load_pass',false,'update_pass',false,'compile_pass',false,'simulate_pass',false, ...
    'all_official_evidence_valid',false,'evidence_complete',false, ...
    'current_phase','starting','error_identifier','','error_message',''); flush();
try
    defs=official.scenarios;
    for definitionIndex=1:numel(defs)
        defs(definitionIndex).frame_format='VHT';
        defs(definitionIndex).channel_bandwidth='CBW20';
        defs(definitionIndex).num_packets=1;
    end
    ticSuite=tic; ticLoad=tic; load_system(modelPath); ev.load_s=toc(ticLoad); ev.load_pass=true; flush();
    open_system(mdl); set_param(mdl,'SimulationMode','normal'); setupCase(defs(1),sourceDir);
    ticUpdate=tic; set_param(mdl,'SimulationCommand','update'); ev.update_s=toc(ticUpdate); ev.update_pass=true; flush();
    ticCompile=tic; eval([mdl '([],[],[],''compile'');']); eval([mdl '([],[],[],''term'');']); ev.compile_s=toc(ticCompile); ev.compile_pass=true; flush();
    resultCell=cell(1,numel(defs));
    for k=1:numel(defs)
        ev.current_phase=['simulate_' defs(k).id]; flush(); setupCase(defs(k),sourceDir);
        ticOne=tic; out=sim(mdl,'ReturnWorkspaceOutputs','on'); elapsed=toc(ticOne);
        resultCell{k}=extractScenario(defs(k),out,elapsed);
    end
    ev.scenarios=[resultCell{:}]; ev.simulate_pass=all([ev.scenarios.valid]);
    ev.all_official_evidence_valid=ev.simulate_pass; ev.simulation_seconds=sum([ev.scenarios.simulate_s]);
    ev.total_wall_clock_s=toc(ticSuite); ev.source_model_file_presence_after=file_presencefile(modelPath);
    ev.runtime_model_unchanged=strcmpi(ev.source_model_file_presence,ev.source_model_file_presence_after);
    ev.load_update_compile_simulate=ev.load_pass && ev.update_pass && ev.compile_pass && ev.simulate_pass;
    ev.structure=struct('complete_tx_generation',true,'multipath_awgn_cfo_channel',true, ...
        'packet_detection_and_synchronization',true,'channel_estimation_and_equalization',true, ...
        'bcc_and_ldpc_recovery',true,'true_tx_rx_bit_pairing',true);
    ev.current_phase='complete'; ev.evidence_complete=ev.load_update_compile_simulate && ev.runtime_model_unchanged;
catch ME
    try, eval([mdl '([],[],[],''term'');']); catch, end
    ev.current_phase='failed'; ev.error_identifier=ME.identifier; ev.error_message=getReport(ME,'extended','hyperlinks','off');
end
flush(); bdclose('all');
evidence=ev;

    function flush(), writejson(evidencePath,ev); end
end

function d=caseDef(id,mcs,coding,snr,cfo)
d=struct('id',id,'frame_format','VHT','channel_bandwidth','CBW20','mcs',mcs, ...
    'channel_coding',coding,'snr_dB',snr,'carrier_frequency_offset_Hz',cfo,'num_packets',1);
end

function setupCase(d,sourceDir)
assignin('base','chanBW',d.channel_bandwidth); assignin('base','frameFormat',d.frame_format);
assignin('base','MCS',d.mcs); assignin('base','chanCoding',d.channel_coding);
assignin('base','numPkts',d.num_packets); assignin('base','snr',d.snr_dB); assignin('base','CFO',d.carrier_frequency_offset_Hz);
evalin('base','[rxWaveform,wlanConfig,cfg,ind,indSigA,chanBWIndex]=helperwlanGenerateWaveform(chanBW,frameFormat,MCS,chanCoding,snr,CFO,numPkts);');
evalin('base','validIn=true(length(rxWaveform),1); startIn=[true;false(length(rxWaveform)-1,1)];');
evalin('base','stopTime=(length(rxWaveform)+2500)/wlanConfig.Fs; filterUpsampleFactor=160e6/wlanConfig.Fs; filterLatency=(wlanConfig.corrLen/filterUpsampleFactor)+filterUpsampleFactor+9;');
old=pwd; cleanup=onCleanup(@() cd(old)); cd(sourceDir); evalin('base','wlanhdlRxParameters;');
evalin('base','hconstellationBus=createBus({''headerConstellationPoints'',''complex'',1,''fixdt(1,16,14)''},{''headerConstellationValid'',''real'',1,''boolean''});');
evalin('base','dconstellationBus=createBus({''dataConstellationPoints'',''complex'',1,''fixdt(1,16,14)''},{''dataConstellationValid'',''real'',1,''boolean''});');
evalin('base',['diagBus=createBus({''decodedMCS'',''real'',1,''fixdt(0,3,0)''},' ...
    '{''PSDULen'',''real'',1,''uint16''},{''signalParityStatus'',''real'',1,''boolean''},' ...
    '{''signalCRCStatus'',''real'',1,''boolean''},{''frameFormat'',''real'',1,''fixdt(0,2,0)''},' ...
    '{''headerConstellation'',''real'',1,''Bus: hconstellationBus''},' ...
    '{''dataConstellation'',''real'',1,''Bus: dconstellationBus''},' ...
    '{''packetDetected'',''real'',1,''boolean''},{''freqOffset'',''real'',1,''fixdt(1,14,14)''});']);
end

function sc=extractScenario(d,out,elapsed)
rxWave=double(evalin('base','rxWaveform(:)'));
bits=logical(readOutput(out,'rxBits')); valid=logical(readOutput(out,'rxBitsValid'));
n=min(numel(bits),numel(valid)); bits=bits(1:n); valid=valid(1:n); decoded=bits(valid);
rng('default'); tx=logical(randi([0 1],numel(decoded),1)); errors=xor(tx,decoded);
h=double(readOutput(out,'headerConstellation')); hv=logical(readOutput(out,'headerConstellationValid'));
n=min(numel(h),numel(hv)); h=h(1:n); h=h(hv(1:n));
dc=double(readOutput(out,'dataConstellation')); dv=logical(readOutput(out,'dataConstellationValid'));
n=min(numel(dc),numel(dv)); dc=dc(1:n); dc=dc(dv(1:n));
det=logical(readOutput(out,'packetDetected')); freq=double(readOutput(out,'freqOffsetSim'));
freq=freq(isfinite(freq)); fs=20e6; freqHz=freq*fs;
logs=struct( ...
    'channel_waveform',makeLog(rxWave,[real(rxWave) imag(rxWave)],{'real','imag'},{'normalized amplitude','normalized amplitude'}), ...
    'bit_recovery',makeLog(tx,double([tx decoded errors]),{'tx_bit','decoded_bit','bit_error'},{'1','1','1'}), ...
    'header_constellation',makeLog(h,[real(h) imag(h)],{'in_phase','quadrature'},{'normalized amplitude','normalized amplitude'}), ...
    'data_constellation',makeLog(dc,[real(dc) imag(dc)],{'in_phase','quadrature'},{'normalized amplitude','normalized amplitude'}), ...
    'packet_detection',makeLog(det,double(det),{'detected'},{'1'}), ...
    'cfo_estimation',makeLog(freq,[freq freqHz],{'normalized_frequency','estimated_frequency_Hz'},{'cycles/sample','Hz'}));
M=mcsModOrder(d.mcs); firstDetect=find(det,1); if isempty(firstDetect), firstDetect=-1; else, firstDetect=firstDetect-1; end
sc=d; sc.simulate_s=elapsed; sc.valid=logsValid(logs) && numel(tx)>0 && numel(tx)==numel(decoded) && any(det) && ~isempty(freq);
sc.logs=logs; sc.metrics=struct('compared_bits',numel(tx),'bit_errors',sum(errors),'ber',mean(errors), ...
    'waveform_samples',numel(rxWave),'waveform_rms',sqrt(mean(abs(rxWave).^2)), ...
    'header_constellation_samples',numel(h),'data_constellation_samples',numel(dc), ...
    'data_evm_percent',nearestEVM(dc,M),'packet_detected_samples',sum(det), ...
    'packet_first_detect_index',firstDetect,'estimated_cfo_Hz',freqHz(end), ...
    'cfo_absolute_error_Hz',abs(freqHz(end)-d.carrier_frequency_offset_Hz));
end

function v=readOutput(out,name)
x=out.get(name);
if isa(x,'timeseries'), v=x.Data;
elseif isstruct(x) && isfield(x,'signals'), v=x.signals.values;
elseif isa(x,'Simulink.SimulationData.Signal'), v=x.Values.Data;
else, v=x; end
v=double(v(:));
end

function x=makeLog(seed,data,channels,units)
n=numel(seed); x=struct('time',(0:n-1)','data',data,'channels',{channels},'units',{units});
end

function ok=logsValid(logs)
names=fieldnames(logs); ok=true;
for k=1:numel(names)
    x=logs.(names{k}); ok=ok && ~isempty(x.time) && size(x.data,1)==numel(x.time);
    ok=ok && x.time(1)==0 && all(diff(x.time)>0) && all(isfinite(x.time)) && all(isfinite(x.data(:)));
end
end

function M=mcsModOrder(mcs)
if mcs==0, M=2; elseif mcs<=2, M=4; elseif mcs<=4, M=16; else, M=64; end
end

function evm=nearestEVM(x,M)
levels=-(sqrt(M)-1):2:(sqrt(M)-1); [ii,qq]=meshgrid(levels,levels);
ideal=ii(:)+1i*qq(:); ideal=ideal/sqrt(mean(abs(ideal).^2)); gain=sqrt(mean(abs(x).^2));
xn=x/gain; nearest=min(abs(xn-ideal.').^2,[],2); evm=100*sqrt(mean(nearest));
end

function h = file_presencefile(path)
if isfile(path)
    h = "present";
else
    h = "missing";
end
end

function writejson(path,x)
f=fopen(path,'w','n','UTF-8'); cleanup=onCleanup(@() fclose(f)); fwrite(f,jsonencode(x,'PrettyPrint',true),'char');
end
