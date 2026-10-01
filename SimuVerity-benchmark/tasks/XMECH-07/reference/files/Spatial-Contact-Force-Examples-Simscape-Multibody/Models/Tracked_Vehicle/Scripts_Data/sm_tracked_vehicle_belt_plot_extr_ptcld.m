% Code to plot extrusion with point cloud sm_tread_drive_gridsurface

% Copyright 2025-2026 The MathWorks, Inc.

Extr_Data_TriangleRounded_Holes(...
    belt.l,belt.h,belt.xlen,0,belt.rad,'plot');

hold on

xminPtcld = min(belt.ptcld.outline(:,1));
xmaxPtcld = max(belt.ptcld.outline(:,1));
lineExtra = 0.1*(xmaxPtcld-xminPtcld);

tread_ptcld_inds = find(belt.ptcld.outline(:,2)<=max_height_ptcld);
tread_ptcld_excl = find(belt.ptcld.outline(:,2)>max_height_ptcld);
tread_ptcld_set = belt.ptcld.outline(tread_ptcld_inds,:);

plot(belt.ptcld.outline(tread_ptcld_inds,1),belt.ptcld.outline(tread_ptcld_inds,2),'c*')
plot(belt.ptcld.outline(tread_ptcld_excl,1),belt.ptcld.outline(tread_ptcld_excl,2),'ko')

hold off

title('Belt Extrusion and Point Cloud')
