% Copyright 2016-2025 The MathWorks(TM), Inc.

if (exist('youBot_optres_noFriction.mat','file'))
    load youBot_optres_noFriction.mat
    youBot_optim_plotEExyz
else
    web('youBot_optim_res_noFriction.html');
end