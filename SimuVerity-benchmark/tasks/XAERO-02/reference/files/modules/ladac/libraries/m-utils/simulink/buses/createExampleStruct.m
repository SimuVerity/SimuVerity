
% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

clear a
a.test1 = 1;
a.test2 = [2 4 6 8];
a.test3 = uint8(3); 
struct2bus(a, "busa");
