function [soc,voc] = getVoc()
    load tattu_voc_curve_v0.mat
    soc_raw = 1-tattu_voc_curve_v0(:,1);
    voc_raw = tattu_voc_curve_v0(:,2);
    voc_raw_min = min(voc_raw);

    o = 7;
    l = 17;
    voc_filt = sgolayfilt(voc_raw,o,l);
    
    n = 10000;
    soc = linspace(0.002,1.0014,n)';
%     voc = interp1(soc_raw,voc_filt,soc);
    voc = interp1(soc_raw,voc_raw,soc,"linear","extrap");
    soc = soc/max(soc);

    % fit model params to single cell
    f       = @(SOC,p)  1*(p(1)*exp(p(2)*SOC) + p(3)*SOC.^3 + p(4)*SOC.^2 + p(5)*SOC + p(6));
    J = @(p) sum((1*voc-f(soc,p)).^2);
    p0 = [-1.031,-30,0.3201,-0.1178,0.2156,3.685];
    options = optimset('Display','iter');
    options.TolFun = 1e-16;
    options.TolX = 1e-16;
    options.MaxIter = 1000;
    options.MaxFunEvals = 1000;
    p = fminsearch(J,p0,options);
    
    % plot results
    lw = 2;
    mksz = 5;
    ncells = 12;
    plot(soc,ncells*voc,'b','LineWidth',lw)
    hold on
    scatter(soc_raw,ncells*voc_raw,mksz+0*soc_raw,'ko')
    plot(soc,ncells*f(soc,p),'r--','LineWidth',lw)
    hold off
    xlabel('state of charge')
    ylabel('V_{oc}')
    title('Open Circuit Voltage vs State of Charge')
    legend('V_{oc} interpolated','V_{oc} raw','V_{oc} fitted')
    grid on
    
    % write to file
    save('voc.mat','soc','voc')

    p
end