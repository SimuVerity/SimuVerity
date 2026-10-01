indexStart=2/0.0005;
indextEnd=3/0.0005;
netCfg='43N54P11VM';
m = matfile(['EGMi_',netCfg,'.mat']);
figFilename=['EGMi_',netCfg];
cfg=matfile(['N3Cfg_second_',netCfg,'.mat']);
npath_tot=54;
t=m.egm(1,indexStart:indextEnd);

xa=1;
xc=0.05;
xc1=0.1;
xd=1;
xe=0.1;
uni_a=1;
uni_v=1;
data_1={};
labels={};
N=0;
labels{1}='egm';
line_type={'--',':'};
makers={'none','.'};
for npath=[27, 28, 32, 34, 37, 35, 53,30, 31]
    N=N+1;
    weight=int2str(cfg.Path(npath,13));
    % vadt=m.egm((npath-1)*8+2,indexStart:indextEnd);
    % vadr=m.egm((npath-1)*8+3,indexStart:indextEnd);
    vvdt=m.egm((npath-1)*8+4,indexStart:indextEnd);
    vvdr=m.egm((npath-1)*8+5,indexStart:indextEnd);
    vvrt=m.egm((npath-1)*8+8,indexStart:indextEnd);
    vvrr=m.egm((npath-1)*8+9,indexStart:indextEnd);

    % aegm_i=xa*(vadt-uni_a*vadr);
    vegm_i=xd*(vvdt-uni_v*vvdr+xe*(vvrt-uni_v*vvrr));

    % data_1= struct('x', t, 'y', aegm_i,'LineStyle', '-');
    data_1{N}= struct('x', t, 'y', vegm_i,'LineStyle', line_type{mod(N,2)+1},'Marker',makers{mod(N,2)+1});
    labels{N+1}=[int2str(npath),'-w',weight];
end
aegm=m.egm(npath_tot*8+2,indexStart:indextEnd);
vegm=m.egm(npath_tot*8+3,indexStart:indextEnd);

data_2= struct('x', t, 'y', aegm,'LineStyle', '-','Marker','none');
data_3= struct('x', t, 'y', vegm,'LineStyle', '-','Marker','none');


plotProperty_1 = struct( 'data', [data_2],...
    'xLabel', 'time(s)', 'yLabel', 'aegm','box','on','legend',struct('labels',[]));

legend_struct=struct('labels',{labels});
plotProperty_2 = struct( 'data', [data_3,data_1{:}],...
    'xLabel', 'time(s)', 'yLabel', 'vegm','box','on','legend',legend_struct);

plotProperties = [plotProperty_1,plotProperty_2];
chartProperty=struct('tiledlayout',[2,1],'TileSpacing','Compact','Padding','Compact', 'plotProperties',plotProperties);

plotExp(chartProperty,figFilename);
