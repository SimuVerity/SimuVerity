function grapple_ptcld = sm_wheel_loader_params_ptclds_grapple()
% Function to create point cloud for wheel loader grapple

% Copyright 2023-2025 The MathWorks, Inc.

% Point cloud on GrappleRake single tooth 
% Extracted from CAD geometry
pcGrappleRakeTooth = [...
    1.02235000 -3.36736365+0.02 0.90702463;
    1.02235000 -3.26876418+0.02 0.88781863;
    1.02235000 -3.17016471+0.02 0.86861263;
    1.02235000 -3.07156524 0.84940663;
    1.02235000 -2.97203936 0.83968047;
    1.02235000 -2.87251347 0.82995431;
    1.02235000 -2.77298759 0.82022816;
    1.02235000 -2.67346170 0.81050200;
    1.02235000 -2.57203921 0.82018338
    1.02235000 -2.45933438 0.94531480];

% number of teeth
nTeeth = 10;
offsetVal = 0.22720309; % offset value for each tooth along x direction

% initialize Grapple Rake point cloud matrix
ptcld_rake = zeros(size(pcGrappleRakeTooth,1)*nTeeth,3);

% offset x value for each tooth
for ii = 1:nTeeth
    startRowIdx = (ii-1)*size(pcGrappleRakeTooth,1) + 1;
    endRowIdx = startRowIdx + size(pcGrappleRakeTooth,1) - 1;
    ptcld_rake(startRowIdx:endRowIdx,1) = pcGrappleRakeTooth(:,1) ...
        - offsetVal*(ii-1);
    ptcld_rake(startRowIdx:endRowIdx,2) = pcGrappleRakeTooth(:,2);
    ptcld_rake(startRowIdx:endRowIdx,3) = pcGrappleRakeTooth(:,3);
end

% Left Toothbar
% point cloud on Grapple toothbar single tooth (extracted from SW)
pcToothbar = [0.90875556 -3.32343901 0.93021689;
    0.90875556 -3.30369317 0.96801692;
    0.90875556 -3.34464028 0.88963068;
    0.90875556 -3.28460897 1.00455033;
    0.90875556 -3.25556200 1.06015579;
    0.90875556 -3.21615548 1.11477643;
    0.90875556 -3.16957561 1.15959394];

nTeeth = 2; % for each toothbar
offsetVal = 0.45437778; % offset value for each tooth along x direction

% initialize Grapple Left Toothbar cloud matrix
ptcld_toothL = zeros(size(pcToothbar,1)*nTeeth,3);
for ii = 1:nTeeth
    startRowIdx = (ii-1)*size(pcToothbar,1) + 1;
    endRowIdx = startRowIdx + size(pcToothbar,1) - 1;
    ptcld_toothL(startRowIdx:endRowIdx,1) = pcToothbar(:,1) ...
        - offsetVal*(ii-1);
    ptcld_toothL(startRowIdx:endRowIdx,2) = pcToothbar(:,2);
    ptcld_toothL(startRowIdx:endRowIdx,3) = pcToothbar(:,3);
end


% offset the pcToothbar x value by the right toothbar offset position from
% left toothbar
pcToothbar(:,1) = pcToothbar(:,1) - 0.90875555;

% initialize Grapple Right Toothbar cloud matrix
ptcld_toothR = zeros(size(pcToothbar,1)*nTeeth,3);
for ii = 1:nTeeth
    startRowIdx = (ii-1)*size(pcToothbar,1) + 1;
    endRowIdx = startRowIdx + size(pcToothbar,1) - 1;
    ptcld_toothR(startRowIdx:endRowIdx,1) = pcToothbar(:,1) ...
        - offsetVal*(ii);
    ptcld_toothR(startRowIdx:endRowIdx,2) = pcToothbar(:,2);
    ptcld_toothR(startRowIdx:endRowIdx,3) = pcToothbar(:,3);
end

grapple_ptcld.rake   = ptcld_rake;
grapple_ptcld.toothL = ptcld_toothL; 
grapple_ptcld.toothR = ptcld_toothR;

end


