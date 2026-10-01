%function [ratchet_wheel, pawl, line, contact_WR, ratchet_arm] = sm_ratchet_pawl_create_wheel
%% Ratchet Wheel

% Parameters for extrusion
r_outer = 0.10;
r_inner = 0.09;
n_teeth = 30;

%Extr_Data_Ratchet_Wheel(r_outer,r_inner,n_teeth,'plot')
ratchet_wheel.xsect = Extr_Data_Ratchet_Wheel(r_outer,r_inner,n_teeth);

% Other parameters
ratchet_wheel.depth = 0.01;

%% Line Contact Geometry
% Wrap points
rwhl_circ = [ratchet_wheel.xsect;ratchet_wheel.xsect(1,:)];

% Get distances between segment ends points along x and y
rwhl_dx   = diff(rwhl_circ(:,1));
rwhl_dy   = diff(rwhl_circ(:,2));

% Calculate angle of each segment
line.q    = atan2d(rwhl_dy,rwhl_dx);

% Calculate center of each segment
line.o    = (rwhl_circ+circshift(rwhl_circ,-1,1))/2;

% Calculate length of each segment
line.l    = sqrt(sum((ratchet_wheel.xsect - circshift(ratchet_wheel.xsect,-1,1)).^2,2));


% Plot centers
%{ 
hold on
for i = 1:length(line.l)
    plot(line.o(i,1),line.o(i,2),'gd')
end
hold off
%}

%% Contact and Friction
contact_WR.k = 1e6;
contact_WR.b = 1e4;
contact_WR.x = 1e-3;
contact_WR.s = 0.5;
contact_WR.d = 0.3;
contact_WR.v = 1e-2;

%% Pawl
pArcRad    = 0.05;
pArcDeg    = 60;
pArcOffset = 0.01;
pArcScaleY = 1.04;
pArcScaleX = 1.1;
ptipRad    = 0.002;

[pawl_driver.xsect, pawl_driver.cFrame] = Extr_Data_Pawl(pArcRad,pArcDeg,pArcOffset,pArcScaleY,pArcScaleX,ptipRad);
[pawl_locking.xsect, pawl_locking.cFrame] = Extr_Data_Pawl(pArcRad,pArcDeg,pArcOffset,pArcScaleY,pArcScaleX,ptipRad);
%Extr_Data_Pawl(pArcRad,pArcDeg,pArcOffset,pArcScaleY,pArcScaleX,ptipRad,'plot');

pawl_driver.tip_rad = ptipRad;
pawl_locking.offset = 0.12;
pawl_driver.offset = 0.12;

pawl_locking.depth = 0.01;
pawl_driver.depth = 0.01;

pawl_locking.tip_rad = ptipRad;
pawl_driver.tip_rad = ptipRad;

%% Arm
ratchet_arm.length = 0.2; 
ratchet_arm.depth  = 0.01;


