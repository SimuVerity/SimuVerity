indexStart=0.8/0.0005;
indextEnd=1.2/0.0005;
figFilename='test_tune';

m = matfile('EGM_43N54P11VM.mat');
t=m.cells(1,indexStart:indextEnd);
aegm=m.cells(2,indexStart:indextEnd);
vegm=m.cells(3,indexStart:indextEnd);

data_1= struct('x', t, 'y', aegm,'LineStyle', '-');
data_2= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_43N54P11VM_tune.mat');
vegm=m.cells(3,indexStart:indextEnd);
data_12= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_93N270P61VM_tune.mat');
vegm=m.cells(3,indexStart:indextEnd);
data_14= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_138N477P106VM_tune.mat');
vegm=m.cells(3,indexStart:indextEnd);
data_16= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_253N969P221VM_tune.mat');
vegm=m.cells(3,indexStart:indextEnd);
data_18= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_374N1479P342VM_tune.mat');
vegm=m.cells(3,indexStart:indextEnd);
data_20= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_644N2802P612VM_tune.mat');
vegm=m.cells(3,indexStart:indextEnd);
data_22= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_253N969P221VM_tune_z.mat');
vegm=m.cells(3,indexStart:indextEnd);
data_24= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_93N270P61VM.mat');
aegm=m.cells(2,indexStart:indextEnd);
vegm=m.cells(3,indexStart:indextEnd);

data_3= struct('x', t, 'y', aegm,'LineStyle', '-');
data_4= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_138N477P106VM.mat');
aegm=m.cells(2,indexStart:indextEnd);
vegm=m.cells(3,indexStart:indextEnd);

data_5= struct('x', t, 'y', aegm,'LineStyle', '-');
data_6= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_253N969P221VM.mat');
aegm=m.cells(2,indexStart:indextEnd);
vegm=m.cells(3,indexStart:indextEnd);

data_7= struct('x', t, 'y', aegm,'LineStyle', '-');
data_8= struct('x', t, 'y', vegm,'LineStyle', '-');

m = matfile('EGM_374N1479P342VM.mat');
aegm=m.cells(2,indexStart:indextEnd);
vegm=m.cells(3,indexStart:indextEnd);

data_9= struct('x', t, 'y', aegm,'LineStyle', '-');
data_10= struct('x', t, 'y', vegm,'LineStyle', '-');

plotProperty_1 = struct( 'data', [data_2,data_12],'legend',struct('labels',{{'original','new probe'}}),...
    'xLabel', 'time(s)', 'yLabel', 'vegm','box','on');


plotProperty_2 = struct( 'data', [data_12,data_14,data_16],'legend',struct('labels',{{'43N54P11VM','93N270P61VM','138N477P106VM'}}),...
    'xLabel', 'time(s)', 'yLabel', 'vegm','box','on');

plotProperty_3 = struct( 'data', [data_16,data_18,data_20,data_24],'legend',struct('labels',{{'138N477P106VM','253N969P221VM','374N1479P342VM','253N969P221VM_z'}}),...
    'xLabel', 'time(s)', 'yLabel', 'vegm','box','on');

plotProperty_4 = struct( 'data', [data_8,data_10,data_18],...
    'xLabel', 'time(s)', 'yLabel', 'vegm','box','on');



plotProperties = [plotProperty_1,plotProperty_2,plotProperty_3];
chartProperty=struct('tiledlayout',[3,1],'TileSpacing','Compact','Padding','Compact', 'plotProperties',plotProperties);

plotExp(chartProperty,figFilename);
