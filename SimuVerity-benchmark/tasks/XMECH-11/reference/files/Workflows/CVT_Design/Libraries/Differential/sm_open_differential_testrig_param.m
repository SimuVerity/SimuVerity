% Parameters for sm_open_differential_testrig
% Copyright 2017-2025 The MathWorks, Inc.

odiff.pinion.rad = 0.075;
odiff.pinion.color = [0.0 0.4 0.6];
odiff.pinion_shaft.rad = 0.02;
odiff.ring.rad = 0.175;
odiff.ring.color = [0.6 0.6 0.6];
odiff.ring.radh = 0.075;
odiff.spider.rad = 0.095;
odiff.spider.len = 0.02;
odiff.spider.color = [0.6 0.6 0.6];
odiff.spider.ring.xsec = [
    odiff.spider.rad odiff.spider.len/2; 
    odiff.ring.radh odiff.spider.len/2; 
    odiff.ring.radh -odiff.spider.len/2; 
    odiff.spider.rad -odiff.spider.len/2];

odiff.spider.bracket.th = (odiff.spider.rad-odiff.ring.radh)/2.2;
odiff.spider.bracket.wi = (odiff.spider.rad-odiff.ring.radh)/2.2*4;

odiff.spider.bracket.xyz = [odiff.spider.bracket.wi odiff.spider.bracket.th (odiff.pinion.rad-odiff.spider.len)];
odiff.spider.bracket.endxyz = [odiff.spider.bracket.wi odiff.spider.bracket.th odiff.spider.len];

odiff.spider.bracket.pin.rad = (odiff.spider.rad-odiff.ring.radh)/2;

odiff.diffpinion.rad = 0.05;
odiff.diffpinion.color = [0.55 0.7 0.4];
odiff.diffpinion.thickness = 0.02;
odiff.axlegear.rad = 0.05;
odiff.axlegear.color = [0.87 0.60 0.0];
odiff.axlegear.thickness = 0.02;

odiff.spider.bracket.pin.len = ...
    (odiff.spider.rad+odiff.ring.radh)/2-odiff.axlegear.rad-odiff.spider.bracket.th/2;
