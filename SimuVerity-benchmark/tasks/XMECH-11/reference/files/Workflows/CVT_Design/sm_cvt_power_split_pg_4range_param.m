function cvtPar = sm_cvt_power_split_pg_4range_param(varargin)
% Copyright 2023-2025 The MathWorks, Inc.

if (nargin==0)
    clrSet   = 'default';
    sizeSet  = 'default';
elseif(nargin==1)
    clrSet = varargin{1};
    HMPST  = '';
elseif(nargin==2)
    clrSet = varargin{1};
    HMPST  = varargin{2};
end
cvtPar.ratioInp.dt = [0 10 10    10    10    0.2    10       10     10       10  0.2      10       10     0.2   10     10     0.2      10      10    0.2   10   10   10];
cvtPar.ratioInp.t  = cumsum(cvtPar.ratioInp.dt);

%cvtPar.ratioInp.t  = [0 10 15    20    30.9  40.1    50      55.6   60       65.6  65.7   70       73     73.2  78     81.5     81.7   85      110   110.1 115   141   146];
cvtPar.ratioInp.r  = [0 0  0.105 0.105 0.2135 0.2145  0.2145 0.33175 0.33175 0.445  0.446  0.446   0.7173 0.7175 0.7175 0.9999  1.0000 1.0000  1.5484 1.5485 1.5485  2.1   2.1];

%% Div by 3 Whl Loader
if (~isempty('HMPST'))
    cvtPar.gear_thickness = 0.05;
    cvtPar.link_thickness = 0.01;
    cvtPar.rad_hole = 0.005;
    cvtPar.plaGear_axial_offset = cvtPar.gear_thickness*2;

    cvtPar.pg1_sun_rad = HMPST.GearTrain.PG1.Sun.PitchDiam/2;
    cvtPar.pg1_pla_rad = HMPST.GearTrain.PG1.Planet.PitchDiam/2;
    cvtPar.pg1_rin_rad = 2*cvtPar.pg1_pla_rad+cvtPar.pg1_sun_rad;

    cvtPar.pg2_sun_rad = HMPST.GearTrain.PG2.Sun.PitchDiam/2;
    cvtPar.pg2_pla_rad = HMPST.GearTrain.PG2.Planet.PitchDiam/2;
    cvtPar.pg2_rin_rad = 2*cvtPar.pg2_pla_rad+cvtPar.pg2_sun_rad;

    cvtPar.pg3_sun_rad = HMPST.GearTrain.PG3.Sun.PitchDiam/2;
    cvtPar.pg3_pla_rad = HMPST.GearTrain.PG3.Planet.PitchDiam/2;
    cvtPar.pg3_rin_rad = 2*cvtPar.pg3_pla_rad+cvtPar.pg3_sun_rad;

    cvtPar.pg4_sun_rad = HMPST.GearTrain.PG4.Sun.PitchDiam/2;
    cvtPar.pg4_pla_rad = HMPST.GearTrain.PG4.Planet.PitchDiam/2;
    cvtPar.pg4_rin_rad = 2*cvtPar.pg4_pla_rad+cvtPar.pg4_sun_rad;

    cvtPar.pg1_sun_nteeth = HMPST.GearTrain.PG1.Sun.TeethNum;
    cvtPar.pg1_pla_nteeth = HMPST.GearTrain.PG1.Planet.TeethNum;
    cvtPar.pg1_rin_nteeth = HMPST.GearTrain.PG1.Ring.TeethNum;

    cvtPar.pg2_sun_nteeth = HMPST.GearTrain.PG2.Sun.TeethNum;
    cvtPar.pg2_pla_nteeth = HMPST.GearTrain.PG2.Planet.TeethNum;
    cvtPar.pg2_rin_nteeth = HMPST.GearTrain.PG2.Ring.TeethNum;

    cvtPar.pg3_sun_nteeth = HMPST.GearTrain.PG3.Sun.TeethNum;
    cvtPar.pg3_pla_nteeth = HMPST.GearTrain.PG3.Planet.TeethNum;
    cvtPar.pg3_rin_nteeth = HMPST.GearTrain.PG3.Ring.TeethNum;

    cvtPar.pg4_sun_nteeth = HMPST.GearTrain.PG4.Sun.TeethNum;
    cvtPar.pg4_pla_nteeth = HMPST.GearTrain.PG4.Planet.TeethNum;
    cvtPar.pg4_rin_nteeth = HMPST.GearTrain.PG4.Ring.TeethNum;

    cvtPar.clr.inputE    = [0.0 0.4 0.6];
    cvtPar.clr.inputH    = [1.0 1.0 0.0]; %[0.0 0.4 0.4]%[0.2 0.6 1.0]
    cvtPar.clr.output    = [1.0 0.6 0.0];
    cvtPar.clr.ring      = [0.4 0.4 0.4];
    cvtPar.clr.pla       = [0.9372549 0.87058824 0.7176471];%[0.7058824 0.827451 0.92941177];%[0.8 0.8 0.8];
    cvtPar.clr.sun       = [1 1 1];%[0.7058824 0.827451 0.92941177];%[0.6 0.6 0.6]; %[0.8 0.8 0.3]
    cvtPar.clr.carr      = [0.5 0.5 0.5];

    % Standard Colors
    if(strcmp(clrSet,'InputOutput'))
        cvtPar.clr.pg1.ring  = cvtPar.clr.inputE;
        cvtPar.clr.pg2.ring  = cvtPar.clr.ring;
        cvtPar.clr.pg3.ring  = cvtPar.clr.ring;
        cvtPar.clr.pg4.ring  = cvtPar.clr.ring;
        cvtPar.clr.pg1.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg2.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg3.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg4.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg1.carr  = cvtPar.clr.carr;
        cvtPar.clr.pg2.carr  = cvtPar.clr.carr;
        cvtPar.clr.pg3.carr  = cvtPar.clr.carr;
        cvtPar.clr.pg4.carr  = cvtPar.clr.output;
        cvtPar.clr.pg1.sun   = cvtPar.clr.inputH;
        cvtPar.clr.pg2.sun   = cvtPar.clr.sun;
        cvtPar.clr.pg3.sun   = cvtPar.clr.sun;
        cvtPar.clr.pg4.sun   = cvtPar.clr.sun;
    else
        cvtPar.clr.pg1.ring  = cvtPar.clr.ring;
        cvtPar.clr.pg2.ring  = cvtPar.clr.ring;
        cvtPar.clr.pg3.ring  = cvtPar.clr.ring;
        cvtPar.clr.pg4.ring  = cvtPar.clr.ring;
        cvtPar.clr.pg1.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg2.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg3.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg4.pla   = cvtPar.clr.pla;
        cvtPar.clr.pg1.carr  = cvtPar.clr.carr;
        cvtPar.clr.pg2.carr  = cvtPar.clr.carr;
        cvtPar.clr.pg3.carr  = cvtPar.clr.carr;
        cvtPar.clr.pg4.carr  = cvtPar.clr.carr;
        cvtPar.clr.pg1.sun   = cvtPar.clr.sun;
        cvtPar.clr.pg2.sun   = cvtPar.clr.sun;
        cvtPar.clr.pg3.sun   = cvtPar.clr.sun;
        cvtPar.clr.pg4.sun   = cvtPar.clr.sun;
    end
else
    %%  ORIG WHL LOADER
    gear_thickness = 0.1;
    link_thickness = 0.01;
    rad_hole = 0.005;
    plaGear_axial_offset = 0.4;

    pg1_sun_rad = 0.0780;
    pg1_pla_rad = 0.0600;
    pg1_rin_rad = 2*pg1_pla_rad+pg1_sun_rad;

    pg2_sun_rad = 0.0980;
    pg2_pla_rad = 0.0500;
    pg2_rin_rad = 2*pg2_pla_rad+pg2_sun_rad;

    pg3_sun_rad = 0.0500;
    pg3_pla_rad = 0.0740;
    pg3_rin_rad = 2*pg3_pla_rad+pg3_sun_rad;

    pg4_sun_rad = 0.0500;
    pg4_pla_rad = 0.0740;
    pg4_rin_rad = 2*pg4_pla_rad+pg4_sun_rad;

    pg1_sun_nteeth = 39;
    pg1_pla_nteeth = 30;
    pg1_rin_nteeth = 99;

    pg2_sun_nteeth = 49;
    pg2_pla_nteeth = 25;
    pg2_rin_nteeth = 99;

    pg3_sun_nteeth = 25;
    pg3_pla_nteeth = 37;
    pg3_rin_nteeth = 99;

    pg4_sun_nteeth = 25;
    pg4_pla_nteeth = 37;
    pg4_rin_nteeth = 99;
end
